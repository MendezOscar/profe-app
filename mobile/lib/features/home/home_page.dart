import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/providers.dart';

/// Lista de clases del docente. Por ahora sólo el estado vacío: las clases nacen
/// al importar el cuadro de notas que se descarga de SACE (siguiente fase).
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis clases'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.upload_file_outlined, size: 56, color: scheme.primary),
              const SizedBox(height: 16),
              Text('Hola, ${session?.fullName ?? 'docente'}', style: text.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'Descarga el cuadro de notas de cada clase en SACE e impórtalo aquí. '
                'Después podrás llenarlo sin internet.',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              const FilledButton.icon(
                onPressed: null,
                icon: Icon(Icons.file_open_outlined),
                label: Text('Importar cuadro de SACE'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
