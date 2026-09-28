import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/avisos/avisos.dart';
import '../../core/avisos/recordatorio.dart';
import '../../core/preferencias.dart';
import '../../ui/estado_vacio.dart';
import '../../ui/shell.dart';

/// Campana del inicio con el número de avisos pendientes.
class BotonAvisos extends ConsumerWidget {
  const BotonAvisos({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avisos = ref.watch(avisosProvider).valueOrNull ?? const [];
    final urgentes = avisos.any((a) => a.urgente);
    return IconButton(
      tooltip: avisos.isEmpty ? 'Avisos' : '${avisos.length} avisos',
      onPressed: () => context.go('/inicio/avisos'),
      icon: Badge(
        isLabelVisible: avisos.isNotEmpty,
        label: Text('${avisos.length}'),
        backgroundColor: urgentes ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
        child: Icon(avisos.isEmpty ? Icons.notifications_none : Icons.notifications),
      ),
    );
  }
}

/// Lo que el docente tiene pendiente, cada aviso lleva a donde se resuelve. Se van solos
/// al resolverlos; también se pueden descartar.
class AvisosPage extends ConsumerWidget {
  const AvisosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avisos = ref.watch(avisosProvider);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/inicio')),
        title: const Text('Avisos'),
      ),
      body: avisos.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (lista) => ContenidoCentrado(
          maxAncho: 720,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (Recordatorio.disponible) const _Recordatorio(),
              if (lista.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: EstadoVacio(
                    icono: Icons.task_alt,
                    titulo: 'Estás al día',
                    mensaje: 'Aquí aparece lo que falte calificar, pasar lista, cerrar o exportar.',
                  ),
                )
              else
                for (final aviso in lista) _TarjetaAviso(aviso: aviso),
            ],
          ),
        ),
      ),
    );
  }
}

class _TarjetaAviso extends ConsumerWidget {
  const _TarjetaAviso({required this.aviso});

  final Aviso aviso;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        leading: Icon(aviso.tipo.icono, color: aviso.urgente ? scheme.error : scheme.primary),
        title: Text(aviso.titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(aviso.detalle),
        onTap: aviso.ruta == null ? null : () => context.go(aviso.ruta!),
        trailing: IconButton(
          tooltip: 'Descartar',
          icon: const Icon(Icons.close),
          onPressed: () => ref.read(descartadosProvider.notifier).descartar(aviso.id),
        ),
      ),
    );
  }
}

class _Recordatorio extends ConsumerWidget {
  const _Recordatorio();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activo = ref.watch(banderaProvider(Bandera.recordatorio));
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: SwitchListTile(
        value: activo,
        title: const Text('Recordatorio a las 5:00 p. m.'),
        subtitle: const Text('Una notificación con tus pendientes del día, si los hay.'),
        onChanged: (valor) async {
          final bandera = ref.read(banderaProvider(Bandera.recordatorio).notifier);
          if (!valor) {
            await bandera.poner(false);
            await Recordatorio.cancelar();
            return;
          }
          if (await Recordatorio.pedirPermiso()) {
            await bandera.poner(true);
          } else if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Permite las notificaciones de ProfeApp en los ajustes del teléfono.')));
          }
        },
      ),
    );
  }
}
