import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/sync/sync_controller.dart';

/// Nube que dice cómo va el respaldo. Tocarla sincroniza en el momento.
class IndicadorSync extends ConsumerWidget {
  const IndicadorSync({super.key, this.conTexto = false});

  /// En la barra lateral de pantallas anchas se muestra también el texto.
  final bool conTexto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);
    final (icono, corto, largo) = switch (sync.estado) {
      EstadoSync.sincronizando => (Icons.cloud_sync_outlined, 'Sincronizando…', 'Sincronizando…'),
      EstadoSync.alDia => (Icons.cloud_done_outlined, 'Respaldado', 'Todo respaldado en la nube'),
      EstadoSync.sinConexion =>
        (Icons.cloud_off_outlined, 'Sin conexión', 'Sin conexión: todo queda guardado en este dispositivo'),
      EstadoSync.error => (Icons.sync_problem_outlined, 'Error al respaldar', 'No se pudo respaldar: ${sync.mensaje ?? ''}'),
      EstadoSync.pendiente => (Icons.cloud_upload_outlined, 'Pendiente', 'Pendiente de respaldar'),
      EstadoSync.soloLectura => (Icons.lock_outline, 'Sin respaldo', sync.mensaje ?? 'Lo nuevo no se respalda por ahora'),
    };
    final color = sync.estado == EstadoSync.error || sync.estado == EstadoSync.soloLectura
        ? Theme.of(context).colorScheme.error
        : null;
    final accion = sync.estado == EstadoSync.sincronizando
        ? null
        : () => ref.read(syncControllerProvider.notifier).sincronizar();

    if (conTexto) {
      return TextButton.icon(
        onPressed: accion,
        icon: Icon(icono, color: color),
        label: Text(corto, style: TextStyle(color: color)),
      );
    }
    return IconButton(tooltip: largo, onPressed: accion, icon: Icon(icono, color: color));
  }
}
