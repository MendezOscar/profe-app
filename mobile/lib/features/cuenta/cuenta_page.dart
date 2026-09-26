import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/providers.dart';
import '../../core/sync/sync_controller.dart';
import '../../ui/indicador_sync.dart';
import '../../ui/shell.dart';
import '../auth/cambiar_clave_dialog.dart';

class CuentaPage extends ConsumerWidget {
  const CuentaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final sync = ref.watch(syncControllerProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final ultima = sync.ultima;

    return Scaffold(
      appBar: AppBar(title: const Text('Cuenta')),
      body: ContenidoCentrado(
        maxAncho: 640,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  color: scheme.primary,
                  alignment: Alignment.center,
                  child: Text(
                    (session?.fullName.isNotEmpty ?? false) ? session!.fullName[0].toUpperCase() : '?',
                    style: text.headlineMedium?.copyWith(color: scheme.onPrimary),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(session?.fullName ?? '', style: text.titleLarge),
                      Text(session?.email ?? '', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.cloud_outlined),
                    title: const Text('Respaldo en la nube'),
                    subtitle: Text(ultima == null
                        ? 'Todavía no se ha sincronizado en esta sesión'
                        : 'Última vez: ${TimeOfDay.fromDateTime(ultima).format(context)}'),
                    trailing: const IndicadorSync(),
                  ),
                  const Divider(height: 2),
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('Cambiar contraseña'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => mostrarCambiarClave(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => ref.read(authControllerProvider.notifier).logout(),
              icon: const Icon(Icons.logout),
              label: const Text('Cerrar sesión'),
            ),
          ],
        ),
      ),
    );
  }
}
