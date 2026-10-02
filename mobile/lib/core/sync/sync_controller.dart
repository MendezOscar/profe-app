import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_exception.dart';
import '../auth/auth_controller.dart';
import '../local/sync_repository.dart';
import '../preferencias.dart';
import '../providers.dart';

/// Última sincronización correcta, para avisar si pasa mucho sin respaldo.
const claveUltimaSync = 'profeapp.ultima_sync';

/// soloLectura: el plan venció y pasó la gracia; se baja lo de otros dispositivos, pero no
/// se sube nada hasta que se renueve. Lo de este teléfono queda guardado y pendiente.
enum EstadoSync { pendiente, sincronizando, alDia, sinConexion, error, soloLectura }

class SyncState {
  const SyncState(this.estado, {this.mensaje, this.ultima});

  final EstadoSync estado;
  final String? mensaje;
  final DateTime? ultima;
}

/// Respalda en el servidor lo capturado en el teléfono y trae lo hecho en otros
/// dispositivos. Corre al abrir la app, al volver la conexión y unos segundos después de
/// cada cambio. Sin red no pasa nada: todo queda en la base local hasta el próximo intento.
class SyncController extends Notifier<SyncState> {
  StreamSubscription<List<ConnectivityResult>>? _conexion;
  Timer? _programado;
  bool _enCurso = false;
  bool _otraVez = false;

  /// Lo que el servidor rechazó en este ciclo por el plan (sólo lectura o tope de asignaturas).
  String? _rechazo;

  /// Espera tras un cambio antes de subir: agrupa una tanda de notas en un solo envío.
  static const _espera = Duration(seconds: 5);

  /// Margen del cursor: lo guardado justo al cortarlo entra en el próximo pull. Mezclar
  /// dos veces lo mismo no cambia nada.
  static const _margen = Duration(minutes: 2);

  static const _tanda = 500;

  @override
  SyncState build() {
    // Otro usuario, otra base: se vuelve a empezar.
    ref.watch(sessionProvider.select((s) => s?.userId));
    _conexion = Connectivity().onConnectivityChanged.listen((resultados) {
      if (!resultados.contains(ConnectivityResult.none)) sincronizar();
    });
    ref.onDispose(() {
      _conexion?.cancel();
      _programado?.cancel();
    });
    Future.microtask(sincronizar);
    return const SyncState(EstadoSync.pendiente);
  }

  /// Para después de un cambio local: se sube al rato, no en cada tecla.
  void programar() {
    _programado?.cancel();
    _programado = Timer(_espera, sincronizar);
  }

  Future<void> sincronizar() async {
    final session = ref.read(sessionProvider);
    if (session == null || session.role != 'Docente' || session.mustChangePassword) return;
    if (_enCurso) {
      _otraVez = true;
      return;
    }
    _enCurso = true;
    state = SyncState(EstadoSync.sincronizando, ultima: state.ultima);
    try {
      _rechazo = null;
      do {
        _otraVez = false;
        await _ciclo();
      } while (_otraVez);
      state = _rechazo == null
          ? SyncState(EstadoSync.alDia, ultima: DateTime.now())
          : SyncState(EstadoSync.soloLectura, mensaje: _rechazo, ultima: state.ultima);
      await ref.read(preferenciasProvider).setString(claveUltimaSync, DateTime.now().toUtc().toIso8601String());
      // Lo bajado puede tocar cualquier pantalla: listas, planes, notas, plantillas.
      ref
        ..invalidate(clasesProvider)
        ..invalidate(claseProvider)
        ..invalidate(parcialesProvider)
        ..invalidate(planProvider)
        ..invalidate(planesClaseProvider)
        ..invalidate(plantillasProvider)
        ..invalidate(tableroProvider);
    } on ApiException catch (error) {
      state = error.isNetworkError
          ? SyncState(EstadoSync.sinConexion, ultima: state.ultima)
          : SyncState(EstadoSync.error, mensaje: error.message, ultima: state.ultima);
    } catch (error) {
      state = SyncState(EstadoSync.error, mensaje: '$error', ultima: state.ultima);
    } finally {
      _enCurso = false;
    }
  }

  Future<void> _ciclo() async {
    final repo = ref.read(syncRepositoryProvider);
    final api = ref.read(apiClientProvider);
    if (ref.read(sessionProvider)?.cobro?.soloLectura ?? false) {
      _rechazo = ref.read(sessionProvider)!.cobro!.mensaje;
    }

    // Una clase por envío: si una falla, las demás ya quedaron respaldadas.
    for (final pendiente in _rechazo == null ? await repo.pendientes() : const <PendienteClase>[]) {
      try {
        await api.post('/sync/push', body: {
          'clases': [pendiente.json],
        });
      } on ApiException catch (error) {
        // El servidor no tiene el archivo de esta clase: se reenvía completa la próxima vez.
        if (error.code == 'archivo_requerido') {
          await repo.forzarPlantilla(pendiente.id);
          _otraVez = true;
          continue;
        }
        // Una asignatura nueva por encima del tope del plan: queda en el teléfono y las demás siguen.
        if (error.code == 'tope_asignaturas') {
          _rechazo = error.message;
          continue;
        }
        if (await _planVencido(error)) break;
        rethrow;
      }
      await repo.marcarSubida(pendiente.id, pendiente.version, pendiente.celdas);
    }

    // El plan va aparte y por tandas: una clase con muchas actividades junta miles de notas.
    // Después de las clases, para que el servidor ya las conozca.
    final registros = ref.read(sessionProvider)?.cobro?.soloLectura ?? false
        ? const <RegistroPendiente>[]
        : await repo.registrosPendientes();
    for (var i = 0; i < registros.length; i += _tanda) {
      final tanda = registros.skip(i).take(_tanda).toList();
      try {
        await api.post('/sync/push', body: {
          'clases': const [],
          'registros': [for (final r in tanda) r.json],
        });
      } on ApiException catch (error) {
        if (await _planVencido(error)) break;
        rethrow;
      }
      await repo.marcarRegistrosSubidos(tanda);
    }

    // Por páginas y con el mismo "hasta": un primer pull con miles de notas no llega de
    // golpe. Las clases vienen en la primera página, sin archivo; el archivo se pide
    // aparte sólo si este dispositivo lo necesita.
    final cursor = await repo.cursor();
    final desde = cursor == null ? null : DateTime.parse(cursor).subtract(_margen).toUtc().toIso8601String();
    String? hasta;
    String? despues;
    for (;;) {
      final pull = await api.get('/sync/pull',
          query: {'desde': desde, 'hasta': hasta, 'despues': despues}, parse: (d) => d as Map<String, dynamic>);
      hasta ??= pull['hasta'] as String;
      for (final clase in (pull['clases'] as List).cast<Map<String, dynamic>>()) {
        if (await repo.necesitaArchivo(clase)) {
          try {
            final archivo = await api.get('/sync/archivo',
                query: {'clave': clase['clave']}, parse: (d) => d as Map<String, dynamic>);
            clase['archivoBase64'] = archivo['archivoBase64'];
          } on ApiException catch (error) {
            // Otro dispositivo la borró mientras tanto: llega su lápida en el próximo pull.
            if (error.code != 'not_found') rethrow;
          }
        }
        await repo.aplicar(clase);
      }
      // Después de las clases: los registros se enganchan a clases y alumnos que ya deben existir.
      await repo.aplicarRegistros(((pull['registros'] as List?) ?? const []).cast<Map<String, dynamic>>());
      if (pull['mas'] != true) break;
      // El servidor sigue desde el último registro entregado, sin saltar filas.
      despues = pull['siguiente'] as String;
    }
    await repo.guardarCursor(hasta);
  }

  /// El servidor dice que el plan quedó de sólo lectura: se trae el estado nuevo para que
  /// la app lo muestre, y se deja de subir. Bajar lo de otros dispositivos sigue.
  Future<bool> _planVencido(ApiException error) async {
    if (error.code != 'solo_lectura') return false;
    _rechazo = error.message;
    try {
      final me = await ref.read(apiClientProvider).get('/auth/me', parse: (d) => d as Map<String, dynamic>);
      if (me['cobro'] case final Map<String, dynamic> cobro) {
        await ref.read(authControllerProvider.notifier).cobroActualizado(cobro);
      }
    } on ApiException {
      // El aviso ya quedó con el mensaje del rechazo.
    }
    return true;
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncState>(SyncController.new);
