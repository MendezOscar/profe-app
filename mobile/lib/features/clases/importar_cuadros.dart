import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/planes/calculo_parcial.dart';
import '../../core/planes/modelos.dart';
import '../../core/providers.dart';
import '../../core/sace/hoja.dart';
import '../../core/sync/sync_controller.dart';

/// Importa uno o varios cuadros de SACE: cada archivo es una asignatura del periodo.
/// Reimportar un cuadro ya importado lo actualiza sin perder lo capturado. Al final
/// ofrece aplicar un plan de calificación a las asignaturas nuevas.
Future<void> importarCuadros(BuildContext context, WidgetRef ref) async {
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['xlsx', 'xls'],
    allowMultiple: true,
    withData: true,
  );
  if (picked == null || !context.mounted) return;

  final repo = ref.read(clasesRepositoryProvider);
  final nuevas = <String>[];
  var actualizadas = 0;
  var alumnos = 0;
  final errores = <String>[];
  for (final file in picked.files) {
    if (file.bytes == null) continue;
    try {
      final r = await repo.importar(file.bytes!, file.name);
      alumnos += r.alumnos;
      if (r.nueva) {
        nuevas.add(r.claseId);
      } else {
        actualizadas++;
      }
      ref.invalidate(claseProvider(r.claseId));
      ref.invalidate(parcialesProvider(r.claseId));
    } on FormatoNoSoportado catch (error) {
      errores.add('${file.name}: ${error.message}');
    }
  }
  ref.invalidate(clasesProvider);
  ref.invalidate(tableroProvider);
  if (nuevas.isNotEmpty || actualizadas > 0) ref.read(syncControllerProvider.notifier).programar();
  if (!context.mounted) return;

  if (errores.isNotEmpty) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(errores.length == picked.files.length ? 'No se pudo importar' : 'Algunos archivos no se importaron'),
        content: SingleChildScrollView(child: Text(errores.join('\n\n'))),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
      ),
    );
    if (!context.mounted) return;
  }

  final total = nuevas.length + actualizadas;
  if (total == 0) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text([
      if (nuevas.isNotEmpty) '${nuevas.length} ${nuevas.length == 1 ? 'asignatura nueva' : 'asignaturas nuevas'}',
      if (actualizadas > 0) '$actualizadas ${actualizadas == 1 ? 'actualizada' : 'actualizadas'}',
      '$alumnos alumnos',
    ].join(' · ')),
  ));

  if (nuevas.isNotEmpty) await ofrecerPlan(context, ref, nuevas);
}

/// Aplica la plantilla elegida a todos los parciales de esas clases que todavía no tienen plan.
Future<void> ofrecerPlan(BuildContext context, WidgetRef ref, List<String> claseIds) async {
  final cuantas = claseIds.length;
  final elegida = await elegirPlantilla(
    context,
    ref,
    mensaje: 'Se copia a ${cuantas == 1 ? 'la asignatura nueva' : 'las $cuantas asignaturas nuevas'}, en cada parcial. '
        'Después puedes cambiar rubros y puntos en cada una.',
  );
  if (elegida == null) return;

  final planes = ref.read(planesRepositoryProvider);
  for (final id in claseIds) {
    final parciales = await planes.parciales(id);
    await planes.aplicarPlantilla(id, parciales.map((p) => p.clave), elegida.rubros);
  }
  ref.invalidate(planProvider);
  ref.invalidate(tableroProvider);
  ref.read(syncControllerProvider.notifier).programar();
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Plan "${elegida.nombre}" aplicado. Puedes ajustarlo en cada asignatura.')));
  }
}

/// Hoja inferior con las plantillas del docente y las prearmadas.
Future<Plantilla?> elegirPlantilla(BuildContext context, WidgetRef ref, {required String mensaje}) async {
  final plantillas = await ref.read(plantillasProvider.future);
  if (!context.mounted) return null;
  return showModalBottomSheet<Plantilla>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(),
    builder: (context) => _ElegirPlantilla(plantillas: plantillas, mensaje: mensaje),
  );
}

class _ElegirPlantilla extends StatelessWidget {
  const _ElegirPlantilla({required this.plantillas, required this.mensaje});

  final List<Plantilla> plantillas;
  final String mensaje;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text('¿Aplicar un plan de calificación?', style: text.titleLarge),
            const SizedBox(height: 4),
            Text(
              mensaje,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            for (final p in plantillas)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    onTap: () => Navigator.pop(context, p),
                    title: Text(p.nombre, style: text.titleMedium),
                    subtitle: Text(p.rubros.map((r) => '${r.nombre} ${formatoPuntos(r.puntos)}').join(' · ')),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Ahora no, lo armo después')),
          ],
        ),
      ),
    );
  }
}
