import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local/clases_repository.dart';
import '../../core/planes/calculo_parcial.dart';
import '../../core/planes/modelos.dart';
import '../../core/providers.dart';
import '../../core/sace/hoja.dart';
import '../../core/sync/sync_controller.dart';
import '../../theme/tokens.dart';
import 'horario_clase.dart';

/// Importa uno o varios cuadros de SACE: cada archivo es una asignatura del periodo.
/// Reimportar un cuadro ya importado lo actualiza sin perder lo capturado. Al final
/// pide el horario de las asignaturas nuevas y ofrece aplicarles un plan de calificación.
Future<void> importarCuadros(BuildContext context, WidgetRef ref) async {
  final cobro = ref.read(sessionProvider)?.cobro;
  if (cobro?.soloLectura ?? false) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No se pueden importar cuadros'),
        content: Text(cobro!.mensaje),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
      ),
    );
    return;
  }
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['xlsx', 'xls'],
    allowMultiple: true,
    withData: true,
  );
  if (picked == null || !context.mounted) return;

  final repo = ref.read(clasesRepositoryProvider);
  final tope = ref.read(sessionProvider)?.cobro?.topeAsignaturas;
  final nuevas = <String>[];
  var actualizadas = 0;
  var alumnos = 0;
  final errores = <String>[];
  for (final file in picked.files) {
    if (file.bytes == null) continue;
    try {
      final r = await repo.importar(file.bytes!, file.name, tope: tope);
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
    } on TopeAsignaturas catch (error) {
      errores.add('${file.name}: $error');
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

  if (nuevas.isEmpty) return;
  await pedirHorarios(context, ref, nuevas);
  if (context.mounted) await ofrecerPlan(context, ref, nuevas);
}

/// Aplica la plantilla elegida a todos los parciales de esas clases que todavía no tienen plan.
Future<void> ofrecerPlan(BuildContext context, WidgetRef ref, List<String> claseIds) async {
  final cuantas = claseIds.length;
  // La tabla oficial de cada una según su grado. Si no todas usan la misma, se ofrece
  // aplicar a cada una la suya.
  final clases = {for (final c in await ref.read(clasesProvider.future)) c.id: c};
  final oficiales = {
    for (final id in claseIds)
      if (Plantilla.oficialPara(clases[id]?.gradoSeccion ?? '') case final p?) id: p,
  };
  final distintas = {for (final p in oficiales.values) p.id}.length > 1;
  if (!context.mounted) return;
  final elegida = await elegirPlantilla(
    context,
    ref,
    mensaje: 'Se copia a ${cuantas == 1 ? 'la asignatura nueva' : 'las $cuantas asignaturas nuevas'}, en cada parcial. '
        'Después puedes cambiar rubros y puntos en cada una.',
    recomendada: distintas ? _segunGrado : oficiales.values.firstOrNull,
  );
  if (elegida == null) return;

  final planes = ref.read(planesRepositoryProvider);
  for (final id in claseIds) {
    final rubros = elegida.id == _segunGrado.id ? oficiales[id]?.rubros : elegida.rubros;
    if (rubros == null) continue;
    final parciales = await planes.parciales(id);
    await planes.aplicarPlantilla(id, parciales.map((p) => p.clave), rubros);
  }
  ref.invalidate(planProvider);
  ref.invalidate(tableroProvider);
  ref.read(syncControllerProvider.notifier).programar();
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Plan "${elegida.nombre}" aplicado. Puedes ajustarlo en cada asignatura.')));
  }
}

/// Al importar asignaturas de grados distintos: a cada una, la tabla oficial de su grado.
const _segunGrado = Plantilla(
  id: 'pre:0158-grado',
  nombre: 'Oficial · la de cada grado',
  prearmada: true,
  rubros: [],
);

/// Hoja inferior con las plantillas del docente y las prearmadas; [recomendada] va primero.
Future<Plantilla?> elegirPlantilla(BuildContext context, WidgetRef ref,
    {required String mensaje, Plantilla? recomendada}) async {
  final todas = await ref.read(plantillasProvider.future);
  final plantillas = [if (recomendada != null) recomendada, ...todas.where((p) => p.id != recomendada?.id)];
  if (!context.mounted) return null;
  return showModalBottomSheet<Plantilla>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(),
    builder: (context) => _ElegirPlantilla(plantillas: plantillas, mensaje: mensaje, recomendada: recomendada?.id),
  );
}

class _ElegirPlantilla extends StatelessWidget {
  const _ElegirPlantilla({required this.plantillas, required this.mensaje, this.recomendada});

  final List<Plantilla> plantillas;
  final String mensaje;
  final String? recomendada;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(Espacio.l, 0, Espacio.l, Espacio.l),
          children: [
            Text('¿Aplicar una rúbrica de evaluación?', style: text.titleLarge),
            const SizedBox(height: Espacio.xs),
            Text(
              mensaje,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Espacio.l),
            for (final p in plantillas)
              Padding(
                padding: const EdgeInsets.only(bottom: Espacio.s),
                child: Card(
                  shape: p.id == recomendada
                      ? RoundedRectangleBorder(side: BorderSide(color: scheme.primary, width: 2))
                      : null,
                  child: ListTile(
                    onTap: () => Navigator.pop(context, p),
                    title: Text(p.nombre, style: text.titleMedium),
                    subtitle: Text([
                      if (p.id == recomendada) 'Recomendada · Acuerdo 0158-SE-2025',
                      if (p.rubros.isEmpty)
                        'A cada asignatura, la tabla oficial de su grado.'
                      else
                        p.rubros.map((r) => '${r.nombre} ${formatoPuntos(r.puntos)}').join(' · '),
                    ].join('\n')),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
              ),
            const SizedBox(height: Espacio.s),
            OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Ahora no, lo armo después')),
          ],
        ),
      ),
    );
  }
}
