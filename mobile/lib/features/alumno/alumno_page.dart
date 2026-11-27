import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/informes/compartir.dart';
import '../../core/informes/informes_pdf.dart';
import '../../core/planes/calculo_parcial.dart';
import '../../core/planes/modelos.dart';
import '../../core/providers.dart';
import '../../core/sync/sync_controller.dart';
import '../../theme/tokens.dart';
import '../../ui/esqueleto.dart';
import '../../ui/estado_error.dart';
import '../../ui/shell.dart';
import '../ia/asistente_ia.dart';

/// Ficha de un alumno en una asignatura: cómo va en el parcial, sus observaciones y el
/// informe para el padre o la madre, que se comparte por WhatsApp como PDF.
class AlumnoPage extends ConsumerWidget {
  const AlumnoPage({super.key, required this.claseId, required this.alumnoId, required this.parcial});

  final String claseId;
  final String alumnoId;
  final String parcial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(planProvider((claseId, parcial)));
    return plan.when(
      loading: () => const EsqueletoPagina(),
      error: (error, _) => PaginaError(error: error, reintentar: () => ref.invalidate(planProvider((claseId, parcial)))),
      data: (plan) {
        final alumno = plan.alumnos.where((a) => a.id == alumnoId).firstOrNull;
        if (alumno == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('El alumno ya no está en esta clase.')));
        }
        return _Ficha(plan: plan, alumno: alumno);
      },
    );
  }
}

class _Ficha extends ConsumerWidget {
  const _Ficha({required this.plan, required this.alumno});

  final PlanParcial plan;
  final AlumnoPlan alumno;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final nota = calcularParcial(plan).porAlumno[alumno.id]!;
    final observaciones = ref.watch(observacionesProvider(alumno.id));

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go('/inicio/asignaturas/${plan.claseId}?parcial=${Uri.encodeComponent(plan.parcial.clave)}&pestana=2'),
        ),
        title: Text(alumno.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          Builder(
            builder: (context) => IconButton(
              tooltip: 'Compartir informe',
              icon: const Icon(Icons.ios_share),
              onPressed: () => _compartirInforme(context, ref),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'nueva-observacion',
        shape: const RoundedRectangleBorder(),
        onPressed: () => editarObservacion(context, ref, plan.claseId, alumno),
        icon: const Icon(Icons.note_add_outlined),
        label: const Text('Observación'),
      ),
      body: ContenidoCentrado(
        maxAncho: Medida.lectura,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.bajoBotonFlotante),
          children: [
            Text(plan.parcial.titulo, style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: Espacio.xs),
            Wrap(
              spacing: Espacio.xl,
              runSpacing: Espacio.s,
              children: [
                _Dato(valor: plan.cerrado ? '${nota.nota}' : formatoPuntos(nota.obtenidos), etiqueta: plan.cerrado ? 'Nota' : 'Puntos'),
                _Dato(valor: '${nota.inasistencias}', etiqueta: nota.inasistencias == 1 ? 'Falta' : 'Faltas'),
                _Dato(valor: '${nota.pendientes}', etiqueta: nota.pendientes == 1 ? 'Pendiente' : 'Pendientes'),
              ],
            ),
            const SizedBox(height: Espacio.l),
            for (final rubro in plan.rubros) ...[
              Padding(
                padding: const EdgeInsets.only(top: Espacio.m, bottom: Espacio.xs),
                child: Text(rubro.nombre.toUpperCase(), style: text.labelSmall),
              ),
              for (final a in plan.actividades.where((a) => a.rubroId == rubro.id))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text(a.titulo)),
                      Text(
                        switch (plan.calificaciones[a.id]?[alumno.id]) {
                          final double v => '${formatoPuntos(v)} / ${formatoPuntos(a.puntos)}',
                          null => 'pendiente / ${formatoPuntos(a.puntos)}',
                        },
                        style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: Espacio.xl),
            const Divider(height: 2),
            const SizedBox(height: Espacio.l),
            Row(
              children: [
                Expanded(child: Text('Observaciones', style: text.titleMedium)),
                TextButton.icon(
                  onPressed: () => comentarioIa(context, ref, plan, alumno, guardar: (texto) async {
                    await ref.read(planesRepositoryProvider).guardarObservacion(plan.claseId, alumno.id,
                        fecha: DateUtils.dateOnly(DateTime.now()), tipo: TipoObservacion.nota, texto: texto);
                    ref.invalidate(observacionesProvider(alumno.id));
                    ref.invalidate(conteoObservacionesProvider(plan.claseId));
                    ref.read(syncControllerProvider.notifier).programar();
                  }),
                  icon: const Icon(iconoIa),
                  label: const Text('Comentario con IA'),
                ),
              ],
            ),
            const SizedBox(height: Espacio.xs),
            Text('Conducta, participación o acuerdos con el padre. Solo las ves tú, salvo que las incluyas en el informe.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: Espacio.s),
            ...observaciones.when(
              loading: () => [const LinearProgressIndicator()],
              error: (error, _) => [Text('No se pudieron cargar: $error')],
              data: (lista) => lista.isEmpty
                  ? [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: Espacio.m),
                        child: Text('Todavía no hay observaciones.', style: text.bodyMedium),
                      ),
                    ]
                  : [
                      for (final o in lista)
                        Card(
                          margin: const EdgeInsets.only(bottom: Espacio.s),
                          child: ListTile(
                            leading: Icon(switch (o.tipo) {
                              TipoObservacion.positiva => Icons.thumb_up_outlined,
                              TipoObservacion.mejora => Icons.flag_outlined,
                              TipoObservacion.nota => Icons.sticky_note_2_outlined,
                            }, color: o.tipo == TipoObservacion.mejora ? scheme.error : scheme.primary),
                            title: Text(o.texto),
                            subtitle: Text('${DateFormat.yMMMd('es').format(o.fecha)} · ${o.tipo.etiqueta}'),
                            onTap: () => editarObservacion(context, ref, plan.claseId, alumno, observacion: o),
                          ),
                        ),
                    ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _compartirInforme(BuildContext context, WidgetRef ref) async {
    final observaciones = ref.read(observacionesProvider(alumno.id)).valueOrNull ?? const <Observacion>[];
    final incluir = await showDialog<bool>(
      context: context,
      builder: (context) => _OpcionesInforme(hayObservaciones: observaciones.isNotEmpty),
    );
    if (incluir == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final clase = await ref.read(claseProvider(plan.claseId).future);
      final planes = await ref.read(planesClaseProvider(plan.claseId).future);
      final bytes = await InformesPdf.informeAlumno(
        clase: clase.resumen,
        docente: ref.read(sessionProvider)?.fullName ?? '',
        alumno: alumno,
        planes: planes,
        detalle: plan,
        observaciones: incluir ? observaciones : const [],
      );
      if (!context.mounted) return;
      await compartirPdf(context, bytes, nombreArchivo('Informe ${alumno.nombre} - ${clase.resumen.asignatura}'));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('No se pudo crear el informe: $error')));
    }
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.valor, required this.etiqueta});

  final String valor;
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(valor, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        Text(etiqueta, style: text.bodySmall),
      ],
    );
  }
}

/// Antes de compartir: si van las observaciones. Por defecto no, porque suelen ser notas
/// personales del docente.
class _OpcionesInforme extends StatefulWidget {
  const _OpcionesInforme({required this.hayObservaciones});

  final bool hayObservaciones;

  @override
  State<_OpcionesInforme> createState() => _OpcionesInformeState();
}

class _OpcionesInformeState extends State<_OpcionesInforme> {
  var _incluir = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: const RoundedRectangleBorder(),
      title: const Text('Informe para el padre o la madre'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Un PDF con la nota de cada parcial, las actividades de este parcial y las faltas. '
              'Lo puedes mandar por WhatsApp o imprimir.'),
          if (widget.hayObservaciones)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _incluir,
              onChanged: (v) => setState(() => _incluir = v ?? false),
              title: const Text('Incluir las observaciones'),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _incluir),
          icon: const Icon(Icons.ios_share),
          label: const Text('Compartir'),
        ),
      ],
    );
  }
}

/// Alta o edición de una observación.
Future<void> editarObservacion(BuildContext context, WidgetRef ref, String claseId, AlumnoPlan alumno,
    {Observacion? observacion}) async {
  final resultado = await showDialog<_ResultadoObservacion>(
    context: context,
    builder: (_) => _FormObservacion(observacion: observacion),
  );
  if (resultado == null) return;
  final repo = ref.read(planesRepositoryProvider);
  void cambiado() {
    ref.invalidate(observacionesProvider(alumno.id));
    ref.invalidate(conteoObservacionesProvider(claseId));
    ref.read(syncControllerProvider.notifier).programar();
  }

  if (resultado.eliminar) {
    await repo.eliminarObservacion(observacion!.id);
    cambiado();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Observación eliminada'),
      action: SnackBarAction(
        label: 'Deshacer',
        onPressed: () async {
          await repo.restaurarObservacion(observacion.id);
          cambiado();
        },
      ),
    ));
    return;
  }
  await repo.guardarObservacion(claseId, alumno.id,
      id: observacion?.id, fecha: resultado.fecha, tipo: resultado.tipo, texto: resultado.texto);
  cambiado();
}

typedef _ResultadoObservacion = ({DateTime fecha, TipoObservacion tipo, String texto, bool eliminar});

class _FormObservacion extends StatefulWidget {
  const _FormObservacion({this.observacion});

  final Observacion? observacion;

  @override
  State<_FormObservacion> createState() => _FormObservacionState();
}

class _FormObservacionState extends State<_FormObservacion> {
  final _form = GlobalKey<FormState>();
  late final _texto = TextEditingController(text: widget.observacion?.texto ?? '');
  late var _tipo = widget.observacion?.tipo ?? TipoObservacion.nota;
  late var _fecha = widget.observacion?.fecha ?? DateUtils.dateOnly(DateTime.now());

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: const RoundedRectangleBorder(),
      title: Text(widget.observacion == null ? 'Nueva observación' : 'Editar observación'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<TipoObservacion>(
                  style: SegmentedButton.styleFrom(shape: const RoundedRectangleBorder()),
                  showSelectedIcon: false,
                  segments: [for (final t in TipoObservacion.values) ButtonSegment(value: t, label: Text(t.etiqueta))],
                  selected: {_tipo},
                  onSelectionChanged: (s) => setState(() => _tipo = s.first),
                ),
                const SizedBox(height: Espacio.l),
                TextFormField(
                  controller: _texto,
                  autofocus: widget.observacion == null,
                  minLines: 3,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: [LengthLimitingTextInputFormatter(1000)],
                  decoration: const InputDecoration(
                    labelText: 'Observación',
                    hintText: 'Participó en la exposición; acuerdo con la madre para revisar tareas…',
                  ),
                  validator: (v) => (v?.trim().isEmpty ?? true) ? 'Escribe la observación' : null,
                ),
                const SizedBox(height: Espacio.l),
                InkWell(
                  onTap: () async {
                    final elegida = await showDatePicker(
                      context: context,
                      initialDate: _fecha,
                      firstDate: DateTime(_fecha.year - 1),
                      lastDate: DateTime.now(),
                    );
                    if (elegida != null) setState(() => _fecha = elegida);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Fecha'),
                    child: Text(DateFormat.yMMMd('es').format(_fecha)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (widget.observacion != null)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(
                context, (fecha: _fecha, tipo: _tipo, texto: '', eliminar: true)),
            child: const Text('Eliminar'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(context, (fecha: _fecha, tipo: _tipo, texto: _texto.text, eliminar: false));
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
