import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/providers.dart';
import '../../../theme/tokens.dart';
import '../../../ui/estado_error.dart';
import '../../../ui/estado_vacio.dart';
import 'comun_centro.dart';
import 'estructura_tabs.dart';

const diasSemana = ['', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'];

final bloquesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) =>
    ref.watch(apiClientProvider).get('/centro/bloques', parse: (d) => (d as List).cast<Map<String, dynamic>>()));

final choquesProvider = FutureProvider.autoDispose<List<String>>((ref) =>
    ref.watch(apiClientProvider).get('/centro/horario/choques', parse: (d) => (d as List).cast<String>()));

final horarioSeccionProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) =>
    ref.watch(apiClientProvider).get('/centro/secciones/$id/horario', parse: (d) => d as Map<String, dynamic>));

final horarioDocenteProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, id) => ref
    .watch(apiClientProvider)
    .get('/centro/docentes/$id/horario', parse: (d) => (d as List).cast<Map<String, dynamic>>()));

/// "07:00:00" → "7:00".
String hora(String t) {
  final p = t.split(':');
  return '${int.parse(p[0])}:${p[1]}';
}

String _aHora(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

TimeOfDay _deHora(String t) {
  final p = t.split(':');
  return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
}

/// Bloques por jornada, horario de cada sección (o de un docente) y choques.
class HorarioTab extends ConsumerStatefulWidget {
  const HorarioTab({super.key});

  @override
  ConsumerState<HorarioTab> createState() => _HorarioTabState();
}

class _HorarioTabState extends ConsumerState<HorarioTab> {
  String? _seccion;
  String? _docente;

  @override
  Widget build(BuildContext context) => PestanaEstructura(
        construir: (context, datos, editar) {
          final text = Theme.of(context).textTheme;
          final scheme = Theme.of(context).colorScheme;
          final secciones = lista(datos, 'secciones');
          final grados = {for (final g in lista(datos, 'grados')) g['id']: g};
          final docentes = lista(datos, 'docentes');
          final bloques = ref.watch(bloquesProvider).valueOrNull ?? const [];
          final choques = ref.watch(choquesProvider).valueOrNull ?? const [];
          final seccion = secciones.where((s) => s['id'] == _seccion).firstOrNull;

          return [
            const EncabezadoPestana(
              titulo: 'Horario',
              ayuda: 'Primero los bloques de cada jornada; después, qué asignatura va en cada bloque de cada sección. '
                  'El docente sale de la carga docente.',
            ),
            if (choques.isNotEmpty)
              Card(
                color: scheme.errorContainer,
                margin: const EdgeInsets.only(bottom: Espacio.l),
                child: Padding(
                  padding: const EdgeInsets.all(Espacio.l),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Choques en el horario', style: text.titleSmall?.copyWith(color: scheme.onErrorContainer)),
                      const SizedBox(height: Espacio.xs),
                      for (final c in choques) Text('• $c', style: TextStyle(color: scheme.onErrorContainer)),
                    ],
                  ),
                ),
              ),
            _Bloques(bloques: bloques, editar: editar),
            const SizedBox(height: Espacio.xl),
            Wrap(
              spacing: Espacio.l,
              runSpacing: Espacio.s,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<String>(
                  value: _seccion,
                  hint: const Text('Horario de la sección…'),
                  items: [
                    for (final s in secciones)
                      DropdownMenuItem(
                        value: s['id'] as String,
                        child: Text('${grados[s['gradoId']]?['nombre']} ${s['nombre']} · ${jornadas[s['jornada']]}'),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _seccion = v;
                    _docente = null;
                  }),
                ),
                DropdownButton<String>(
                  value: _docente,
                  hint: const Text('…o de un docente'),
                  items: [for (final d in docentes) DropdownMenuItem(value: d['id'] as String, child: Text('${d['nombre']}'))],
                  onChanged: (v) => setState(() {
                    _docente = v;
                    _seccion = null;
                  }),
                ),
              ],
            ),
            const SizedBox(height: Espacio.m),
            if (seccion != null)
              _HorarioSeccion(
                key: ValueKey(seccion['id']),
                seccion: seccion,
                grado: grados[seccion['gradoId']]!,
                bloques: bloques.where((b) => b['jornada'] == seccion['jornada']).toList(),
                datos: datos,
                editar: editar,
              )
            else if (_docente != null)
              _HorarioDocente(docenteId: _docente!)
            else
              Text('Elige una sección para armar su horario, o un docente para ver el suyo.',
                  style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ];
        },
      );
}

class _Bloques extends ConsumerWidget {
  const _Bloques({required this.bloques, required this.editar});

  final List<Map<String, dynamic>> bloques;
  final bool editar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final usadas = {for (final b in bloques) b['jornada'] as String};
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Espacio.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('BLOQUES DE CLASE', style: text.labelSmall)),
                if (editar)
                  TextButton.icon(
                    onPressed: () => _editarBloque(context, ref, null),
                    icon: const Icon(Icons.add),
                    label: const Text('Bloque'),
                  ),
              ],
            ),
            if (bloques.isEmpty)
              Text('Agrega los períodos de cada jornada: 1.ª hora de 7:00 a 7:45, receso, etc.', style: text.bodySmall),
            for (final j in jornadas.keys.where(usadas.contains)) ...[
              const SizedBox(height: Espacio.s),
              Text(jornadas[j]!, style: text.labelLarge),
              Wrap(
                spacing: Espacio.s,
                runSpacing: Espacio.xs,
                children: [
                  for (final (i, b) in bloques.where((b) => b['jornada'] == j).indexed)
                    ActionChip(
                      // El número cuenta solo las horas de clase, no los recesos.
                      label: Text('${b['esReceso'] == true ? 'Receso' : '${bloques.where((x) => x['jornada'] == j).take(i + 1).where((x) => x['esReceso'] != true).length}.'} '
                          '${hora(b['inicio'] as String)}–${hora(b['fin'] as String)}'),
                      onPressed: editar ? () => _editarBloque(context, ref, b) : null,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> _editarBloque(BuildContext context, WidgetRef ref, Map<String, dynamic>? bloque) {
  var jornada = bloque?['jornada'] as String? ?? 'matutina';
  var inicio = bloque == null ? const TimeOfDay(hour: 7, minute: 0) : _deHora(bloque['inicio'] as String);
  var fin = bloque == null ? const TimeOfDay(hour: 7, minute: 45) : _deHora(bloque['fin'] as String);
  var receso = bloque?['esReceso'] == true;
  return showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (dialogo, setState) => AlertDialog(
        shape: const RoundedRectangleBorder(),
        title: Text(bloque == null ? 'Nuevo bloque' : 'Editar bloque'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: jornada,
                decoration: const InputDecoration(labelText: 'Jornada'),
                items: [for (final e in jornadas.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => jornada = v ?? jornada),
              ),
              const SizedBox(height: Espacio.m),
              Row(
                children: [
                  for (final (etiqueta, valor, cambiar) in [
                    ('Empieza', inicio, (TimeOfDay t) => inicio = t),
                    ('Termina', fin, (TimeOfDay t) => fin = t),
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: Espacio.s),
                        child: InkWell(
                          onTap: () async {
                            final t = await showTimePicker(context: dialogo, initialTime: valor);
                            if (t != null) setState(() => cambiar(t));
                          },
                          child: InputDecorator(
                            decoration: InputDecoration(labelText: etiqueta),
                            child: Text(valor.format(dialogo)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: receso,
                onChanged: (v) => setState(() => receso = v ?? false),
                title: const Text('Es receso'),
              ),
            ],
          ),
        ),
        actions: [
          if (bloque != null)
            TextButton(
              onPressed: () async {
                if (await accionCentro(dialogo, ref, (api) => api.delete('/centro/bloques/${bloque['id']}'))) {
                  ref.invalidate(bloquesProvider);
                  if (dialogo.mounted) Navigator.pop(dialogo);
                }
              },
              child: Text('Eliminar', style: TextStyle(color: Theme.of(dialogo).colorScheme.error)),
            ),
          TextButton(onPressed: () => Navigator.pop(dialogo), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              final cuerpo = {'jornada': jornada, 'inicio': _aHora(inicio), 'fin': _aHora(fin), 'esReceso': receso};
              final ok = await accionCentro(dialogo, ref, (api) => bloque == null
                  ? api.post<void>('/centro/bloques', body: cuerpo)
                  : api.put<void>('/centro/bloques/${bloque['id']}', body: cuerpo));
              if (ok) {
                ref.invalidate(bloquesProvider);
                if (dialogo.mounted) Navigator.pop(dialogo);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
}

/// Cuadrícula días × bloques de una sección. Los cambios se guardan juntos.
class _HorarioSeccion extends ConsumerStatefulWidget {
  const _HorarioSeccion({
    super.key,
    required this.seccion,
    required this.grado,
    required this.bloques,
    required this.datos,
    required this.editar,
  });

  final Map<String, dynamic> seccion;
  final Map<String, dynamic> grado;
  final List<Map<String, dynamic>> bloques;
  final Map<String, dynamic> datos;
  final bool editar;

  @override
  ConsumerState<_HorarioSeccion> createState() => _HorarioSeccionState();
}

typedef _Celda = ({String asignatura, String? aula});

class _HorarioSeccionState extends ConsumerState<_HorarioSeccion> {
  Map<(int, String), _Celda>? _celdas;
  var _cambios = false;
  var _guardando = false;
  String? _error;

  String get _id => widget.seccion['id'] as String;

  @override
  Widget build(BuildContext context) {
    final horario = ref.watch(horarioSeccionProvider(_id));
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (widget.bloques.isEmpty) {
      return EstadoVacio(
        icono: Icons.schedule,
        titulo: 'Sin bloques de la jornada ${jornadas[widget.seccion['jornada']]?.toLowerCase()}',
        mensaje: 'Agrega arriba los bloques de esa jornada.',
      );
    }
    return horario.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => EstadoError(error: e, reintentar: () => ref.invalidate(horarioSeccionProvider(_id))),
      data: (h) {
        _celdas ??= {
          for (final c in (h['celdas'] as List).cast<Map<String, dynamic>>())
            (c['dia'] as int, c['bloqueId'] as String): (asignatura: c['asignaturaId'] as String, aula: c['aulaId'] as String?),
        };
        final asignaturas = {for (final a in (widget.grado['asignaturas'] as List).cast<Map<String, dynamic>>()) a['id']: a['nombre']};
        final carga = {
          for (final c in (widget.seccion['carga'] as List).cast<Map<String, dynamic>>()) c['asignaturaId']: c['docenteId'],
        };
        final docentes = {for (final d in lista(widget.datos, 'docentes')) d['id']: d['nombre']};
        final aulas = {for (final a in lista(widget.datos, 'aulas')) a['id']: a['nombre']};
        final dias = widget.seccion['jornada'] == 'sabatina' ? [6] : [1, 2, 3, 4, 5];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (asignaturas.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: Espacio.m),
                child: Text('El grado no tiene asignaturas. Agrégalas en la pestaña Grados.', style: TextStyle(color: scheme.error)),
              ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultColumnWidth: const FixedColumnWidth(150),
                columnWidths: const {0: FixedColumnWidth(96)},
                border: TableBorder.all(color: scheme.outlineVariant),
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: scheme.surfaceContainerHigh),
                    children: [
                      const SizedBox(),
                      for (final d in dias)
                        Padding(padding: const EdgeInsets.all(Espacio.s), child: Text(diasSemana[d], style: text.labelLarge)),
                    ],
                  ),
                  for (final b in widget.bloques)
                    TableRow(
                      decoration: b['esReceso'] == true ? BoxDecoration(color: scheme.surfaceContainerHighest) : null,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(Espacio.s),
                          child: Text('${hora(b['inicio'] as String)}\n${hora(b['fin'] as String)}', style: text.labelSmall),
                        ),
                        for (final d in dias)
                          b['esReceso'] == true
                              ? Padding(
                                  padding: const EdgeInsets.all(Espacio.s),
                                  child: Text('Receso', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                                )
                              : InkWell(
                                  onTap: widget.editar && asignaturas.isNotEmpty
                                      ? () => _elegir(d, b['id'] as String, asignaturas, aulas)
                                      : null,
                                  child: Padding(
                                    padding: const EdgeInsets.all(Espacio.s),
                                    child: switch (_celdas![(d, b['id'] as String)]) {
                                      null => Text(widget.editar ? '+' : '', style: text.bodySmall),
                                      final c => Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('${asignaturas[c.asignatura]}', style: text.labelLarge, maxLines: 2),
                                            Text('${docentes[carga[c.asignatura]] ?? 'Sin docente'}',
                                                style: text.bodySmall?.copyWith(
                                                    color: carga[c.asignatura] == null ? scheme.error : scheme.onSurfaceVariant),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis),
                                            if (c.aula != null) Text('${aulas[c.aula]}', style: text.bodySmall),
                                          ],
                                        ),
                                    },
                                  ),
                                ),
                      ],
                    ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: Espacio.m),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
            if (widget.editar) ...[
              const SizedBox(height: Espacio.m),
              FilledButton(
                onPressed: !_cambios || _guardando ? null : _guardar,
                child: Text(_cambios ? 'Guardar horario' : 'Horario guardado'),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _elegir(int dia, String bloque, Map<dynamic, dynamic> asignaturas, Map<dynamic, dynamic> aulas) async {
    final actual = _celdas![(dia, bloque)];
    String? asignatura = actual?.asignatura;
    String? aula = actual?.aula;
    final listo = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogo, setState) => AlertDialog(
          shape: const RoundedRectangleBorder(),
          title: Text(diasSemana[dia]),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String?>(
                  initialValue: asignatura,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Asignatura'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Libre')),
                    for (final e in asignaturas.entries) DropdownMenuItem(value: e.key as String, child: Text('${e.value}')),
                  ],
                  onChanged: (v) => setState(() => asignatura = v),
                ),
                const SizedBox(height: Espacio.m),
                DropdownButtonFormField<String?>(
                  initialValue: aula,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Aula'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('La de la sección')),
                    for (final e in aulas.entries) DropdownMenuItem(value: e.key as String, child: Text('${e.value}')),
                  ],
                  onChanged: (v) => setState(() => aula = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogo, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(dialogo, true), child: const Text('Listo')),
          ],
        ),
      ),
    );
    if (listo != true) return;
    setState(() {
      if (asignatura == null) {
        _celdas!.remove((dia, bloque));
      } else {
        _celdas![(dia, bloque)] = (asignatura: asignatura!, aula: aula);
      }
      _cambios = true;
      _error = null;
    });
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      await ref.read(apiClientProvider).put<void>('/centro/secciones/$_id/horario', body: {
        'celdas': [
          for (final e in _celdas!.entries)
            {'dia': e.key.$1, 'bloqueId': e.key.$2, 'asignaturaId': e.value.asignatura, 'aulaId': e.value.aula},
        ],
      });
      ref.invalidate(choquesProvider);
      if (!mounted) return;
      setState(() => _cambios = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Horario guardado.')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.isNetworkError ? 'Necesitas internet.' : e.message);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }
}

class _HorarioDocente extends ConsumerWidget {
  const _HorarioDocente({required this.docenteId});

  final String docenteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final horario = ref.watch(horarioDocenteProvider(docenteId));
    final text = Theme.of(context).textTheme;
    return horario.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => EstadoError(error: e, reintentar: () => ref.invalidate(horarioDocenteProvider(docenteId))),
      data: (clases) => clases.isEmpty
          ? const Text('Este docente aún no tiene clases en el horario.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final d in {for (final c in clases) c['dia'] as int}) ...[
                  const SizedBox(height: Espacio.s),
                  Text(diasSemana[d].toUpperCase(), style: text.labelSmall),
                  for (final c in clases.where((c) => c['dia'] == d))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Text('${hora(c['inicio'] as String)}–${hora(c['fin'] as String)}', style: text.labelLarge),
                      title: Text('${c['asignatura']} · ${c['seccion']}'),
                      subtitle: c['aula'] == null ? null : Text('${c['aula']}'),
                    ),
                ],
              ],
            ),
    );
  }
}

// ── Asistencia del día ───────────────────────────────────────────────────────

final asistenciaDelDiaProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, fecha) => ref
    .watch(apiClientProvider)
    .get('/centro/asistencia-diaria', query: {'fecha': fecha}, parse: (d) => d as Map<String, dynamic>));

/// Qué secciones pasaron la lista del día y quién faltó.
class AsistenciaDiaTab extends ConsumerStatefulWidget {
  const AsistenciaDiaTab({super.key});

  @override
  ConsumerState<AsistenciaDiaTab> createState() => _AsistenciaDiaTabState();
}

class _AsistenciaDiaTabState extends ConsumerState<AsistenciaDiaTab> {
  String _fecha = aIso(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final dia = ref.watch(asistenciaDelDiaProvider(_fecha));
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    const estados = {'A': 'Ausente', 'T': 'Tarde', 'J': 'Justificada'};
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.xxxl),
          children: [
            const EncabezadoPestana(
              titulo: 'Asistencia del día',
              ayuda: 'La lista que pasa cada maestro guía en la app. Las familias ven las faltas de sus hijos.',
            ),
            SizedBox(
              width: 260,
              child: CampoFecha(etiqueta: 'Día', valor: _fecha, alCambiar: (v) => setState(() => _fecha = v ?? _fecha)),
            ),
            const SizedBox(height: Espacio.l),
            ...dia.when(
              loading: () => [const LinearProgressIndicator()],
              error: (e, _) => [EstadoError(error: e, reintentar: () => ref.invalidate(asistenciaDelDiaProvider(_fecha)))],
              data: (d) {
                final secciones = (d['secciones'] as List).cast<Map<String, dynamic>>();
                final tomadas = secciones.where((s) => s['tomada'] == true).length;
                return [
                  Text('$tomadas de ${secciones.length} secciones pasaron lista', style: text.titleMedium),
                  const SizedBox(height: Espacio.s),
                  for (final s in secciones)
                    Card(
                      margin: const EdgeInsets.only(bottom: Espacio.s),
                      child: ListTile(
                        title: Text('${s['seccion']}'),
                        subtitle: Text(
                          s['tomada'] != true
                              ? 'Sin lista${s['guia'] == null ? ' · sin maestro guía' : ' · ${s['guia']}'}'
                              : (s['faltas'] as List).isEmpty
                                  ? 'Todos presentes (${s['activos']})'
                                  : [
                                      for (final f in (s['faltas'] as List).cast<Map<String, dynamic>>())
                                        '${f['nombre']} (${estados[f['estado']]})',
                                    ].join(', '),
                          style: text.bodySmall?.copyWith(color: s['tomada'] == true ? null : scheme.error),
                        ),
                        trailing: Icon(s['tomada'] == true ? Icons.check_circle_outline : Icons.schedule,
                            color: s['tomada'] == true ? scheme.primary : scheme.onSurfaceVariant),
                      ),
                    ),
                ];
              },
            ),
          ],
        ),
      ),
    );
  }
}
