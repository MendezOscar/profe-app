import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/tokens.dart';
import '../../../ui/estado_vacio.dart';
import 'carnet.dart';
import 'comun_centro.dart';
import 'estructura_tabs.dart';
import 'consolidado_page.dart';
import 'matricula.dart';

/// Secciones del año elegido: grado, jornada, aula, maestro guía y qué docente da cada asignatura.
class SeccionesTab extends ConsumerWidget {
  const SeccionesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => PestanaEstructura(
    construir: (context, datos, editar) {
      final anios = lista(datos, 'anios');
      final grados = lista(datos, 'grados');
      final secciones = lista(datos, 'secciones');
      final anioId = datos['anioId'] as String?;
      final text = Theme.of(context).textTheme;

      return [
        EncabezadoPestana(
          titulo: 'Secciones',
          ayuda: 'Cada sección con su jornada, aula, maestro guía y el docente de cada asignatura.',
          acciones: [
            if (anios.length > 1)
              DropdownButton<String>(
                value: anioId,
                items: [
                  for (final a in anios) DropdownMenuItem(value: a['id'] as String, child: Text('Año ${a['anio']}')),
                ],
                onChanged: (v) => ref.read(anioElegidoProvider.notifier).state = v,
              ),
            if (editar && anioId != null && grados.isNotEmpty)
              FilledButton.icon(
                onPressed: () => _editarSeccion(context, ref, datos, null),
                icon: const Icon(Icons.add),
                label: const Text('Nueva sección'),
              ),
          ],
        ),
        if (anioId == null)
          const EstadoVacio(
            icono: Icons.event_outlined,
            titulo: 'Primero el año lectivo',
            mensaje: 'Las secciones son de cada año. Crea el año en la pestaña Año lectivo.',
          )
        else if (grados.isEmpty)
          const EstadoVacio(
            icono: Icons.school_outlined,
            titulo: 'Primero los grados',
            mensaje: 'Agrega los grados y sus asignaturas en la pestaña Grados.',
          )
        else if (secciones.isEmpty)
          const EstadoVacio(
            icono: Icons.groups_2_outlined,
            titulo: 'Sin secciones este año',
            mensaje: 'Crea las secciones de cada grado: A, B, C... por jornada.',
          ),
        for (final g in grados)
          if (secciones.any((s) => s['gradoId'] == g['id'])) ...[
            Padding(
              padding: const EdgeInsets.only(top: Espacio.s, bottom: Espacio.s),
              child: Text('${g['nombre']}'.toUpperCase(), style: text.labelSmall),
            ),
            for (final s in secciones.where((s) => s['gradoId'] == g['id']))
              _Seccion(seccion: s, grado: g, datos: datos, editar: editar),
          ],
      ];
    },
  );
}

class _Seccion extends ConsumerWidget {
  const _Seccion({required this.seccion, required this.grado, required this.datos, required this.editar});

  final Map<String, dynamic> seccion;
  final Map<String, dynamic> grado;
  final Map<String, dynamic> datos;
  final bool editar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final docentes = {for (final d in lista(datos, 'docentes')) d['id']: d['nombre']};
    final aulas = {for (final a in lista(datos, 'aulas')) a['id']: a['nombre']};
    final asignaturas = (grado['asignaturas'] as List).length;
    final asignadas = (seccion['carga'] as List).length;
    final completa = asignaturas > 0 && asignadas >= asignaturas;

    return Card(
      margin: const EdgeInsets.only(bottom: Espacio.s),
      child: InkWell(
        onTap: () => _alumnos(context, seccion, grado, editar),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.m, Espacio.xs, Espacio.m),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${grado['nombre']} ${seccion['nombre']} · ${jornadas[seccion['jornada']]}',
                      style: text.titleMedium,
                    ),
                    Text(
                      [
                        'Aula: ${aulas[seccion['aulaId']] ?? 'sin asignar'}',
                        'Guía: ${docentes[seccion['maestroGuiaId']] ?? 'sin asignar'}',
                        'Alumnos: ${seccion['matriculados']}${seccion['cupo'] == null ? '' : ' de ${seccion['cupo']}'}',
                      ].join(' · '),
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: Espacio.xs),
                    Text(
                      asignaturas == 0
                          ? 'El grado no tiene asignaturas'
                          : 'Carga docente: $asignadas de $asignaturas asignaturas',
                      style: text.labelLarge?.copyWith(color: completa ? scheme.primary : scheme.error),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Más opciones',
                onSelected: (o) async {
                  switch (o) {
                    case 'alumnos':
                      _alumnos(context, seccion, grado, editar);
                    case 'consolidado':
                      Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => ConsolidadoPage(
                          seccionId: seccion['id'] as String,
                          titulo: '${grado['nombre']} ${seccion['nombre']}',
                        ),
                      ));
                    case 'carnets':
                      await imprimirCarnets(context, ref, '/centro/secciones/${seccion['id']}/carnets',
                          'Carnets ${grado['nombre']} ${seccion['nombre']}');
                    case 'carga':
                      await _carga(context, ref, seccion, grado, datos, editar);
                    case 'editar':
                      await _editarSeccion(context, ref, datos, seccion);
                    case 'eliminar':
                      if (await confirmar(
                            context,
                            titulo: 'Eliminar ${grado['nombre']} ${seccion['nombre']}',
                            mensaje: 'Se elimina la sección con su carga docente.',
                          ) &&
                          context.mounted) {
                        await accionCentro(
                          context,
                          ref,
                          (api) => api.delete('/centro/secciones/${seccion['id']}'),
                          listo: 'Sección eliminada.',
                        );
                      }
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'alumnos', child: Text('Alumnos')),
                  const PopupMenuItem(value: 'consolidado', child: Text('Consolidado y boletas')),
                  const PopupMenuItem(value: 'carnets', child: Text('Carnets de la sección')),
                  const PopupMenuItem(value: 'carga', child: Text('Carga docente')),
                  if (editar) ...const [
                    PopupMenuItem(value: 'editar', child: Text('Editar sección')),
                    PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _alumnos(BuildContext context, Map<String, dynamic> seccion, Map<String, dynamic> grado, bool editar) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AlumnosSeccionPage(
          seccion: seccion,
          titulo: '${grado['nombre']} ${seccion['nombre']} · ${jornadas[seccion['jornada']]}',
          editar: editar,
        ),
      ),
    );

/// Docentes activos para elegir, más el ya asignado aunque esté inactivo (para no perderlo de vista).
List<DropdownMenuItem<String?>> _opcionesDocente(Map<String, dynamic> datos, String? actual, String vacio) => [
  DropdownMenuItem(value: null, child: Text(vacio)),
  for (final d in lista(datos, 'docentes'))
    if (d['activo'] == true || d['id'] == actual)
      DropdownMenuItem(
        value: d['id'] as String,
        child: Text('${d['nombre']}${d['activo'] == true ? '' : ' (inactivo)'}', overflow: TextOverflow.ellipsis),
      ),
];

Future<void> _editarSeccion(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> datos,
  Map<String, dynamic>? seccion,
) {
  final grados = lista(datos, 'grados');
  final aulas = lista(datos, 'aulas');
  var grado = seccion?['gradoId'] as String? ?? grados.first['id'] as String;
  final nombre = TextEditingController(text: seccion?['nombre'] as String? ?? 'A');
  var jornada = seccion?['jornada'] as String? ?? 'matutina';
  final cupo = TextEditingController(text: seccion?['cupo']?.toString() ?? '');
  var aula = seccion?['aulaId'] as String?;
  var guia = seccion?['maestroGuiaId'] as String?;

  return showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => DialogoForm(
        titulo: seccion == null ? 'Nueva sección' : 'Editar sección',
        contenido: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: grado,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Grado'),
              items: [
                for (final g in grados) DropdownMenuItem(value: g['id'] as String, child: Text('${g['nombre']}')),
              ],
              onChanged: (v) => setState(() => grado = v ?? grado),
            ),
            const SizedBox(height: Espacio.m),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: nombre,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Sección', hintText: 'A'),
                  ),
                ),
                const SizedBox(width: Espacio.m),
                Expanded(
                  child: TextField(
                    controller: cupo,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                    decoration: const InputDecoration(labelText: 'Cupo (opcional)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Espacio.m),
            DropdownButtonFormField<String>(
              initialValue: jornada,
              decoration: const InputDecoration(labelText: 'Jornada'),
              items: [for (final e in jornadas.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => jornada = v ?? jornada),
            ),
            const SizedBox(height: Espacio.m),
            DropdownButtonFormField<String?>(
              initialValue: aula,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Aula'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Sin aula')),
                for (final a in aulas)
                  DropdownMenuItem(
                    value: a['id'] as String,
                    child: Text('${a['nombre']}${a['capacidad'] == null ? '' : ' (${a['capacidad']})'}'),
                  ),
              ],
              onChanged: (v) => setState(() => aula = v),
            ),
            const SizedBox(height: Espacio.m),
            DropdownButtonFormField<String?>(
              initialValue: guia,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Maestro guía'),
              items: _opcionesDocente(datos, guia, 'Sin maestro guía'),
              onChanged: (v) => setState(() => guia = v),
            ),
          ],
        ),
        guardar: () => accionCentro(context, ref, (api) {
          final cuerpo = {
            'anioLectivoId': datos['anioId'],
            'gradoId': grado,
            'nombre': nombre.text,
            'jornada': jornada,
            'cupo': int.tryParse(cupo.text),
            'aulaId': aula,
            'maestroGuiaId': guia,
          };
          return seccion == null
              ? api.post<void>('/centro/secciones', body: cuerpo)
              : api.put<void>('/centro/secciones/${seccion['id']}', body: cuerpo);
        }, listo: 'Sección guardada.'),
      ),
    ),
  );
}

/// Qué docente da cada asignatura del grado en la sección.
Future<void> _carga(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> seccion,
  Map<String, dynamic> grado,
  Map<String, dynamic> datos,
  bool editar,
) {
  final asignaturas = (grado['asignaturas'] as List).cast<Map<String, dynamic>>();
  final docentes = {for (final d in lista(datos, 'docentes')) d['id']: d['nombre']};
  final elegido = <String, String?>{
    for (final c in (seccion['carga'] as List).cast<Map<String, dynamic>>())
      c['asignaturaId'] as String: c['docenteId'] as String,
  };
  final titulo = 'Carga docente · ${grado['nombre']} ${seccion['nombre']}';

  if (asignaturas.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${grado['nombre']} no tiene asignaturas. Agrégalas en la pestaña Grados.')));
    return Future.value();
  }

  if (!editar) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: const RoundedRectangleBorder(),
        title: Text(titulo),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final a in asignaturas)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${a['nombre']}'),
                    subtitle: Text('${docentes[elegido[a['id']]] ?? 'Sin asignar'}'),
                  ),
              ],
            ),
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      ),
    );
  }

  return showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => DialogoForm(
        titulo: titulo,
        contenido: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in asignaturas) ...[
              DropdownButtonFormField<String?>(
                initialValue: elegido[a['id']],
                isExpanded: true,
                decoration: InputDecoration(labelText: '${a['nombre']}'),
                items: _opcionesDocente(datos, elegido[a['id']], 'Sin asignar'),
                onChanged: (v) => setState(() => elegido[a['id'] as String] = v),
              ),
              const SizedBox(height: Espacio.m),
            ],
          ],
        ),
        guardar: () => accionCentro(context, ref, (api) {
          final asignaciones = [
            for (final e in elegido.entries)
              if (e.value != null) {'asignaturaId': e.key, 'docenteId': e.value},
          ];
          return api.put<void>('/centro/secciones/${seccion['id']}/carga', body: {'asignaciones': asignaciones});
        }, listo: 'Carga docente guardada.'),
      ),
    ),
  );
}
