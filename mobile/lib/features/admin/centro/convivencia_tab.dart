import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../theme/tokens.dart';
import '../../../ui/esqueleto.dart';
import '../../../ui/estado_error.dart';
import '../../../ui/estado_vacio.dart';
import 'comun_centro.dart';

final excusasCentroProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) => ref
    .watch(apiClientProvider)
    .get('/centro/excusas', parse: (d) => (d as List).cast<Map<String, dynamic>>()));

const _tiposExcusa = {'excusa': 'Excusa', 'permiso': 'Permiso'};

String _rango(Map<String, dynamic> e) =>
    e['desde'] == e['hasta'] ? fechaIso(e['desde'] as String) : '${fechaIso(e['desde'] as String)} al ${fechaIso(e['hasta'] as String)}';

/// Excusas y permisos que registra el centro. Quien pasa lista (el maestro guía en la lista
/// del día y cada catedrático en su clase) ve al alumno como falta justificada.
class ExcusasTab extends ConsumerWidget {
  const ExcusasTab({super.key, required this.puedeEditar});

  final bool puedeEditar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final excusas = ref.watch(excusasCentroProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final hoy = aIso(DateTime.now());
    return excusas.when(
      loading: () => const EsqueletoLista(filas: 5),
      error: (e, _) => EstadoError(error: e, reintentar: () => ref.invalidate(excusasCentroProvider)),
      data: (lista) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.xxxl),
            children: [
              EncabezadoPestana(
                titulo: 'Excusas y permisos',
                ayuda: 'Al pasar lista, el maestro guía y cada catedrático ven al alumno como falta justificada '
                    'esos días. Se muestran las vigentes y las del último mes.',
                acciones: [
                  if (puedeEditar)
                    FilledButton.icon(
                      onPressed: () => registrarExcusa(context, ref),
                      icon: const Icon(Icons.event_busy_outlined),
                      label: const Text('Registrar excusa'),
                    ),
                ],
              ),
              if (lista.isEmpty)
                const EstadoVacio(
                  icono: Icons.event_busy_outlined,
                  titulo: 'Sin excusas recientes',
                  mensaje: 'Registra la excusa médica o el permiso de un alumno y los docentes la verán al pasar lista.',
                ),
              for (final e in lista)
                Card(
                  margin: const EdgeInsets.only(bottom: Espacio.s),
                  child: ListTile(
                    title: Text('${e['alumno']}${e['seccion'] == null ? '' : ' · ${e['seccion']}'}'),
                    subtitle: Text([
                      '${_tiposExcusa[e['tipo']]} · ${_rango(e)}',
                      '${e['motivo']}',
                      if (e['registradaPor'] != null) 'Registró: ${e['registradaPor']}',
                    ].join('\n')),
                    isThreeLine: true,
                    leading: Icon(
                      e['tipo'] == 'permiso' ? Icons.assignment_turned_in_outlined : Icons.medical_information_outlined,
                      color: (e['hasta'] as String).compareTo(hoy) >= 0 && (e['desde'] as String).compareTo(hoy) <= 0
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    trailing: puedeEditar
                        ? IconButton(
                            tooltip: 'Eliminar',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              if (!await confirmar(context,
                                      titulo: 'Eliminar excusa',
                                      mensaje: 'Las listas que ya se pasaron no cambian; las próximas ya no la mostrarán.') ||
                                  !context.mounted) {
                                return;
                              }
                              if (await accionCentro(context, ref, (api) => api.delete('/centro/excusas/${e['id']}'))) {
                                ref.invalidate(excusasCentroProvider);
                              }
                            },
                          )
                        : null,
                  ),
                ),
              if (lista.isNotEmpty)
                Text('En verde, las que cubren hoy.', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Diálogo para registrar una excusa. Con [alumno] ({id, nombre}) no pide buscarlo.
Future<void> registrarExcusa(BuildContext context, WidgetRef ref, {Map<String, dynamic>? alumno}) async {
  Map<String, dynamic>? elegido = alumno;
  var tipo = 'excusa';
  var desde = aIso(DateTime.now());
  var hasta = desde;
  final motivo = TextEditingController();

  await showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (dialogo, setState) => DialogoForm(
        titulo: 'Registrar excusa',
        contenido: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (alumno != null)
              Text('${alumno['nombre']}', style: Theme.of(dialogo).textTheme.titleMedium)
            else
              BuscarAlumno(alElegir: (a) => setState(() => elegido = a)),
            const SizedBox(height: Espacio.m),
            SegmentedButton<String>(
              segments: [for (final t in _tiposExcusa.entries) ButtonSegment(value: t.key, label: Text(t.value))],
              selected: {tipo},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => tipo = s.first),
            ),
            const SizedBox(height: Espacio.m),
            CampoFecha(
              etiqueta: 'Desde',
              valor: desde,
              alCambiar: (v) => setState(() {
                desde = v ?? desde;
                if (hasta.compareTo(desde) < 0) hasta = desde;
              }),
            ),
            const SizedBox(height: Espacio.s),
            CampoFecha(etiqueta: 'Hasta (incluido)', valor: hasta, alCambiar: (v) => setState(() => hasta = v ?? hasta)),
            const SizedBox(height: Espacio.s),
            TextField(
              controller: motivo,
              maxLength: 300,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Motivo',
                hintText: tipo == 'permiso' ? 'Representa al centro en el torneo de fútbol' : 'Incapacidad médica por gripe',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
        guardar: () async {
          if (elegido == null) {
            ScaffoldMessenger.of(dialogo).showSnackBar(const SnackBar(content: Text('Elige al alumno de la lista.')));
            return false;
          }
          final ok = await accionCentro(dialogo, ref,
              (api) => api.post<void>('/centro/excusas', body: {
                    'alumnoId': elegido!['id'],
                    'tipo': tipo,
                    'desde': desde,
                    'hasta': hasta,
                    'motivo': motivo.text,
                  }),
              listo: 'Excusa registrada.');
          if (ok) ref.invalidate(excusasCentroProvider);
          return ok;
        },
      ),
    ),
  );
}

// ── Incidencias ──────────────────────────────────────────────────────────────

final _soloAbiertasProvider = StateProvider.autoDispose<bool>((ref) => false);

final incidenciasCentroProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) => ref
    .watch(apiClientProvider)
    .get('/centro/incidencias',
        query: {if (ref.watch(_soloAbiertasProvider)) 'abiertas': true},
        parse: (d) => (d as List).cast<Map<String, dynamic>>()));

const gravedades = {'leve': 'Leve', 'grave': 'Grave', 'muy_grave': 'Muy grave'};

Color colorGravedad(BuildContext context, String g) {
  final scheme = Theme.of(context).colorScheme;
  return switch (g) { 'leve' => scheme.tertiary, 'grave' => scheme.error, _ => scheme.onErrorContainer };
}

/// Faltas disciplinarias del año: las registra un catedrático desde la app o el centro aquí.
/// La familia ve fecha, gravedad, descripción y medida (no el seguimiento) y recibe un aviso.
class IncidenciasTab extends ConsumerWidget {
  const IncidenciasTab({super.key, required this.puedeEditar});

  final bool puedeEditar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incidencias = ref.watch(incidenciasCentroProvider);
    final soloAbiertas = ref.watch(_soloAbiertasProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.xxxl),
          children: [
            EncabezadoPestana(
              titulo: 'Incidencias',
              ayuda: 'Faltas leves, graves o muy graves del año. Las registran los catedráticos desde la app o el centro aquí. '
                  'La familia las ve con la medida tomada y recibe un aviso; el seguimiento es interno.',
              acciones: [
                FilterChip(
                  label: const Text('Solo abiertas'),
                  selected: soloAbiertas,
                  onSelected: (v) => ref.read(_soloAbiertasProvider.notifier).state = v,
                ),
                if (puedeEditar)
                  FilledButton.icon(
                    onPressed: () => registrarIncidencia(context, ref),
                    icon: const Icon(Icons.report_outlined),
                    label: const Text('Registrar incidencia'),
                  ),
              ],
            ),
            ...incidencias.when(
              loading: () => [const LinearProgressIndicator()],
              error: (e, _) => [EstadoError(error: e, reintentar: () => ref.invalidate(incidenciasCentroProvider))],
              data: (lista) => [
                if (lista.isEmpty)
                  EstadoVacio(
                    icono: Icons.report_outlined,
                    titulo: soloAbiertas ? 'Sin incidencias abiertas' : 'Sin incidencias este año',
                    mensaje: 'Cuando un catedrático o el centro registre una falta disciplinaria, aparecerá aquí.',
                  ),
                for (final i in lista)
                  Card(
                    margin: const EdgeInsets.only(bottom: Espacio.s),
                    child: InkWell(
                      onTap: puedeEditar ? () => _seguimiento(context, ref, i) : null,
                      child: Padding(
                        padding: const EdgeInsets.all(Espacio.l),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: Espacio.s,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text('${i['alumno']}${i['seccion'] == null ? '' : ' · ${i['seccion']}'}', style: text.titleMedium),
                                Text('Falta ${gravedades[i['gravedad']]!.toLowerCase()}',
                                    style: text.labelLarge?.copyWith(color: colorGravedad(context, i['gravedad'] as String))),
                                if (i['cerrada'] == true)
                                  Text('Cerrada', style: text.labelLarge?.copyWith(color: scheme.primary))
                                else
                                  Text('Abierta', style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
                              ],
                            ),
                            Text(
                              [fechaIso(i['fecha'] as String), if (i['registradaPor'] != null) 'Registró: ${i['registradaPor']}'].join(' · '),
                              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: Espacio.s),
                            Text('${i['descripcion']}'),
                            if (i['medida'] != null) ...[
                              const SizedBox(height: Espacio.xs),
                              Text('Medida: ${i['medida']}', style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                            ],
                            if (i['seguimiento'] != null) ...[
                              const SizedBox(height: Espacio.xs),
                              Text('Seguimiento: ${i['seguimiento']}', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _seguimiento(BuildContext context, WidgetRef ref, Map<String, dynamic> i) async {
    final medida = TextEditingController(text: i['medida'] as String?);
    final seguimiento = TextEditingController(text: i['seguimiento'] as String?);
    var cerrada = i['cerrada'] == true;
    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogo, setState) => DialogoForm(
          titulo: 'Seguimiento · ${i['alumno']}',
          contenido: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${i['descripcion']}'),
              const SizedBox(height: Espacio.m),
              TextField(
                controller: medida,
                maxLength: 500,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(labelText: 'Medida tomada (la ve la familia)'),
              ),
              TextField(
                controller: seguimiento,
                maxLength: 1000,
                maxLines: 5,
                minLines: 2,
                decoration: const InputDecoration(labelText: 'Seguimiento interno', alignLabelWithHint: true),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: cerrada,
                onChanged: (v) => setState(() => cerrada = v),
                title: const Text('Caso cerrado'),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Theme.of(dialogo).colorScheme.error),
                  onPressed: () async {
                    if (!await confirmar(dialogo, titulo: 'Eliminar incidencia', mensaje: 'La familia dejará de verla.') ||
                        !dialogo.mounted) {
                      return;
                    }
                    if (await accionCentro(dialogo, ref, (api) => api.delete('/centro/incidencias/${i['id']}')) &&
                        dialogo.mounted) {
                      ref.invalidate(incidenciasCentroProvider);
                      Navigator.pop(dialogo);
                    }
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Eliminar'),
                ),
              ),
            ],
          ),
          guardar: () async {
            final ok = await accionCentro(dialogo, ref,
                (api) => api.put<void>('/centro/incidencias/${i['id']}',
                    body: {'medida': medida.text, 'seguimiento': seguimiento.text, 'cerrada': cerrada}),
                listo: 'Seguimiento guardado.');
            if (ok) ref.invalidate(incidenciasCentroProvider);
            return ok;
          },
        ),
      ),
    );
  }
}

/// Campos comunes de una incidencia (gravedad, fecha, descripción y medida).
class CamposIncidencia extends StatelessWidget {
  const CamposIncidencia({
    super.key,
    required this.gravedad,
    required this.fecha,
    required this.descripcion,
    required this.medida,
    required this.alGravedad,
    required this.alFecha,
  });

  final String gravedad;
  final String fecha;
  final TextEditingController descripcion;
  final TextEditingController medida;
  final ValueChanged<String> alGravedad;
  final ValueChanged<String> alFecha;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<String>(
            segments: [for (final g in gravedades.entries) ButtonSegment(value: g.key, label: Text(g.value))],
            selected: {gravedad},
            showSelectedIcon: false,
            onSelectionChanged: (s) => alGravedad(s.first),
          ),
          const SizedBox(height: Espacio.m),
          CampoFecha(etiqueta: 'Fecha', valor: fecha, alCambiar: (v) => alFecha(v ?? fecha)),
          const SizedBox(height: Espacio.s),
          TextField(
            controller: descripcion,
            maxLength: 1000,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'Qué pasó', alignLabelWithHint: true),
          ),
          TextField(
            controller: medida,
            maxLength: 500,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Medida tomada (opcional)', hintText: 'Llamada de atención, citación a la familia…'),
          ),
          Text('La familia la verá en la app y recibirá un aviso.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      );
}

/// Diálogo del centro para registrar una incidencia. Con [alumno] ({id, nombre}) no pide buscarlo.
Future<void> registrarIncidencia(BuildContext context, WidgetRef ref, {Map<String, dynamic>? alumno}) async {
  Map<String, dynamic>? elegido = alumno;
  var gravedad = 'leve';
  var fecha = aIso(DateTime.now());
  final descripcion = TextEditingController();
  final medida = TextEditingController();

  await showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (dialogo, setState) => DialogoForm(
        titulo: 'Registrar incidencia',
        contenido: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (alumno != null)
              Text('${alumno['nombre']}', style: Theme.of(dialogo).textTheme.titleMedium)
            else
              BuscarAlumno(alElegir: (a) => setState(() => elegido = a)),
            const SizedBox(height: Espacio.m),
            CamposIncidencia(
              gravedad: gravedad,
              fecha: fecha,
              descripcion: descripcion,
              medida: medida,
              alGravedad: (g) => setState(() => gravedad = g),
              alFecha: (f) => setState(() => fecha = f),
            ),
          ],
        ),
        guardar: () async {
          if (elegido == null) {
            ScaffoldMessenger.of(dialogo).showSnackBar(const SnackBar(content: Text('Elige al alumno de la lista.')));
            return false;
          }
          final ok = await accionCentro(dialogo, ref,
              (api) => api.post<void>('/centro/incidencias', body: {
                    'alumnoId': elegido!['id'],
                    'fecha': fecha,
                    'gravedad': gravedad,
                    'descripcion': descripcion.text,
                    'medida': medida.text,
                  }),
              listo: 'Incidencia registrada.');
          if (ok) ref.invalidate(incidenciasCentroProvider);
          return ok;
        },
      ),
    ),
  );
}

/// Buscador de alumnos activos del centro (nombre o identidad). Al borrar el texto, [alElegir] recibe null.
class BuscarAlumno extends ConsumerWidget {
  const BuscarAlumno({super.key, required this.alElegir});

  final ValueChanged<Map<String, dynamic>?> alElegir;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Autocomplete<Map<String, dynamic>>(
        displayStringForOption: (a) => '${a['nombre']}${a['seccion'] == null ? '' : ' · ${a['seccion']}'}',
        optionsBuilder: (v) async {
          final buscar = v.text.trim();
          if (buscar.length < 3) return const [];
          final r = await ref.read(apiClientProvider).get('/centro/alumnos',
              query: {'buscar': buscar, 'pagina': 0}, parse: (d) => d as Map<String, dynamic>);
          return (r['alumnos'] as List).cast<Map<String, dynamic>>().where((a) => a['estado'] == 'activa');
        },
        onSelected: alElegir,
        fieldViewBuilder: (context, controller, foco, alEnviar) => TextField(
          controller: controller,
          focusNode: foco,
          autofocus: true,
          onChanged: (_) => alElegir(null),
          decoration: const InputDecoration(
            labelText: 'Alumno',
            helperText: 'Escribe al menos 3 letras del nombre o la identidad',
            prefixIcon: Icon(Icons.search),
          ),
        ),
      );
}
