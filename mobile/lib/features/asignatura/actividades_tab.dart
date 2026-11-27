import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models/clase.dart';
import '../../core/planes/calculo_parcial.dart';
import '../../core/planes/modelos.dart';
import '../../core/providers.dart';
import '../../ui/estado_vacio.dart';
import '../../ui/shell.dart';
import 'parcial_cerrado.dart';
import 'plan_tab.dart';
import '../../theme/tokens.dart';
import '../ia/asistente_ia.dart';

/// Actividades del parcial agrupadas por rubro. Tocar una abre la captura de notas.
class ActividadesTab extends ConsumerWidget {
  const ActividadesTab({super.key, required this.plan});

  final PlanParcial plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (plan.rubros.isEmpty) {
      return const EstadoVacio(
        icono: Icons.assignment_outlined,
        titulo: 'Primero arma el plan',
        mensaje: 'Cada actividad pertenece a un rubro del plan. Ve a la pestaña Plan para crearlos.',
      );
    }

    final resultado = calcularParcial(plan);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: plan.cerrado
          ? null
          : FloatingActionButton.extended(
              heroTag: 'nueva-actividad',
              shape: const RoundedRectangleBorder(),
              onPressed: () => editarActividad(context, ref, plan),
              icon: const Icon(Icons.add),
              label: const Text('Nueva actividad'),
            ),
      body: plan.actividades.isEmpty
          ? EstadoVacio(
              icono: Icons.assignment_outlined,
              titulo: 'Sin actividades todavía',
              mensaje: 'Crea tareas, trabajos o exámenes a medida que avanza el parcial. '
                  'Puedes cambiarlos o borrarlos cuando quieras.',
              accion: plan.cerrado
                  ? null
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          onPressed: () => editarActividad(context, ref, plan),
                          icon: const Icon(Icons.add),
                          label: const Text('Nueva actividad'),
                        ),
                        const SizedBox(height: Espacio.s),
                        OutlinedButton.icon(
                          onPressed: () => generarExamenIa(context, ref, plan),
                          icon: const Icon(iconoIa),
                          label: const Text('Generar examen con IA'),
                        ),
                      ],
                    ),
            )
          : ContenidoCentrado(
              maxAncho: 720,
              child: ListView(
                padding: const EdgeInsets.only(bottom: Espacio.bajoBotonFlotante),
                children: [
                  if (plan.cerrado) ParcialCerrado(plan: plan),
                  if (!plan.cerrado && plan.actividades.length > 1)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, 0),
                      child: OutlinedButton.icon(
                        onPressed: () => calificarVarias(context, plan),
                        icon: const Icon(Icons.library_add_check_outlined),
                        label: const Text('Calificar varias a la vez'),
                      ),
                    ),
                  if (!plan.cerrado)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.s, Espacio.l, 0),
                      child: TextButton.icon(
                        onPressed: () => generarExamenIa(context, ref, plan),
                        icon: const Icon(iconoIa),
                        label: const Text('Generar examen con IA'),
                      ),
                    ),
                  for (final rubro in plan.rubros) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.xl, Espacio.l, Espacio.s),
                      child: Row(
                        children: [
                          Expanded(child: Text(rubro.nombre.toUpperCase(), style: text.labelSmall)),
                          Text(
                            '${formatoPuntos(resultado.asignadoPorRubro[rubro.id] ?? 0)} / ${formatoPuntos(rubro.puntos)} pts',
                            style: text.labelSmall?.copyWith(
                              color: (resultado.asignadoPorRubro[rubro.id] ?? 0) > rubro.puntos ? scheme.error : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (final a in plan.actividades.where((a) => a.rubroId == rubro.id))
                      _TileActividad(plan: plan, actividad: a),
                    if (!plan.actividades.any((a) => a.rubroId == rubro.id))
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Espacio.l),
                        child: Text('Sin actividades',
                            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _TileActividad extends ConsumerWidget {
  const _TileActividad({required this.plan, required this.actividad});

  final PlanParcial plan;
  final Actividad actividad;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final notas = plan.calificaciones[actividad.id] ?? const {};
    final hechas = plan.alumnos.where((a) => notas[a.id] != null).length;
    final total = plan.alumnos.length;
    final completa = hechas == total && total > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Espacio.l, 0, Espacio.l, Espacio.s),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.xs, Espacio.xs, Espacio.xs),
          onTap: () => context.go(
              '/inicio/asignaturas/${plan.claseId}/actividades/${actividad.id}?parcial=${Uri.encodeQueryComponent(plan.parcial.clave)}'),
          title: Text(actividad.titulo, style: text.titleMedium),
          subtitle: Text(
            '${DateFormat.MMMd('es').format(actividad.fecha)} · ${formatoPuntos(actividad.puntos)} pts',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: Espacio.s, vertical: Espacio.xs),
                color: completa ? scheme.primaryContainer : scheme.primary,
                child: Text(
                  completa ? 'Calificada' : '$hechas/$total',
                  style: text.labelMedium?.copyWith(
                    color: completa ? scheme.onPrimaryContainer : scheme.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!plan.cerrado)
                PopupMenuButton<String>(
                  tooltip: 'Más opciones',
                  onSelected: (opcion) => opcion == 'editar'
                      ? editarActividad(context, ref, plan, actividad: actividad)
                      : _eliminar(context, ref),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'editar', child: Text('Editar')),
                    PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Sin confirmación: se borra y se ofrece deshacer, que es más rápido y igual de seguro.
  Future<void> _eliminar(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(planesRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    await repo.eliminarActividad(actividad.id);
    planCambiado(ref, plan.claseId, plan.parcial.clave);
    messenger.showSnackBar(SnackBar(
      content: Text('"${actividad.titulo}" eliminada'),
      action: SnackBarAction(
        label: 'Deshacer',
        onPressed: () async {
          await repo.restaurarActividad(actividad.id);
          planCambiado(ref, plan.claseId, plan.parcial.clave);
        },
      ),
    ));
  }
}

/// Elegir qué actividades calificar juntas. Vienen marcadas las que tienen notas pendientes.
Future<void> calificarVarias(BuildContext context, PlanParcial plan) async {
  final resultado = calcularParcial(plan);
  final elegidas = await showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(),
    builder: (_) => _ElegirActividades(
      plan: plan,
      iniciales: {for (final a in resultado.actividadesIncompletas) a.id},
    ),
  );
  if (elegidas == null || elegidas.isEmpty || !context.mounted) return;
  context.go(Uri(
    path: '/inicio/asignaturas/${plan.claseId}/calificar',
    queryParameters: {'parcial': plan.parcial.clave, 'actividades': elegidas.join(',')},
  ).toString());
}

class _ElegirActividades extends StatefulWidget {
  const _ElegirActividades({required this.plan, required this.iniciales});

  final PlanParcial plan;
  final Set<String> iniciales;

  @override
  State<_ElegirActividades> createState() => _ElegirActividadesState();
}

class _ElegirActividadesState extends State<_ElegirActividades> {
  late final Set<String> _marcadas = {...widget.iniciales};

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final plan = widget.plan;
    final total = plan.actividades.where((a) => _marcadas.contains(a.id)).fold(0.0, (s, a) => s + a.puntos);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Espacio.l, 0, Espacio.l, Espacio.s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('¿Qué actividades vas a calificar?', style: text.titleLarge),
                  const SizedBox(height: Espacio.xs),
                  Text('Las calificas todas en una sola pantalla, alumno por alumno.', style: text.bodyMedium),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final a in plan.actividades)
                    CheckboxListTile(
                      value: _marcadas.contains(a.id),
                      onChanged: (v) => setState(() => v! ? _marcadas.add(a.id) : _marcadas.remove(a.id)),
                      title: Text(a.titulo),
                      subtitle: Text([
                        plan.rubros.where((r) => r.id == a.rubroId).firstOrNull?.nombre ?? '',
                        '${formatoPuntos(a.puntos)} pts',
                        if (widget.iniciales.contains(a.id)) 'con pendientes',
                      ].where((t) => t.isNotEmpty).join(' · ')),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Espacio.l),
              child: FilledButton(
                onPressed: _marcadas.isEmpty ? null : () => Navigator.pop(context, [
                  for (final a in plan.actividades)
                    if (_marcadas.contains(a.id)) a.id,
                ]),
                child: Text(_marcadas.isEmpty
                    ? 'Elige al menos una'
                    : 'Calificar ${_marcadas.length} (${formatoPuntos(total)} pts)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Alta o edición de una actividad. Sugiere los puntos que le quedan libres al rubro.
Future<void> editarActividad(BuildContext context, WidgetRef ref, PlanParcial plan, {Actividad? actividad}) async {
  final guardada = await showDialog<bool>(
    context: context,
    builder: (_) => _FormActividad(plan: plan, actividad: actividad),
  );
  if (guardada == true) planCambiado(ref, plan.claseId, plan.parcial.clave);
}

class _FormActividad extends ConsumerStatefulWidget {
  const _FormActividad({required this.plan, this.actividad});

  final PlanParcial plan;
  final Actividad? actividad;

  @override
  ConsumerState<_FormActividad> createState() => _FormActividadState();
}

class _FormActividadState extends ConsumerState<_FormActividad> {
  final _form = GlobalKey<FormState>();
  late final _titulo = TextEditingController(text: widget.actividad?.titulo ?? '');
  late final _descripcion = TextEditingController(text: widget.actividad?.descripcion ?? '');
  late final _puntos = TextEditingController(
      text: widget.actividad == null ? '' : formatoPuntos(widget.actividad!.puntos));
  late String _rubroId = widget.actividad?.rubroId ?? widget.plan.rubros.first.id;
  late DateTime _fecha = widget.actividad?.fecha ?? DateUtils.dateOnly(DateTime.now());

  /// Otras secciones donde también se crea (sólo al crear): clase → su rubro del mismo nombre.
  Map<String, String> _otras = const {};
  final Set<String> _tambien = {};

  @override
  void initState() {
    super.initState();
    if (widget.actividad == null) {
      _sugerirPuntos();
      _buscarOtras();
    }
  }

  /// La misma tarea para Química en cuatro secciones: se crea una vez. Sólo donde el plan del
  /// parcial tiene un rubro con el mismo nombre, para que la nota caiga en el mismo lugar.
  Future<void> _buscarOtras() async {
    final rubro = widget.plan.rubros.firstWhere((r) => r.id == _rubroId);
    final otras = await ref
        .read(planesRepositoryProvider)
        .rubrosIguales(widget.plan.claseId, widget.plan.parcial.clave, rubro.nombre);
    if (!mounted) return;
    setState(() {
      _otras = otras;
      _tambien.removeWhere((c) => !otras.containsKey(c));
    });
  }

  @override
  void dispose() {
    _titulo.dispose();
    _descripcion.dispose();
    _puntos.dispose();
    super.dispose();
  }

  double _libres(String rubroId) {
    final rubro = widget.plan.rubros.firstWhere((r) => r.id == rubroId);
    final usados = widget.plan.actividades
        .where((a) => a.rubroId == rubroId && a.id != widget.actividad?.id)
        .fold(0.0, (s, a) => s + a.puntos);
    return rubro.puntos - usados;
  }

  void _sugerirPuntos() {
    final libres = _libres(_rubroId);
    _puntos.text = libres > 0 ? formatoPuntos(libres) : '';
  }

  @override
  Widget build(BuildContext context) {
    final libres = _libres(_rubroId);
    return AlertDialog(
      shape: const RoundedRectangleBorder(),
      title: Text(widget.actividad == null ? 'Nueva actividad' : 'Editar actividad'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _titulo,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Título', hintText: 'Tarea 1, Examen parcial…'),
                  validator: (v) => (v?.trim().isEmpty ?? true) ? 'Escribe un título' : null,
                ),
                const SizedBox(height: Espacio.l),
                DropdownButtonFormField<String>(
                  initialValue: _rubroId,
                  decoration: const InputDecoration(labelText: 'Rubro'),
                  items: [
                    for (final r in widget.plan.rubros)
                      DropdownMenuItem(value: r.id, child: Text('${r.nombre} (${formatoPuntos(r.puntos)} pts)')),
                  ],
                  onChanged: (id) {
                    setState(() {
                      _rubroId = id!;
                      if (widget.actividad == null) _sugerirPuntos();
                    });
                    if (widget.actividad == null) _buscarOtras();
                  },
                ),
                const SizedBox(height: Espacio.l),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _puntos,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                        decoration: InputDecoration(
                          labelText: 'Vale',
                          suffixText: 'pts',
                          helperText: 'Libres: ${formatoPuntos(libres < 0 ? 0 : libres)}',
                        ),
                        validator: (v) {
                          final n = leerPuntos(v);
                          return n == null || n <= 0 || n > 100 ? 'Más de 0 y hasta 100' : null;
                        },
                      ),
                    ),
                    const SizedBox(width: Espacio.m),
                    Expanded(
                      child: InkWell(
                        onTap: _elegirFecha,
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Fecha'),
                          child: Text(DateFormat.yMMMd('es').format(_fecha)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Espacio.l),
                TextFormField(
                  controller: _descripcion,
                  maxLines: 3,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
                ),
                if (widget.actividad == null) _OtrasSecciones(
                  otras: _otras,
                  elegidas: _tambien,
                  rubro: widget.plan.rubros.firstWhere((r) => r.id == _rubroId).nombre,
                  parcial: widget.plan.parcial.titulo,
                  onCambio: (claseId, si) => setState(() => si ? _tambien.add(claseId) : _tambien.remove(claseId)),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: _guardar, child: const Text('Guardar')),
      ],
    );
  }

  Future<void> _elegirFecha() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(_fecha.year - 1),
      lastDate: DateTime(_fecha.year + 1, 12, 31),
    );
    if (elegida != null) setState(() => _fecha = elegida);
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    final repo = ref.read(planesRepositoryProvider);
    final parcial = widget.plan.parcial.clave;
    for (final (claseId, rubroId) in [
      (widget.plan.claseId, _rubroId),
      for (final c in _tambien) if (_otras[c] case final r?) (c, r),
    ]) {
      await repo.guardarActividad(
        claseId,
        parcial,
        id: claseId == widget.plan.claseId ? widget.actividad?.id : null,
        rubroId: rubroId,
        titulo: _titulo.text,
        fecha: _fecha,
        puntos: leerPuntos(_puntos.text)!,
        descripcion: _descripcion.text,
      );
      if (claseId != widget.plan.claseId) planCambiado(ref, claseId, parcial);
    }
    if (!mounted) return;
    if (_tambien.isNotEmpty) {
      final n = _tambien.length + 1;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Actividad creada en $n secciones')));
    }
    Navigator.pop(context, true);
  }
}

/// Las otras secciones donde se puede crear la misma actividad, para marcarlas.
class _OtrasSecciones extends ConsumerWidget {
  const _OtrasSecciones({
    required this.otras,
    required this.elegidas,
    required this.rubro,
    required this.parcial,
    required this.onCambio,
  });

  final Map<String, String> otras;
  final Set<String> elegidas;
  final String rubro;
  final String parcial;
  final void Function(String claseId, bool si) onCambio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final clases = {for (final c in ref.watch(clasesProvider).valueOrNull ?? const <ClaseResumen>[]) c.id: c};
    final lista = [for (final id in otras.keys) if (clases[id] case final c?) c]
      ..sort((a, b) => '${a.asignatura} ${a.gradoSeccion}'.compareTo('${b.asignatura} ${b.gradoSeccion}'));
    return Padding(
      padding: const EdgeInsets.only(top: Espacio.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('También en otras secciones', style: text.titleSmall),
          const SizedBox(height: Espacio.xs),
          if (lista.isEmpty)
            Text('Ninguna otra sección tiene el rubro «$rubro» en $parcial. Aplica la misma rúbrica para poder '
                'crearla en varias a la vez.', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant))
          else
            for (final c in lista)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: elegidas.contains(c.id),
                onChanged: (v) => onCambio(c.id, v ?? false),
                title: Text(c.asignatura, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(c.gradoSeccion, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
        ],
      ),
    );
  }
}
