import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_exception.dart';
import '../core/sync/sync_controller.dart';
import '../theme/tokens.dart';
import 'estado_vacio.dart';

/// Algo salió mal al cargar una pantalla: qué pasó en palabras del docente, que lo suyo
/// sigue a salvo y un botón para reintentar. Nunca el texto crudo de la excepción.
class EstadoError extends StatelessWidget {
  const EstadoError({super.key, required this.error, required this.reintentar});

  final Object error;
  final VoidCallback reintentar;

  @override
  Widget build(BuildContext context) {
    final (icono, titulo, mensaje) = switch (error) {
      ApiException(isNetworkError: true) => (
          Icons.cloud_off_outlined,
          'Sin conexión',
          'No se pudo hablar con el servidor. Lo que ya tienes en este dispositivo sigue guardado.',
        ),
      ApiException(:final message) => (Icons.error_outline, 'No se pudo cargar', message),
      _ => (
          Icons.error_outline,
          'No se pudo abrir esta pantalla',
          'Tus datos siguen guardados en este dispositivo. Intenta de nuevo; si se repite, '
              'escríbenos desde Cuenta → Ayuda.',
        ),
    };
    return EstadoVacio(
      icono: icono,
      titulo: titulo,
      mensaje: mensaje,
      tono: TonoEstado.error,
      accion: FilledButton.icon(onPressed: reintentar, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
    );
  }
}

/// Lo mismo para una pantalla de detalle, con su barra para poder volver.
class PaginaError extends StatelessWidget {
  const PaginaError({super.key, required this.error, required this.reintentar});

  final Object error;
  final VoidCallback reintentar;

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(), body: EstadoError(error: error, reintentar: reintentar));
}

/// Franja al pie del contenido cuando el teléfono se queda sin red: avisa sin bloquear,
/// porque sin conexión la app funciona igual.
class AvisoSinConexion extends ConsumerWidget {
  const AvisoSinConexion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sinRed = ref.watch(syncControllerProvider.select((s) => s.estado == EstadoSync.sinConexion));
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: !sinRed
          ? const SizedBox(width: double.infinity)
          : Semantics(
              liveRegion: true,
              child: Container(
                width: double.infinity,
                color: scheme.secondary,
                padding: const EdgeInsets.symmetric(horizontal: Espacio.l, vertical: Espacio.s),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      Icon(Icons.cloud_off_outlined, size: 18, color: scheme.onSecondary),
                      const SizedBox(width: Espacio.s),
                      Expanded(
                        child: Text(
                          'Sin conexión. Puedes seguir trabajando: se respalda solo al volver la señal.',
                          style: text.bodySmall?.copyWith(color: scheme.onSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
