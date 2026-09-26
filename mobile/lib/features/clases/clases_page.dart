import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/models/clase.dart';
import '../../core/providers.dart';
import '../../core/sace/hoja.dart';
import '../../core/sync/sync_controller.dart';

/// Clases del docente. Cada una nace de importar el cuadro de notas descargado de SACE;
/// importar otra vez el mismo cuadro la actualiza.
class ClasesPage extends ConsumerWidget {
  const ClasesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clases = ref.watch(clasesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis clases'),
        actions: [
          const _EstadoSync(),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: clases.valueOrNull?.isNotEmpty == true
          ? FloatingActionButton.extended(
              onPressed: () => importarCuadro(context, ref),
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Importar cuadro'),
            )
          : null,
      body: clases.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('No se pudo abrir la base local: $error')),
        data: (lista) => lista.isEmpty
            ? const _SinClases()
            : RefreshIndicator(
                onRefresh: () => ref.read(syncControllerProvider.notifier).sincronizar(),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: lista.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _ClaseTile(clase: lista[i]),
                ),
              ),
      ),
    );
  }
}

Future<void> importarCuadro(BuildContext context, WidgetRef ref) async {
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['xlsx', 'xls'],
    withData: true,
  );
  final file = picked?.files.single;
  if (file?.bytes == null || !context.mounted) return;

  try {
    final resultado = await ref.read(clasesRepositoryProvider).importar(file!.bytes!, file.name);
    ref.invalidate(clasesProvider);
    ref.invalidate(claseProvider(resultado.claseId));
    ref.read(syncControllerProvider.notifier).programar();
    if (!context.mounted) return;

    final mensaje = resultado.nueva
        ? 'Clase importada: ${resultado.alumnos} alumnos.'
        : resultado.columnasNuevas.isEmpty
            ? 'Clase actualizada. Lo que ya habías capturado se conservó.'
            : 'Clase actualizada. Columnas nuevas: ${resultado.columnasNuevas.join(', ')}.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
    context.push('/clases/${resultado.claseId}');
  } on FormatoNoSoportado catch (error) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No se pudo importar'),
        content: Text(error.message),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
      ),
    );
  }
}

class _ClaseTile extends StatelessWidget {
  const _ClaseTile({required this.clase});

  final ClaseResumen clase;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: ListTile(
        onTap: () => context.push('/clases/${clase.id}'),
        title: Text(clase.asignatura),
        subtitle: Text([clase.gradoSeccion, clase.jornada].where((t) => t.isNotEmpty).join(' · ')),
        trailing: Text('${clase.alumnos} alumnos', style: Theme.of(context).textTheme.labelMedium),
      ),
    );
  }
}

class _SinClases extends ConsumerWidget {
  const _SinClases();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
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
              'Descarga el cuadro de notas de cada clase en SACE (Notas → Descargar Archivos Notas) '
              'e impórtalo aquí. Después podrás llenarlo sin internet.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => importarCuadro(context, ref),
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Importar cuadro de SACE'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nube en la barra: cómo va el respaldo. Tocarla sincroniza en el momento.
class _EstadoSync extends ConsumerWidget {
  const _EstadoSync();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);
    final (icono, texto) = switch (sync.estado) {
      EstadoSync.sincronizando => (Icons.cloud_sync_outlined, 'Sincronizando…'),
      EstadoSync.alDia => (Icons.cloud_done_outlined, 'Respaldado en la nube'),
      EstadoSync.sinConexion => (Icons.cloud_off_outlined, 'Sin conexión: todo queda guardado en el teléfono'),
      EstadoSync.error => (Icons.sync_problem_outlined, 'No se pudo respaldar: ${sync.mensaje ?? ''}'),
      EstadoSync.pendiente => (Icons.cloud_upload_outlined, 'Pendiente de respaldar'),
    };
    return IconButton(
      tooltip: texto,
      onPressed: sync.estado == EstadoSync.sincronizando
          ? null
          : () => ref.read(syncControllerProvider.notifier).sincronizar(),
      icon: Icon(icono),
    );
  }
}
