import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/api_exception.dart';
import '../../core/informes/compartir.dart';
import '../../core/informes/informes_pdf.dart';
import '../../core/planes/calculo_parcial.dart';
import '../../core/planes/modelos.dart';
import '../../core/providers.dart';
import '../../theme/tokens.dart';

/// Si el docente tiene el asistente (plan Pro) y cuánto le queda este mes. Null sin internet.
final estadoIaProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  try {
    return await ref.watch(apiClientProvider).get('/ia/estado', parse: (d) => d as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
});

/// Ícono del asistente, el mismo en todos los botones.
const iconoIa = Icons.auto_awesome_outlined;

/// Antes de abrir el asistente: sin plan Pro o sin internet se explica y no sigue.
Future<bool> _puedeUsar(BuildContext context, WidgetRef ref, String uso, String nombre) async {
  final estado = await ref.read(estadoIaProvider.future);
  if (!context.mounted) return false;
  final (titulo, mensaje) = switch (estado) {
    null => ('Sin conexión', 'El asistente necesita internet. Lo demás de la app sigue funcionando sin conexión.'),
    {'habilitada': false} => (
        'Asistente del plan Pro',
        'El asistente propone el plan del parcial, exámenes con su clave y comentarios para cada alumno. '
            'Es parte del plan Pro: consúltalo con la administración de tu centro o con ProfeApp.'
      ),
    {'disponible': false} => ('No disponible', 'El asistente no está disponible en este momento. Intenta más tarde.'),
    _ => (null, null),
  };
  if (titulo == null) return await consentimientoIa(context) && context.mounted && await revisarTopeIa(context, estado!, uso, nombre);
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      shape: const RoundedRectangleBorder(),
      icon: const Icon(iconoIa),
      title: Text(titulo),
      content: Text(mensaje!),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
    ),
  );
  return false;
}

const _claveConsentimiento = 'ia_consentimiento_v1';

/// La primera vez explica qué se envía a Anthropic y pide permiso (App Store 5.1.2(i)).
/// Se recuerda en el dispositivo; sin aceptar no se usa el asistente.
Future<bool> consentimientoIa(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_claveConsentimiento) ?? false) return true;
  if (!context.mounted) return false;
  final acepta = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: const RoundedRectangleBorder(),
      icon: const Icon(iconoIa),
      title: const Text('Antes de usar el asistente'),
      content: const SingleChildScrollView(
        child: Text(
          'El asistente funciona con Claude, la inteligencia artificial de Anthropic. Para cada tarea, '
          'ProfeApp le envía solo lo necesario: los temas, las notas, la asistencia, la conducta o la foto '
          'del trabajo que vas a calificar.\n\n'
          'Nunca se envía el nombre ni la identidad de los alumnos. Anthropic no usa estos datos para '
          'entrenar sus modelos, y las fotos no se guardan.\n\n'
          'El asistente solo propone: nada se guarda ni cambia sin que tú lo aceptes. Más detalle en la '
          'política de privacidad (profeapphn.com/privacidad).',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ahora no')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Acepto')),
      ],
    ),
  );
  if (acepta != true) return false;
  await prefs.setBool(_claveConsentimiento, true);
  return true;
}

/// Con el tope del mes alcanzado lo explica y no sigue; desde el 80 % avisa cuánto queda.
/// [uso] es la clave del conteo en el estado (p. ej. 'comentarios', con su 'limiteComentarios').
Future<bool> revisarTopeIa(BuildContext context, Map<String, dynamic> estado, String uso, String nombre) async {
  final usado = estado[uso] as int? ?? 0;
  final limite = estado['limite${uso[0].toUpperCase()}${uso.substring(1)}'] as int? ?? 0;
  if (limite <= 0) return true;
  if (usado >= limite) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: const RoundedRectangleBorder(),
        icon: const Icon(iconoIa),
        title: const Text('Tope del mes alcanzado'),
        content: Text('Ya se usaron $limite de $limite $nombre de este mes. Se renueva el día 1; '
            'si necesitas más, escríbenos a ProfeApp. Lo demás de la app sigue funcionando igual.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
      ),
    );
    return false;
  }
  if (usado >= limite * 0.8) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Este mes te quedan ${limite - usado} de $limite $nombre.')));
  }
  return true;
}

/// Llama al asistente con un indicador de espera. Null si falló (ya avisó).
Future<Map<String, dynamic>?> _pedir(BuildContext context, WidgetRef ref, String ruta, Map<String, dynamic> body) async {
  final messenger = ScaffoldMessenger.of(context);
  final navegador = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(),
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: Espacio.l),
          Expanded(child: Text('El asistente está trabajando… puede tardar unos segundos.')),
        ]),
      ),
    ),
  );
  try {
    return await ref.read(apiClientProvider).post(ruta, body: body, parse: (d) => d as Map<String, dynamic>);
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.isNetworkError ? 'Necesitas internet para usar el asistente.' : e.message)));
    return null;
  } finally {
    navegador.pop();
    ref.invalidate(estadoIaProvider);
  }
}

String _clave(String s) => s.trim().toUpperCase();

double _num(Object? v) => (v as num).toDouble();

// ── Plan del parcial ─────────────────────────────────────────────────────────

/// Propone rubros (si el parcial no tiene) y actividades; el docente elige cuáles agregar.
Future<void> sugerirPlanIa(BuildContext context, WidgetRef ref, PlanParcial plan) async {
  if (!await _puedeUsar(context, ref, 'generaciones', 'planes y exámenes') || !context.mounted) return;
  final clase = (await ref.read(claseProvider(plan.claseId).future)).resumen;
  if (!context.mounted) return;

  final temas = TextEditingController();
  var semanas = 5;
  final pedir = await showDialog<bool>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (dialogo, setState) => AlertDialog(
        shape: const RoundedRectangleBorder(),
        title: const Text('Sugerir el plan'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(plan.rubros.isEmpty
                  ? 'El asistente propone rubros que suman 100 puntos y sus actividades.'
                  : 'El asistente propone actividades para los rubros que ya tienes.'),
              const SizedBox(height: Espacio.m),
              TextField(
                controller: temas,
                autofocus: true,
                minLines: 4,
                maxLines: 8,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Temas del parcial',
                  hintText: 'Fracciones: suma, resta y problemas. Números decimales…',
                  alignLabelWithHint: true,
                ),
              ),
              Row(
                children: [
                  const Expanded(child: Text('Semanas del parcial')),
                  IconButton(
                    onPressed: semanas > 1 ? () => setState(() => semanas--) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Text('$semanas', style: Theme.of(dialogo).textTheme.titleMedium),
                  IconButton(
                    onPressed: semanas < 12 ? () => setState(() => semanas++) : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogo, false), child: const Text('Cancelar')),
          FilledButton.icon(
            onPressed: () => temas.text.trim().isEmpty ? null : Navigator.pop(dialogo, true),
            icon: const Icon(iconoIa),
            label: const Text('Sugerir'),
          ),
        ],
      ),
    ),
  );
  if (pedir != true || !context.mounted) return;

  final r = await _pedir(context, ref, '/ia/plan', {
    'asignatura': clase.asignatura,
    'grado': clase.gradoSeccion,
    'parcial': plan.parcial.titulo,
    'temas': temas.text,
    'semanas': semanas,
    'total': 100,
    'rubros': [for (final x in plan.rubros) {'nombre': x.nombre, 'puntos': x.puntos}],
  });
  if (r == null || !context.mounted) return;
  final rubros = (r['rubros'] as List).cast<Map<String, dynamic>>();
  if (rubros.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El asistente no propuso nada. Intenta con más detalle en los temas.')));
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => _RevisarPlan(plan: plan, rubros: rubros, semanas: semanas),
  ));
}

class _RevisarPlan extends ConsumerStatefulWidget {
  const _RevisarPlan({required this.plan, required this.rubros, required this.semanas});

  final PlanParcial plan;
  final List<Map<String, dynamic>> rubros;
  final int semanas;

  @override
  ConsumerState<_RevisarPlan> createState() => _RevisarPlanState();
}

class _RevisarPlanState extends ConsumerState<_RevisarPlan> {
  // Elegidas, por rubro e índice de actividad.
  late final _elegidas = <(int, int)>{
    for (final (i, r) in widget.rubros.indexed)
      for (var j = 0; j < (r['actividades'] as List).length; j++) (i, j),
  };
  var _guardando = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final nuevos = widget.plan.rubros.isEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Plan sugerido')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Espacio.l),
          child: FilledButton(
            onPressed: _guardando ? null : _agregar,
            child: Text(_elegidas.isEmpty && !nuevos
                ? 'Elige al menos una actividad'
                : 'Agregar ${nuevos ? 'rubros y ' : ''}${_elegidas.length} ${_elegidas.length == 1 ? 'actividad' : 'actividades'}'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Espacio.l),
        children: [
          Text('Revisa lo que propone el asistente. Desmarca lo que no quieras; después puedes cambiar '
              'títulos, puntos y fechas como cualquier actividad.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          for (final (i, r) in widget.rubros.indexed) ...[
            Padding(
              padding: const EdgeInsets.only(top: Espacio.xl, bottom: Espacio.xs),
              child: Row(children: [
                Expanded(child: Text('${r['nombre']}'.toUpperCase(), style: text.labelSmall)),
                Text('${formatoPuntos(_num(r['puntos']))} pts', style: text.labelSmall),
              ]),
            ),
            for (final (j, a) in (r['actividades'] as List).cast<Map<String, dynamic>>().indexed)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _elegidas.contains((i, j)),
                onChanged: (v) => setState(() => v == true ? _elegidas.add((i, j)) : _elegidas.remove((i, j))),
                title: Text('${a['titulo']} · ${formatoPuntos(_num(a['puntos']))} pts'),
                subtitle: Text('Semana ${a['semana']} · ${a['descripcion']}'),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _agregar() async {
    final plan = widget.plan;
    if (_elegidas.isEmpty && plan.rubros.isNotEmpty) return;
    setState(() => _guardando = true);
    final repo = ref.read(planesRepositoryProvider);
    final existentes = {for (final x in plan.rubros) _clave(x.nombre): x.id};
    // La semana 1 empieza este lunes; el docente ajusta las fechas después.
    final hoy = DateUtils.dateOnly(DateTime.now());
    final lunes = hoy.subtract(Duration(days: hoy.weekday - 1));
    var agregadas = 0;
    for (final (i, r) in widget.rubros.indexed) {
      final actividades = (r['actividades'] as List).cast<Map<String, dynamic>>();
      final elegidas = [for (var j = 0; j < actividades.length; j++) if (_elegidas.contains((i, j))) actividades[j]];
      var rubroId = existentes[_clave('${r['nombre']}')];
      if (rubroId == null) {
        if (plan.rubros.isNotEmpty) continue;
        rubroId = await repo.guardarRubro(plan.claseId, plan.parcial.clave, nombre: '${r['nombre']}', puntos: _num(r['puntos']));
      }
      for (final a in elegidas) {
        await repo.guardarActividad(plan.claseId, plan.parcial.clave,
            rubroId: rubroId,
            titulo: '${a['titulo']}',
            fecha: lunes.add(Duration(days: 7 * (((a['semana'] as num).toInt()) - 1))),
            puntos: _num(a['puntos']),
            descripcion: '${a['descripcion']}');
        agregadas++;
      }
    }
    planCambiado(ref, plan.claseId, plan.parcial.clave);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Se agregaron $agregadas actividades al plan.')));
    Navigator.pop(context);
  }
}

// ── Examen ───────────────────────────────────────────────────────────────────

const _tipos = {
  'opcion_multiple': 'Opción múltiple',
  'verdadero_falso': 'Verdadero o falso',
  'respuesta_corta': 'Respuesta corta',
  'desarrollo': 'Desarrollo',
};

/// Genera un examen con su clave; se imprime en PDF y, si se quiere, queda como actividad.
Future<void> generarExamenIa(BuildContext context, WidgetRef ref, PlanParcial plan) async {
  if (!await _puedeUsar(context, ref, 'generaciones', 'planes y exámenes') || !context.mounted) return;
  final clase = (await ref.read(claseProvider(plan.claseId).future)).resumen;
  if (!context.mounted) return;

  final temas = TextEditingController();
  final puntos = TextEditingController(text: '20');
  var preguntas = 10;
  final tipos = {'opcion_multiple', 'verdadero_falso', 'respuesta_corta'};
  final pedir = await showDialog<bool>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (dialogo, setState) => AlertDialog(
        shape: const RoundedRectangleBorder(),
        title: const Text('Generar examen'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: temas,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                maxLength: 2000,
                decoration: const InputDecoration(labelText: 'Temas que evalúa', alignLabelWithHint: true),
              ),
              Row(
                children: [
                  const Expanded(child: Text('Preguntas')),
                  IconButton(onPressed: preguntas > 3 ? () => setState(() => preguntas--) : null, icon: const Icon(Icons.remove)),
                  Text('$preguntas', style: Theme.of(dialogo).textTheme.titleMedium),
                  IconButton(onPressed: preguntas < 40 ? () => setState(() => preguntas++) : null, icon: const Icon(Icons.add)),
                ],
              ),
              TextField(
                controller: puntos,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Valor del examen (puntos)'),
              ),
              const SizedBox(height: Espacio.m),
              Wrap(
                spacing: Espacio.xs,
                runSpacing: Espacio.xs,
                children: [
                  for (final t in _tipos.entries)
                    FilterChip(
                      label: Text(t.value),
                      selected: tipos.contains(t.key),
                      onSelected: (v) => setState(() => v ? tipos.add(t.key) : tipos.remove(t.key)),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogo, false), child: const Text('Cancelar')),
          FilledButton.icon(
            onPressed: () => temas.text.trim().isEmpty || tipos.isEmpty ? null : Navigator.pop(dialogo, true),
            icon: const Icon(iconoIa),
            label: const Text('Generar'),
          ),
        ],
      ),
    ),
  );
  final valor = double.tryParse(puntos.text.replaceAll(',', '.'));
  if (pedir != true || !context.mounted) return;
  if (valor == null || valor <= 0 || valor > 100) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El valor del examen va de 1 a 100 puntos.')));
    return;
  }

  final examen = await _pedir(context, ref, '/ia/examen', {
    'asignatura': clase.asignatura,
    'grado': clase.gradoSeccion,
    'temas': temas.text,
    'preguntas': preguntas,
    'puntos': valor,
    'tipos': tipos.toList(),
  });
  if (examen == null || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => _RevisarExamen(plan: plan, examen: examen, puntos: valor, asignatura: clase.asignatura, grado: clase.gradoSeccion),
  ));
}

class _RevisarExamen extends ConsumerWidget {
  const _RevisarExamen({required this.plan, required this.examen, required this.puntos, required this.asignatura, required this.grado});

  final PlanParcial plan;
  final Map<String, dynamic> examen;
  final double puntos;
  final String asignatura;
  final String grado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final preguntas = (examen['preguntas'] as List).cast<Map<String, dynamic>>();
    final letras = 'abcdefgh';

    Future<void> pdf({required bool clave}) async {
      final bytes = await InformesPdf.examen(examen, asignatura: asignatura, grado: grado, conClave: clave);
      if (context.mounted) await compartirPdf(context, bytes, nombreArchivo('${clave ? 'Clave' : 'Examen'} ${examen['titulo']}'));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Examen sugerido')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Espacio.l),
          child: Wrap(
            spacing: Espacio.s,
            runSpacing: Espacio.s,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(onPressed: () => pdf(clave: true), icon: const Icon(Icons.key_outlined), label: const Text('Clave')),
              FilledButton.icon(onPressed: () => pdf(clave: false), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Examen en PDF')),
              if (!plan.cerrado)
                OutlinedButton.icon(
                  onPressed: () => _crearActividad(context, ref),
                  icon: const Icon(Icons.add_task),
                  label: const Text('Crear actividad'),
                ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Espacio.l),
        children: [
          Text('${examen['titulo']}', style: text.titleLarge),
          Text('${examen['instrucciones']}', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: Espacio.s),
          Text('Revisa cada pregunta y su respuesta antes de imprimir.', style: text.bodySmall?.copyWith(color: scheme.error)),
          for (final (i, p) in preguntas.indexed)
            Padding(
              padding: const EdgeInsets.only(top: Espacio.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${i + 1}. ${p['enunciado']}  (${formatoPuntos(_num(p['puntos']))} pts)', style: text.bodyLarge),
                  for (final (j, o) in (p['opciones'] as List).indexed)
                    Padding(padding: const EdgeInsets.only(left: Espacio.l, top: 2), child: Text('${letras[j]}) $o')),
                  Padding(
                    padding: const EdgeInsets.only(top: Espacio.xs),
                    child: Text('Respuesta: ${p['respuesta']}', style: text.bodySmall?.copyWith(color: scheme.primary)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _crearActividad(BuildContext context, WidgetRef ref) async {
    final rubro = await showDialog<Rubro>(
      context: context,
      builder: (context) => SimpleDialog(
        shape: const RoundedRectangleBorder(),
        title: const Text('¿En qué rubro va?'),
        children: [
          for (final r in plan.rubros) SimpleDialogOption(onPressed: () => Navigator.pop(context, r), child: Text(r.nombre)),
        ],
      ),
    );
    if (rubro == null) return;
    await ref.read(planesRepositoryProvider).guardarActividad(plan.claseId, plan.parcial.clave,
        rubroId: rubro.id, titulo: '${examen['titulo']}', fecha: DateUtils.dateOnly(DateTime.now()), puntos: puntos);
    planCambiado(ref, plan.claseId, plan.parcial.clave);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Actividad creada en ${rubro.nombre}. Cambia la fecha si hace falta.')));
    }
  }
}

// ── Comentario de un alumno ──────────────────────────────────────────────────

/// Redacta el comentario del parcial con sus notas por rubro y su asistencia (sin su nombre)
/// y lo guarda como observación si el docente quiere.
Future<void> comentarioIa(BuildContext context, WidgetRef ref, PlanParcial plan, AlumnoPlan alumno,
    {required Future<void> Function(String texto) guardar}) async {
  if (!await _puedeUsar(context, ref, 'comentarios', 'comentarios') || !context.mounted) return;
  final clase = (await ref.read(claseProvider(plan.claseId).future)).resumen;
  if (!context.mounted) return;

  final rubros = <Map<String, dynamic>>[];
  for (final rubro in plan.rubros) {
    var obtenido = 0.0, posible = 0.0;
    for (final a in plan.actividades.where((a) => a.rubroId == rubro.id)) {
      final v = plan.calificaciones[a.id]?[alumno.id];
      if (v == null) continue;
      obtenido += v;
      posible += a.puntos;
    }
    if (posible > 0) rubros.add({'nombre': rubro.nombre, 'obtenido': obtenido, 'posible': posible});
  }
  final estados = [for (final s in plan.sesiones) plan.asistencias[s.id]?[alumno.id]];
  final nota = calcularParcial(plan).porAlumno[alumno.id];

  final r = await _pedir(context, ref, '/ia/comentario', {
    'asignatura': clase.asignatura,
    'grado': clase.gradoSeccion,
    'parcial': plan.parcial.titulo,
    'rubros': rubros,
    'nota': plan.cerrado ? nota?.nota : null,
    'ausencias': estados.where((e) => e == EstadoAsistencia.ausente).length,
    'tardes': estados.where((e) => e == EstadoAsistencia.tarde).length,
  });
  if (r == null || !context.mounted) return;
  final texto = TextEditingController(text: '${r['texto']}');
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: const RoundedRectangleBorder(),
      title: const Text('Comentario sugerido'),
      content: TextField(controller: texto, minLines: 4, maxLines: 10, decoration: const InputDecoration(helperText: 'Puedes cambiarlo antes de guardar.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Descartar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar como observación')),
      ],
    ),
  );
  if (ok == true && texto.text.trim().isNotEmpty) await guardar(texto.text.trim());
}

// ── Calificar desde una foto ─────────────────────────────────────────────────

/// Foto lista para la IA: orientada y con su lado mayor en 1568 px (JPEG).
Uint8List? _reducirTrabajo(Uint8List bytes) {
  final original = img.decodeImage(bytes);
  if (original == null) return null;
  final orientada = img.bakeOrientation(original);
  final ancho = orientada.width >= orientada.height;
  final mayor = ancho ? orientada.width : orientada.height;
  final reducida = mayor <= 1568
      ? orientada
      : img.copyResize(orientada, width: ancho ? 1568 : null, height: ancho ? null : 1568, interpolation: img.Interpolation.average);
  return img.encodeJpg(reducida, quality: 80);
}

/// Toma o elige las fotos del trabajo (hasta 4 páginas), pide la sugerencia y devuelve la nota
/// que el docente acepta, o null. [criterios] es la clave de la actividad, que se recuerda
/// mientras el docente está en la pantalla.
Future<double?> calificarConFotoIa(
  BuildContext context,
  WidgetRef ref,
  PlanParcial plan,
  Actividad actividad, {
  required String? criterios,
  required ValueChanged<String> alCriterios,
}) async {
  if (!await _puedeUsar(context, ref, 'calificaciones', 'calificaciones con foto') || !context.mounted) return null;
  final clase = (await ref.read(claseProvider(plan.claseId).future)).resumen;
  if (!context.mounted) return null;

  // La clave se pide una vez por actividad: ayuda mucho a la IA.
  var clave = criterios;
  if (clave == null) {
    final campo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: const RoundedRectangleBorder(),
        title: const Text('Clave o criterios'),
        content: TextField(
          controller: campo,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          maxLength: 3000,
          decoration: const InputDecoration(
            helperText: 'Opcional, pero mejora mucho la sugerencia. Se usa para todos los alumnos de esta actividad.',
            helperMaxLines: 3,
            hintText: '1) 3/4  2) Verdadero  3) Explica con un dibujo…',
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Seguir')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return null;
    clave = campo.text.trim();
    alCriterios(clave);
  }

  final picker = ImagePicker();
  final fotos = <Uint8List>[];
  while (fotos.length < 4) {
    if (!context.mounted) return null;
    final origen = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(),
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Espacio.l, 0, Espacio.l, Espacio.s),
            child: Text(fotos.isEmpty
                ? 'Foto del trabajo, de frente y con buena luz. Tapa el nombre del alumno si puedes.'
                : '${fotos.length} ${fotos.length == 1 ? 'página' : 'páginas'}. ¿Agregas otra?'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Tomar foto'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Elegir de la galería'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          if (fotos.isNotEmpty)
            ListTile(
              leading: const Icon(iconoIa),
              title: const Text('Listo, calificar'),
              onTap: () => Navigator.pop(context),
            ),
        ]),
      ),
    );
    if (origen == null) break;
    final elegida = await picker.pickImage(source: origen);
    if (elegida == null) continue;
    final lista = await compute(_reducirTrabajo, await elegida.readAsBytes());
    if (lista != null) fotos.add(lista);
  }
  if (fotos.isEmpty || !context.mounted) return null;

  final r = await _pedir(context, ref, '/ia/calificar', {
    'asignatura': clase.asignatura,
    'grado': clase.gradoSeccion,
    'actividad': actividad.titulo,
    'descripcion': actividad.descripcion,
    'puntos': actividad.puntos,
    'criterios': clave,
    'imagenes': [for (final f in fotos) base64Encode(f)],
  });
  if (r == null || !context.mounted) return null;
  final nota = TextEditingController(text: formatoPuntos(_num(r['nota'])));
  final usar = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: const RoundedRectangleBorder(),
      title: const Text('Nota sugerida'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: nota,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Nota', suffixText: '/ ${formatoPuntos(actividad.puntos)}'),
          ),
          const SizedBox(height: Espacio.m),
          Text('${r['justificacion']}'),
          const SizedBox(height: Espacio.s),
          Text('Es una sugerencia: la nota la decides tú.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Descartar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Usar esta nota')),
      ],
    ),
  );
  if (usar != true) return null;
  final valor = double.tryParse(nota.text.replaceAll(',', '.'));
  return valor == null || valor < 0 || valor > actividad.puntos ? null : valor;
}
