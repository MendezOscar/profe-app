import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/cobro.dart';
import '../../core/providers.dart';
import '../../ui/estado_vacio.dart';
import '../../ui/shell.dart';
import 'admin_comun.dart';
import '../../theme/tokens.dart';
import '../../ui/esqueleto.dart';
import '../../ui/estado_error.dart';

final centroProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
    (ref) => ref.watch(apiClientProvider).get('/centro', parse: (d) => d as Map<String, dynamic>));

/// Panel del administrador de un centro: licencia, docentes y su avance. No ve ni edita
/// notas: sólo cuántas asignaturas, actividades y parciales cerrados lleva cada docente.
class CentroPage extends ConsumerWidget {
  const CentroPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final centro = ref.watch(centroProvider);
    final nombre = centro.valueOrNull?['institucion']?['nombre'] as String?;

    return Scaffold(
      appBar: AppBar(
        title: Text(nombre ?? 'Mi centro'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () => ref.invalidate(centroProvider),
            icon: const Icon(Icons.refresh),
          ),
          const MenuCuentaAdmin(),
        ],
      ),
      floatingActionButton: centro.hasValue
          ? FloatingActionButton.extended(
              shape: const RoundedRectangleBorder(),
              onPressed: () => _agregar(context, ref),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Agregar docente'),
            )
          : null,
      body: centro.when(
        loading: () => const EsqueletoLista(filas: 6, conTarjeta: true),
        error: (e, _) => EstadoError(error: e, reintentar: () => ref.invalidate(centroProvider)),
        data: (datos) {
          final institucion = datos['institucion'] as Map<String, dynamic>;
          final docentes = (datos['docentes'] as List).cast<Map<String, dynamic>>();
          return RefreshIndicator(
            onRefresh: () => ref.refresh(centroProvider.future),
            child: ContenidoCentrado(
              maxAncho: 1100,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.bajoBotonFlotante),
                children: [
                  _Licencia(institucion: institucion),
                  const SizedBox(height: Espacio.xl),
                  if (docentes.isEmpty)
                    const EstadoVacio(
                      icono: Icons.groups_outlined,
                      titulo: 'Agrega a tus docentes',
                      mensaje: 'Cada docente recibe una contraseña temporal para entrar a la app. '
                          'Aquí verás cómo avanza cada uno con sus parciales.',
                    )
                  else ...[
                    Text('DOCENTES', style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: Espacio.s),
                    for (final d in docentes) _Docente(docente: d),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _agregar(BuildContext context, WidgetRef ref) async {
    final cuenta = await pedirNombreYCorreo(context, ref, titulo: 'Agregar docente', ruta: '/centro/docentes');
    if (cuenta == null || !context.mounted) return;
    ref.invalidate(centroProvider);
    await mostrarCuentaCreada(context, cuenta, titulo: 'Docente agregado');
  }
}

class _Licencia extends StatelessWidget {
  const _Licencia({required this.institucion});

  final Map<String, dynamic> institucion;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final usados = institucion['docentes'] as int;
    final cupo = institucion['maxDocentes'] as int;
    final cobro = Cobro.fromJson(institucion['cobro'] as Map<String, dynamic>);
    final lleno = usados >= cupo;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Espacio.l),
        child: Wrap(
          spacing: 32,
          runSpacing: 16,
          children: [
            _Dato(etiqueta: 'Plan', valor: planesCentro[institucion['plan']] ?? '${institucion['plan']}'),
            _Dato(etiqueta: 'Docentes', valor: '$usados de $cupo', alerta: lleno),
            _Dato(
              etiqueta: 'Pagado hasta',
              valor: cobro.pagadoHasta == null ? 'Sin vencimiento' : fechaCorta(cobro.pagadoHasta!.toIso8601String()),
              alerta: cobro.pideAtencion,
            ),
            if (cobro.pideAtencion)
              SizedBox(
                width: 320,
                child: Text(
                  [cobro.mensaje, if (kIsWeb && cobro.comoPagar != null) 'Cómo pagar: ${cobro.comoPagar}'].join('\n'),
                  style: text.bodySmall?.copyWith(color: scheme.error),
                ),
              ),
            if (lleno)
              SizedBox(
                width: 320,
                child: Text('El cupo está lleno. Desactiva a un docente o escríbenos para ampliar el plan.',
                    style: text.bodySmall?.copyWith(color: scheme.error)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.etiqueta, required this.valor, this.alerta = false});

  final String etiqueta;
  final String valor;
  final bool alerta;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(etiqueta.toUpperCase(), style: text.labelSmall),
        Text(valor,
            style: text.titleLarge?.copyWith(color: alerta ? Theme.of(context).colorScheme.error : null)),
      ],
    );
  }
}

class _Docente extends ConsumerWidget {
  const _Docente({required this.docente});

  final Map<String, dynamic> docente;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final activo = docente['activo'] as bool;
    final id = docente['id'] as String;

    Future<void> accion(String opcion) async {
      final api = ref.read(apiClientProvider);
      final messenger = ScaffoldMessenger.of(context);
      try {
        if (opcion == 'clave') {
          final cuenta = await api.post('/centro/docentes/$id/restablecer-clave', parse: (d) => d as Map<String, dynamic>);
          if (context.mounted) await mostrarCuentaCreada(context, cuenta, titulo: 'Contraseña restablecida');
        } else {
          await api.post<void>('/centro/docentes/$id/${activo ? 'desactivar' : 'activar'}');
          messenger.showSnackBar(SnackBar(content: Text(activo ? 'Docente desactivado.' : 'Docente activado.')));
        }
        ref.invalidate(centroProvider);
      } on ApiException catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.isNetworkError ? 'Necesitas internet.' : e.message)));
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: Espacio.s),
      child: Card(
        color: activo ? null : scheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.m, Espacio.xs, Espacio.m),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text('${docente['nombre']}', style: text.titleMedium)),
                        if (!activo) ...[
                          const SizedBox(width: Espacio.s),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: Espacio.s, vertical: Espacio.xxs),
                            color: scheme.errorContainer,
                            child: Text('Inactivo', style: text.labelSmall?.copyWith(color: scheme.onErrorContainer)),
                          ),
                        ],
                      ],
                    ),
                    Text('${docente['email']} · último acceso: ${fechaCorta(docente['ultimoAcceso'] as String?)}',
                        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: Espacio.s),
                    Wrap(
                      spacing: 16,
                      children: [
                        Text(_cuantos(docente['asignaturas'] as int, 'asignatura', 'asignaturas'), style: text.labelLarge),
                        Text(_cuantos(docente['actividades'] as int, 'actividad', 'actividades'), style: text.labelLarge),
                        Text(_cuantos(docente['parcialesCerrados'] as int, 'parcial cerrado', 'parciales cerrados'),
                            style: text.labelLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Opciones',
                onSelected: accion,
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'clave', child: Text('Restablecer contraseña')),
                  PopupMenuItem(value: 'estado', child: Text(activo ? 'Desactivar' : 'Activar')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _cuantos(int n, String uno, String varios) => '$n ${n == 1 ? uno : varios}';
