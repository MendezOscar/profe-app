import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/tokens.dart';
import '../../../ui/estado_error.dart';
import '../../../ui/estado_vacio.dart';
import '../../../ui/esqueleto.dart';
import 'comun_centro.dart';

/// Envoltorio común de las pestañas de estructura: carga, error y lista centrada.
class PestanaEstructura extends ConsumerWidget {
  const PestanaEstructura({super.key, required this.construir});

  final List<Widget> Function(BuildContext context, Map<String, dynamic> datos, bool puedeEditar) construir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estructura = ref.watch(estructuraProvider);
    return estructura.when(
      loading: () => const EsqueletoLista(filas: 5, conTarjeta: true),
      error: (e, _) => EstadoError(error: e, reintentar: () => ref.invalidate(estructuraProvider)),
      data: (datos) => RefreshIndicator(
        onRefresh: () => ref.refresh(estructuraProvider.future),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.xxxl),
              children: construir(context, datos, datos['puedeEditar'] == true),
            ),
          ),
        ),
      ),
    );
  }
}

List<Map<String, dynamic>> lista(Map<String, dynamic> datos, String clave) =>
    (datos[clave] as List).cast<Map<String, dynamic>>();

// ── Año lectivo ──────────────────────────────────────────────────────────────

class AniosTab extends ConsumerWidget {
  const AniosTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => PestanaEstructura(
    construir: (context, datos, editar) {
      final anios = lista(datos, 'anios');
      return [
        EncabezadoPestana(
          titulo: 'Año lectivo',
          ayuda: 'Fechas del año y cierre de cada parcial. El año actual es con el que trabaja el centro.',
          acciones: [
            if (editar)
              FilledButton.icon(
                onPressed: () => _editarAnio(context, ref, null),
                icon: const Icon(Icons.add),
                label: const Text('Nuevo año lectivo'),
              ),
          ],
        ),
        if (anios.isEmpty)
          const EstadoVacio(
            icono: Icons.event_outlined,
            titulo: 'Crea el año lectivo',
            mensaje: 'Empieza por el año: de febrero a noviembre, con el cierre de los cuatro parciales.',
          ),
        for (final a in anios)
          Card(
            margin: const EdgeInsets.only(bottom: Espacio.s),
            child: ListTile(
              title: Text(
                '${a['anio']}${a['actual'] == true ? ' · actual' : ''}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(
                [
                  'Del ${fechaIso(a['inicio'] as String)} al ${fechaIso(a['fin'] as String)}',
                  'Cierres: ${[
                    for (final (i, c) in (a['cierres'] as List).indexed) '${['I', 'II', 'III', 'IV'][i]} ${fechaIso(c as String?)}',
                  ].join(' · ')}',
                ].join('\n'),
              ),
              isThreeLine: true,
              trailing: editar ? const Icon(Icons.edit_outlined) : null,
              onTap: editar ? () => _editarAnio(context, ref, a) : null,
            ),
          ),
      ];
    },
  );
}

Future<void> _editarAnio(BuildContext context, WidgetRef ref, Map<String, dynamic>? anio) {
  final hoy = DateTime.now();
  final numero = TextEditingController(text: '${anio?['anio'] ?? hoy.year}');
  String? inicio = anio?['inicio'] as String? ?? '${hoy.year}-02-01';
  String? fin = anio?['fin'] as String? ?? '${hoy.year}-11-30';
  final cierres = [...((anio?['cierres'] as List?) ?? List.filled(4, null)).cast<String?>()];
  var actual = anio?['actual'] == true;

  return showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => DialogoForm(
        titulo: anio == null ? 'Nuevo año lectivo' : 'Año lectivo ${anio['anio']}',
        contenido: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: numero,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
              decoration: const InputDecoration(labelText: 'Año'),
            ),
            const SizedBox(height: Espacio.m),
            CampoFecha(etiqueta: 'Inicio de clases', valor: inicio, alCambiar: (v) => setState(() => inicio = v)),
            const SizedBox(height: Espacio.m),
            CampoFecha(etiqueta: 'Fin de clases', valor: fin, alCambiar: (v) => setState(() => fin = v)),
            for (var i = 0; i < 4; i++) ...[
              const SizedBox(height: Espacio.m),
              CampoFecha(
                etiqueta: 'Cierre del parcial ${['I', 'II', 'III', 'IV'][i]}',
                valor: cierres[i],
                opcional: true,
                alCambiar: (v) => setState(() => cierres[i] = v),
              ),
            ],
            const SizedBox(height: Espacio.s),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: actual,
              onChanged: anio?['actual'] == true ? null : (v) => setState(() => actual = v ?? false),
              title: const Text('Es el año actual'),
              subtitle: anio?['actual'] == true ? const Text('Para cambiarlo, marca otro año como actual.') : null,
            ),
          ],
        ),
        guardar: () => accionCentro(context, ref, (api) {
          final cuerpo = {
            'anio': int.tryParse(numero.text) ?? 0,
            'inicio': inicio,
            'fin': fin,
            'cierres': cierres,
            'actual': actual,
          };
          return anio == null
              ? api.post<void>('/centro/anios', body: cuerpo)
              : api.put<void>('/centro/anios/${anio['id']}', body: cuerpo);
        }, listo: 'Año lectivo guardado.'),
      ),
    ),
  );
}

// ── Grados y asignaturas ─────────────────────────────────────────────────────

class GradosTab extends ConsumerWidget {
  const GradosTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => PestanaEstructura(
    construir: (context, datos, editar) {
      final grados = lista(datos, 'grados');
      final text = Theme.of(context).textTheme;
      return [
        EncabezadoPestana(
          titulo: 'Grados y asignaturas',
          ayuda: 'Los grados que ofrece el centro y las asignaturas que lleva cada uno.',
          acciones: [
            if (editar) ...[
              OutlinedButton.icon(
                onPressed: () => _plantilla(context, ref),
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('Grados de Honduras'),
              ),
              OutlinedButton.icon(
                onPressed: () => _editarGrado(context, ref, null),
                icon: const Icon(Icons.add),
                label: const Text('Grado'),
              ),
              if (grados.isNotEmpty)
                FilledButton.icon(
                  onPressed: () => _agregarAsignaturas(context, ref, grados, const {}),
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Asignaturas'),
                ),
            ],
          ],
        ),
        if (grados.isEmpty)
          EstadoVacio(
            icono: Icons.school_outlined,
            titulo: 'Agrega los grados del centro',
            mensaje: 'Carga de una vez los grados de prebásica, básica o media y después ajusta los nombres.',
            accion: editar
                ? FilledButton(
                    onPressed: () => _plantilla(context, ref),
                    child: const Text('Cargar grados de Honduras'),
                  )
                : null,
          ),
        for (final nivel in nivelesEducativos.keys)
          if (grados.any((g) => g['nivel'] == nivel)) ...[
            Padding(
              padding: const EdgeInsets.only(top: Espacio.s, bottom: Espacio.s),
              child: Text(nivelesEducativos[nivel]!.toUpperCase(), style: text.labelSmall),
            ),
            for (final g in grados.where((g) => g['nivel'] == nivel)) _Grado(grado: g, grados: grados, editar: editar),
          ],
      ];
    },
  );
}

class _Grado extends ConsumerWidget {
  const _Grado({required this.grado, required this.grados, required this.editar});

  final Map<String, dynamic> grado;
  final List<Map<String, dynamic>> grados;
  final bool editar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final asignaturas = (grado['asignaturas'] as List).cast<Map<String, dynamic>>();
    return Card(
      margin: const EdgeInsets.only(bottom: Espacio.s),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.s, Espacio.xs, Espacio.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('${grado['nombre']}', style: text.titleMedium)),
                if (editar)
                  PopupMenuButton<String>(
                    tooltip: 'Más opciones',
                    onSelected: (o) async {
                      switch (o) {
                        case 'asignaturas':
                          await _agregarAsignaturas(context, ref, grados, {grado['id'] as String});
                        case 'editar':
                          await _editarGrado(context, ref, grado);
                        case 'eliminar':
                          if (await confirmar(
                                context,
                                titulo: 'Eliminar ${grado['nombre']}',
                                mensaje:
                                    'Se eliminan también sus asignaturas. Un grado con secciones no se puede eliminar.',
                              ) &&
                              context.mounted) {
                            await accionCentro(
                              context,
                              ref,
                              (api) => api.delete('/centro/grados/${grado['id']}'),
                              listo: 'Grado eliminado.',
                            );
                          }
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'asignaturas', child: Text('Agregar asignaturas')),
                      PopupMenuItem(value: 'editar', child: Text('Cambiar nombre o nivel')),
                      PopupMenuItem(value: 'eliminar', child: Text('Eliminar grado')),
                    ],
                  ),
              ],
            ),
            if (asignaturas.isEmpty)
              Text(
                'Sin asignaturas',
                style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              )
            else
              Wrap(
                spacing: Espacio.s,
                runSpacing: Espacio.xs,
                children: [
                  for (final a in asignaturas)
                    editar
                        ? InputChip(
                            label: Text('${a['nombre']}'),
                            onPressed: () => _renombrarAsignatura(context, ref, a),
                            onDeleted: () async {
                              if (await confirmar(
                                    context,
                                    titulo: 'Quitar ${a['nombre']}',
                                    mensaje: 'Se quita de ${grado['nombre']} y de la carga docente de sus secciones.',
                                  ) &&
                                  context.mounted) {
                                await accionCentro(context, ref, (api) => api.delete('/centro/asignaturas/${a['id']}'));
                              }
                            },
                            deleteButtonTooltipMessage: 'Quitar',
                          )
                        : Chip(label: Text('${a['nombre']}')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _plantilla(BuildContext context, WidgetRef ref) {
  final elegidos = <String>{'basica'};
  return showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => DialogoForm(
        titulo: 'Grados de Honduras',
        textoGuardar: 'Agregar',
        contenido: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Se agregan los que falten; los que ya tienes no se tocan.'),
            for (final (nivel, detalle) in [
              ('prebasica', 'Prekínder, Kínder y Preparatoria'),
              ('basica', '1.º a 9.º grado'),
              ('media', '10.º a 12.º grado'),
            ])
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: elegidos.contains(nivel),
                onChanged: (v) => setState(() => v == true ? elegidos.add(nivel) : elegidos.remove(nivel)),
                title: Text(nivelesEducativos[nivel]!),
                subtitle: Text(detalle),
              ),
          ],
        ),
        guardar: () => accionCentro(
          context,
          ref,
          (api) => api.post<void>('/centro/grados/plantilla', body: {'niveles': elegidos.toList()}),
          listo: 'Grados agregados.',
        ),
      ),
    ),
  );
}

Future<void> _editarGrado(BuildContext context, WidgetRef ref, Map<String, dynamic>? grado) {
  final nombre = TextEditingController(text: grado?['nombre'] as String? ?? '');
  var nivel = grado?['nivel'] as String? ?? 'basica';
  return showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => DialogoForm(
        titulo: grado == null ? 'Nuevo grado' : 'Editar grado',
        contenido: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: nivel,
              decoration: const InputDecoration(labelText: 'Nivel'),
              items: [for (final e in nivelesEducativos.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => nivel = v ?? nivel),
            ),
            const SizedBox(height: Espacio.m),
            TextField(
              controller: nombre,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Ej.: 10.º BCH, 11.º BTP Informática'),
            ),
          ],
        ),
        guardar: () => accionCentro(context, ref, (api) {
          final cuerpo = {'nivel': nivel, 'nombre': nombre.text};
          return grado == null
              ? api.post<void>('/centro/grados', body: cuerpo)
              : api.put<void>('/centro/grados/${grado['id']}', body: cuerpo);
        }),
      ),
    ),
  );
}

Future<void> _agregarAsignaturas(
  BuildContext context,
  WidgetRef ref,
  List<Map<String, dynamic>> grados,
  Set<String> preelegidos,
) {
  final nombres = TextEditingController();
  final elegidos = {...preelegidos};
  return showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => DialogoForm(
        titulo: 'Agregar asignaturas',
        textoGuardar: 'Agregar',
        contenido: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nombres,
              autofocus: true,
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(
                labelText: 'Asignaturas, una por línea',
                hintText: 'Español\nMatemáticas\nCiencias Naturales',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: Espacio.m),
            Row(
              children: [
                const Expanded(child: Text('En los grados:')),
                TextButton(
                  onPressed: () => setState(
                    () => elegidos.length == grados.length
                        ? elegidos.clear()
                        : elegidos.addAll(grados.map((g) => g['id'] as String)),
                  ),
                  child: Text(elegidos.length == grados.length ? 'Ninguno' : 'Todos'),
                ),
              ],
            ),
            for (final g in grados)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: elegidos.contains(g['id']),
                onChanged: (v) =>
                    setState(() => v == true ? elegidos.add(g['id'] as String) : elegidos.remove(g['id'])),
                title: Text('${g['nombre']}'),
              ),
          ],
        ),
        guardar: () async {
          final lineas = nombres.text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
          if (lineas.isEmpty || elegidos.isEmpty) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Escribe al menos una asignatura y elige los grados.')));
            return false;
          }
          return accionCentro(
            context,
            ref,
            (api) => api.post<void>('/centro/asignaturas', body: {'gradoIds': elegidos.toList(), 'nombres': lineas}),
            listo: 'Asignaturas agregadas.',
          );
        },
      ),
    ),
  );
}

Future<void> _renombrarAsignatura(BuildContext context, WidgetRef ref, Map<String, dynamic> asignatura) {
  final nombre = TextEditingController(text: asignatura['nombre'] as String);
  return showDialog<void>(
    context: context,
    builder: (_) => DialogoForm(
      titulo: 'Renombrar asignatura',
      contenido: TextField(
        controller: nombre,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Nombre'),
      ),
      guardar: () => accionCentro(
        context,
        ref,
        (api) => api.put<void>('/centro/asignaturas/${asignatura['id']}', body: {'nombre': nombre.text}),
      ),
    ),
  );
}

// ── Aulas ────────────────────────────────────────────────────────────────────

class AulasTab extends ConsumerWidget {
  const AulasTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => PestanaEstructura(
    construir: (context, datos, editar) {
      final aulas = lista(datos, 'aulas');
      final secciones = lista(datos, 'secciones');
      final grados = {for (final g in lista(datos, 'grados')) g['id']: g['nombre']};
      return [
        EncabezadoPestana(
          titulo: 'Aulas',
          ayuda: 'Salones, laboratorios y talleres, con cuántos alumnos caben.',
          acciones: [
            if (editar)
              FilledButton.icon(
                onPressed: () => _editarAula(context, ref, null),
                icon: const Icon(Icons.add),
                label: const Text('Nueva aula'),
              ),
          ],
        ),
        if (aulas.isEmpty)
          const EstadoVacio(
            icono: Icons.meeting_room_outlined,
            titulo: 'Sin aulas todavía',
            mensaje: 'Agrega las aulas para asignarlas a cada sección.',
          ),
        for (final a in aulas)
          Card(
            margin: const EdgeInsets.only(bottom: Espacio.s),
            child: ListTile(
              title: Text('${a['nombre']}'),
              subtitle: Text(
                [
                  a['capacidad'] == null ? 'Capacidad sin definir' : 'Capacidad: ${a['capacidad']}',
                  () {
                    final usan = secciones
                        .where((s) => s['aulaId'] == a['id'])
                        .map(
                          (s) => '${grados[s['gradoId']]} ${s['nombre']} (${jornadas[s['jornada']]?.toLowerCase()})',
                        );
                    return usan.isEmpty ? 'Sin secciones este año' : usan.join(', ');
                  }(),
                ].join('\n'),
              ),
              trailing: editar
                  ? PopupMenuButton<String>(
                      tooltip: 'Más opciones',
                      onSelected: (o) async {
                        if (o == 'editar') return _editarAula(context, ref, a);
                        if (await confirmar(
                              context,
                              titulo: 'Eliminar ${a['nombre']}',
                              mensaje: 'Las secciones que la usan quedan sin aula.',
                            ) &&
                            context.mounted) {
                          await accionCentro(context, ref, (api) => api.delete('/centro/aulas/${a['id']}'));
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'editar', child: Text('Editar')),
                        PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
                      ],
                    )
                  : null,
            ),
          ),
      ];
    },
  );
}

Future<void> _editarAula(BuildContext context, WidgetRef ref, Map<String, dynamic>? aula) {
  final nombre = TextEditingController(text: aula?['nombre'] as String? ?? '');
  final capacidad = TextEditingController(text: aula?['capacidad']?.toString() ?? '');
  return showDialog<void>(
    context: context,
    builder: (_) => DialogoForm(
      titulo: aula == null ? 'Nueva aula' : 'Editar aula',
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nombre,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Ej.: Aula 5, Laboratorio de Ciencias'),
          ),
          const SizedBox(height: Espacio.m),
          TextField(
            controller: capacidad,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
            decoration: const InputDecoration(labelText: 'Capacidad (opcional)'),
          ),
        ],
      ),
      guardar: () => accionCentro(context, ref, (api) {
        final cuerpo = {'nombre': nombre.text, 'capacidad': int.tryParse(capacidad.text)};
        return aula == null
            ? api.post<void>('/centro/aulas', body: cuerpo)
            : api.put<void>('/centro/aulas/${aula['id']}', body: cuerpo);
      }),
    ),
  );
}
