import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/planes/calculo_parcial.dart';
import '../../core/planes/modelos.dart';
import '../../core/providers.dart';
import '../../ui/estado_vacio.dart';
import '../../ui/shell.dart';
import 'parcial_cerrado.dart';
import 'plan_tab.dart';

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
                  : FilledButton.icon(
                      onPressed: () => editarActividad(context, ref, plan),
                      icon: const Icon(Icons.add),
                      label: const Text('Nueva actividad'),
                    ),
            )
          : ContenidoCentrado(
              maxAncho: 720,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: [
                  if (plan.cerrado) ParcialCerrado(plan: plan),
                  for (final rubro in plan.rubros) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
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
                        padding: const EdgeInsets.symmetric(horizontal: 16),
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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

  @override
  void initState() {
    super.initState();
    if (widget.actividad == null) _sugerirPuntos();
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
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _rubroId,
                  decoration: const InputDecoration(labelText: 'Rubro'),
                  items: [
                    for (final r in widget.plan.rubros)
                      DropdownMenuItem(value: r.id, child: Text('${r.nombre} (${formatoPuntos(r.puntos)} pts)')),
                  ],
                  onChanged: (id) => setState(() {
                    _rubroId = id!;
                    if (widget.actividad == null) _sugerirPuntos();
                  }),
                ),
                const SizedBox(height: 16),
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
                          return n == null || n <= 0 || n > 100 ? 'Entre 0 y 100' : null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
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
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descripcion,
                  maxLines: 3,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
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
    await ref.read(planesRepositoryProvider).guardarActividad(
          widget.plan.claseId,
          widget.plan.parcial.clave,
          id: widget.actividad?.id,
          rubroId: _rubroId,
          titulo: _titulo.text,
          fecha: _fecha,
          puntos: leerPuntos(_puntos.text)!,
          descripcion: _descripcion.text,
        );
    if (mounted) Navigator.pop(context, true);
  }
}
