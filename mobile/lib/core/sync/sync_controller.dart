import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_exception.dart';
import '../providers.dart';

enum EstadoSync { pendiente, sincronizando, alDia, sinConexion, error }

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

  /// Espera tras un cambio antes de subir: agrupa una tanda de notas en un solo envío.
  static const _espera = Duration(seconds: 5);

  /// Margen del cursor: lo guardado justo al cortarlo entra en el próximo pull. Mezclar
  /// dos veces lo mismo no cambia nada.
  static const _margen = Duration(minutes: 2);

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
    if (ref.read(sessionProvider) == null) return;
    if (_enCurso) {
      _otraVez = true;
      return;
    }
    _enCurso = true;
    state = SyncState(EstadoSync.sincronizando, ultima: state.ultima);
    try {
      do {
        _otraVez = false;
        await _ciclo();
      } while (_otraVez);
      state = SyncState(EstadoSync.alDia, ultima: DateTime.now());
      ref.invalidate(clasesProvider);
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

    // Una clase por envío: si una falla, las demás ya quedaron respaldadas.
    for (final pendiente in await repo.pendientes()) {
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
        rethrow;
      }
      await repo.marcarSubida(pendiente.id, pendiente.version);
    }

    final cursor = await repo.cursor();
    final desde = cursor == null ? null : DateTime.parse(cursor).subtract(_margen).toUtc().toIso8601String();
    final pull = await api.get('/sync/pull', query: {'desde': desde}, parse: (d) => d as Map<String, dynamic>);
    for (final clase in (pull['clases'] as List).cast<Map<String, dynamic>>()) {
      await repo.aplicar(clase);
    }
    await repo.guardarCursor(pull['hasta'] as String);
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncState>(SyncController.new);
