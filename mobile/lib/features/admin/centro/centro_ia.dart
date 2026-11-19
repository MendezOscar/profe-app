import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/informes/compartir.dart';
import '../../../core/informes/informes_pdf.dart';
import '../../../core/providers.dart';
import '../../../theme/tokens.dart';
import '../../../ui/estado_error.dart';
import '../../ia/asistente_ia.dart' show iconoIa;
import '../centro_page.dart' show centroProvider;
import 'consolidado_page.dart';

/// Si el centro tiene el asistente (plan Pro) y su uso del mes. Null sin internet.
final estadoIaCentroProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  try {
    return await ref.watch(apiClientProvider).get('/centro/ia/estado', parse: (d) => d as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
});

/// Sin plan Pro o sin internet se explica y no sigue.
Future<bool> puedeUsarIaCentro(BuildContext context, WidgetRef ref) async {
  final estado = await ref.read(estadoIaCentroProvider.future);
  if (!context.mounted) return false;
  final (titulo, mensaje) = switch (estado) {
    null => ('Sin conexión', 'El asistente necesita internet.'),
    {'habilitada': false} => (
        'Asistente del plan Pro',
        'Con el plan Pro el asistente redacta los comentarios de las boletas, el informe del año para la dirección y '
            'borradores de comunicados. Consúltalo con ProfeApp.'
      ),
    {'disponible': false} => ('No disponible', 'El asistente no está disponible en este momento. Intenta más tarde.'),
    _ => (null, null),
  };
  if (titulo == null) return true;
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

String _mensaje(ApiException e) => e.isNetworkError ? 'Necesitas internet.' : e.message;

const _romanos = ['I', 'II', 'III', 'IV'];

// ── Comentarios de boleta ────────────────────────────────────────────────────

/// Comentario de cada alumno de la sección para la boleta de un parcial. La IA los redacta
/// en segundo plano; el centro los revisa y edita. Lo editado ya no lo reescribe la IA.
class ComentariosBoletaPage extends ConsumerStatefulWidget {
  const ComentariosBoletaPage({super.key, required this.seccionId, required this.titulo});

  final String seccionId;
  final String titulo;

  @override
  ConsumerState<ComentariosBoletaPage> createState() => _ComentariosBoletaPageState();
}

class _ComentariosBoletaPageState extends ConsumerState<ComentariosBoletaPage> {
  var _parcial = 1;
  Map<String, dynamic>? _datos;
  Object? _error;
  Timer? _espera;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _espera?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final d = await ref.read(apiClientProvider).get('/centro/secciones/${widget.seccionId}/comentarios',
          query: {'parcial': _parcial}, parse: (d) => d as Map<String, dynamic>);
      if (!mounted) return;
      // Al terminar la IA, el consolidado (y las boletas) ya traen los comentarios nuevos.
      if (_datos?['enProceso'] == true && d['enProceso'] != true) ref.invalidate(consolidadoProvider(widget.seccionId));
      setState(() {
        _datos = d;
        _error = null;
      });
      _esperarSiHaceFalta();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Mientras la IA redacta, se vuelve a consultar cada pocos segundos.
  void _esperarSiHaceFalta() {
    _espera?.cancel();
    if (_datos?['enProceso'] == true) _espera = Timer(const Duration(seconds: 3), _cargar);
  }

  Future<void> _generar({required bool todos}) async {
    if (!await puedeUsarIaCentro(context, ref) || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final d = await ref.read(apiClientProvider).post('/centro/secciones/${widget.seccionId}/comentarios/generar',
          body: {'parcial': _parcial, 'todos': todos}, parse: (d) => d as Map<String, dynamic>);
      if (!mounted) return;
      setState(() => _datos = d);
      _esperarSiHaceFalta();
      ref.invalidate(estadoIaCentroProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_mensaje(e))));
    }
  }

  Future<void> _editar(Map<String, dynamic> a) async {
    final texto = TextEditingController(text: a['texto'] as String?);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: const RoundedRectangleBorder(),
        title: Text('${a['nombre']}'),
        content: TextField(
          controller: texto,
          minLines: 4,
          maxLines: 10,
          maxLength: 1000,
          decoration: const InputDecoration(helperText: 'Déjalo vacío para quitarlo de la boleta.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiClientProvider).put<void>('/centro/secciones/${widget.seccionId}/comentarios/${a['alumnoId']}',
          body: {'parcial': _parcial, 'texto': texto.text});
      ref.invalidate(consolidadoProvider(widget.seccionId));
      await _cargar();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_mensaje(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final alumnos = ((_datos?['alumnos'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final enProceso = _datos?['enProceso'] == true;
    final faltan = alumnos.where((a) => a['texto'] == null).length;

    return Scaffold(
      appBar: AppBar(title: Text('Comentarios · ${widget.titulo}')),
      body: _error != null
          ? EstadoError(error: _error!, reintentar: _cargar)
          : ListView(
              padding: const EdgeInsets.all(Espacio.l),
              children: [
                SegmentedButton<int>(
                  segments: [for (var i = 1; i <= 4; i++) ButtonSegment(value: i, label: Text('Parcial ${_romanos[i - 1]}'))],
                  selected: {_parcial},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) {
                    setState(() {
                      _parcial = s.first;
                      _datos = null;
                    });
                    _cargar();
                  },
                ),
                const SizedBox(height: Espacio.m),
                Text('El comentario va en la boleta, en Observaciones. La IA lo redacta con las notas, la conducta, '
                    'las faltas y las incidencias del alumno, sin su nombre. Revísalo: si lo editas, la IA ya no lo cambia.',
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: Espacio.m),
                Wrap(
                  spacing: Espacio.s,
                  runSpacing: Espacio.s,
                  children: [
                    FilledButton.icon(
                      onPressed: enProceso || _datos == null || faltan == 0 ? null : () => _generar(todos: false),
                      icon: const Icon(iconoIa),
                      label: Text(faltan == alumnos.length ? 'Redactar todos con IA' : 'Redactar los $faltan que faltan'),
                    ),
                    OutlinedButton(
                      onPressed: enProceso || _datos == null || faltan == alumnos.length ? null : () => _generar(todos: true),
                      child: const Text('Rehacer los de la IA'),
                    ),
                  ],
                ),
                if (enProceso || _datos == null) ...[
                  const SizedBox(height: Espacio.m),
                  const LinearProgressIndicator(),
                  if (enProceso)
                    Padding(
                      padding: const EdgeInsets.only(top: Espacio.xs),
                      child: Text('La IA está redactando… tarda unos segundos por alumno. Puedes salir y volver.',
                          style: text.bodySmall),
                    ),
                ],
                const SizedBox(height: Espacio.m),
                for (final a in alumnos)
                  Card(
                    margin: const EdgeInsets.only(bottom: Espacio.s),
                    child: ListTile(
                      onTap: enProceso ? null : () => _editar(a),
                      title: Text('${a['nombre']}'),
                      subtitle: Text(a['texto'] as String? ?? 'Sin comentario',
                          style: a['texto'] == null ? TextStyle(color: scheme.onSurfaceVariant) : null),
                      trailing: a['texto'] == null
                          ? null
                          : Icon(a['deIa'] == true ? iconoIa : Icons.edit_outlined,
                              size: 18, semanticLabel: a['deIa'] == true ? 'Redactado por la IA' : 'Editado'),
                    ),
                  ),
              ],
            ),
    );
  }
}

// ── Informe para la dirección ────────────────────────────────────────────────

Future<void> informeIa(BuildContext context, WidgetRef ref) async {
  if (!await puedeUsarIaCentro(context, ref) || !context.mounted) return;
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
          Expanded(child: Text('La IA está leyendo los reportes del año…')),
        ]),
      ),
    ),
  );
  Map<String, dynamic>? informe;
  try {
    informe = await ref.read(apiClientProvider).post('/centro/ia/informe', parse: (d) => d as Map<String, dynamic>);
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(_mensaje(e))));
  } finally {
    navegador.pop();
    ref.invalidate(estadoIaCentroProvider);
  }
  if (informe == null || !context.mounted) return;
  final centro = ref.read(centroProvider).valueOrNull?['institucion']?['nombre'] as String? ?? 'Centro educativo';
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _InformePage(informe: informe!, centro: centro)));
}

class _InformePage extends StatelessWidget {
  const _InformePage({required this.informe, required this.centro});

  final Map<String, dynamic> informe;
  final String centro;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget lista(String titulo, String clave, IconData icono, Color color) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: Espacio.xl),
            Text(titulo.toUpperCase(), style: text.labelSmall),
            for (final x in (informe[clave] as List).cast<String>())
              Padding(
                padding: const EdgeInsets.only(top: Espacio.s),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icono, size: 18, color: color),
                  const SizedBox(width: Espacio.s),
                  Expanded(child: Text(x)),
                ]),
              ),
          ],
        );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Informe con IA'),
        actions: [
          IconButton(
            tooltip: 'PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () async {
              final bytes = await InformesPdf.informeDireccion(informe, centro: centro);
              if (context.mounted) await compartirPdf(context, bytes, nombreArchivo('Informe $centro'));
            },
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Medida.lectura),
          child: ListView(
            padding: const EdgeInsets.all(Espacio.l),
            children: [
              Text('${informe['resumen']}', style: text.bodyLarge),
              lista('Fortalezas', 'fortalezas', Icons.check_circle_outline, scheme.primary),
              lista('Alertas', 'alertas', Icons.warning_amber_outlined, scheme.error),
              lista('Recomendaciones', 'recomendaciones', Icons.lightbulb_outline, scheme.tertiary),
              const SizedBox(height: Espacio.xl),
              Text('Lo redactó la IA con las cifras de Reportes (sin nombres de alumnos ni docentes). Revísalo antes de compartirlo.',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Comunicados ──────────────────────────────────────────────────────────────

/// Pide los puntos clave y devuelve (título, mensaje) redactados, o null.
Future<(String, String)?> redactarComunicadoIa(BuildContext context, WidgetRef ref, {String? destinatarios}) async {
  if (!await puedeUsarIaCentro(context, ref) || !context.mounted) return null;
  final puntos = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: const RoundedRectangleBorder(),
      title: const Text('Redactar con IA'),
      content: TextField(
        controller: puntos,
        autofocus: true,
        minLines: 4,
        maxLines: 8,
        maxLength: 1500,
        decoration: const InputDecoration(
          labelText: '¿Qué quieres comunicar?',
          hintText: 'Reunión de padres el viernes 22 a las 3 pm en el salón de actos. Entrega de boletas del II parcial.',
          alignLabelWithHint: true,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton.icon(onPressed: () => Navigator.pop(context, true), icon: const Icon(iconoIa), label: const Text('Redactar')),
      ],
    ),
  );
  if (ok != true || puntos.text.trim().isEmpty || !context.mounted) return null;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final r = await ref.read(apiClientProvider).post('/centro/ia/comunicado',
        body: {'puntos': puntos.text, 'destinatarios': destinatarios}, parse: (d) => d as Map<String, dynamic>);
    ref.invalidate(estadoIaCentroProvider);
    return ('${r['titulo']}', '${r['cuerpo']}');
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(_mensaje(e))));
    return null;
  }
}
