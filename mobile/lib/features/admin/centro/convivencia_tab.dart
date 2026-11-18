import 'package:flutter/material.dart';
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
              Autocomplete<Map<String, dynamic>>(
                displayStringForOption: (a) => '${a['nombre']}${a['seccion'] == null ? '' : ' · ${a['seccion']}'}',
                optionsBuilder: (v) async {
                  final buscar = v.text.trim();
                  if (buscar.length < 3) return const [];
                  final r = await ref.read(apiClientProvider).get('/centro/alumnos',
                      query: {'buscar': buscar, 'pagina': 0}, parse: (d) => d as Map<String, dynamic>);
                  return (r['alumnos'] as List).cast<Map<String, dynamic>>().where((a) => a['estado'] == 'activa');
                },
                onSelected: (a) => setState(() => elegido = a),
                fieldViewBuilder: (context, controller, foco, alEnviar) => TextField(
                  controller: controller,
                  focusNode: foco,
                  autofocus: true,
                  onChanged: (_) {
                    if (elegido != null) setState(() => elegido = null);
                  },
                  decoration: const InputDecoration(
                    labelText: 'Alumno',
                    helperText: 'Escribe al menos 3 letras del nombre o la identidad',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
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
