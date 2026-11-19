import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../theme/tokens.dart';
import '../../../ui/esqueleto.dart';
import '../../../ui/estado_error.dart';
import '../../../ui/estado_vacio.dart';
import 'comun_centro.dart';
import '../../ia/asistente_ia.dart' show iconoIa;
import 'centro_ia.dart';

final familiaProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, alumno) =>
    ref.watch(apiClientProvider).get('/centro/alumnos/$alumno/familia', parse: (d) => d as Map<String, dynamic>));

final comunicadosCentroProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) => ref
    .watch(apiClientProvider)
    .get('/centro/comunicados', parse: (d) => (d as List).cast<Map<String, dynamic>>()));

String _fechaHora(String iso) {
  final d = DateTime.parse(iso).toLocal();
  return '${fechaIso(aIso(d))} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// En la ficha: el código para que la familia cree su cuenta y quiénes ya entraron.
class AccesoFamilia extends ConsumerWidget {
  const AccesoFamilia({super.key, required this.alumnoId, required this.nombre, required this.editar});

  final String alumnoId;
  final String nombre;
  final bool editar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final familia = ref.watch(familiaProvider(alumnoId));
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return familia.when(
      loading: () => const Padding(padding: EdgeInsets.all(Espacio.l), child: LinearProgressIndicator()),
      error: (e, _) => EstadoError(error: e, reintentar: () => ref.invalidate(familiaProvider(alumnoId))),
      data: (f) {
        final codigo = f['codigo'] as Map<String, dynamic>?;
        final vinculos = (f['vinculos'] as List).cast<Map<String, dynamic>>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('La familia ve notas, asistencia, entregas y comunicados en la app ProfeApp. '
                'No ve la ficha (salud ni notas de secretaría).',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: Espacio.s),
            if (codigo != null)
              Card(
                margin: const EdgeInsets.only(bottom: Espacio.s),
                child: ListTile(
                  title: SelectableText('${codigo['codigo']}',
                      style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 2)),
                  subtitle: Text('Vence el ${fechaIso(aIso(DateTime.parse(codigo['expiraEn'] as String).toLocal()))}'),
                  trailing: IconButton(
                    tooltip: 'Copiar instrucciones',
                    icon: const Icon(Icons.copy),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(
                          text: 'Para ver las notas y la asistencia de $nombre, descarga ProfeApp (App Store o Google Play) '
                              'o entra a https://profeapphn.com/app/, toca «Soy padre o madre» y escribe este código: '
                              '${codigo['codigo']}'));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('Instrucciones copiadas para enviar a la familia.')));
                      }
                    },
                  ),
                ),
              ),
            if (editar)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    if (codigo != null &&
                        !await confirmar(context,
                            titulo: 'Generar otro código',
                            mensaje: 'El código actual dejará de servir. Las cuentas que ya entraron no se afectan.',
                            accion: 'Generar')) {
                      return;
                    }
                    if (!context.mounted) return;
                    if (await accionCentro(context, ref, (api) => api.post<void>('/centro/alumnos/$alumnoId/familia/codigo'))) {
                      ref.invalidate(familiaProvider(alumnoId));
                    }
                  },
                  icon: const Icon(Icons.key_outlined),
                  label: Text(codigo == null ? 'Generar código para la familia' : 'Generar otro código'),
                ),
              ),
            const SizedBox(height: Espacio.s),
            if (vinculos.isEmpty)
              Text('Ninguna cuenta de familia todavía.', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            for (final v in vinculos)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.family_restroom_outlined),
                title: Text('${v['nombre']}'),
                subtitle: Text('${v['email']} · desde ${fechaIso(aIso(DateTime.parse(v['desde'] as String).toLocal()))}'),
                trailing: editar
                    ? TextButton(
                        onPressed: () async {
                          if (!await confirmar(context,
                                  titulo: 'Quitar acceso',
                                  mensaje: '${v['nombre']} dejará de ver a $nombre en la app.',
                                  accion: 'Quitar') ||
                              !context.mounted) {
                            return;
                          }
                          if (await accionCentro(context, ref,
                              (api) => api.delete('/centro/alumnos/$alumnoId/familia/${v['usuarioId']}'),
                              listo: 'Acceso quitado.')) {
                            ref.invalidate(familiaProvider(alumnoId));
                          }
                        },
                        child: Text('Quitar', style: TextStyle(color: scheme.error)),
                      )
                    : null,
              ),
          ],
        );
      },
    );
  }
}

/// Comunicados del centro a las familias, con cuántas los leyeron.
class ComunicadosTab extends ConsumerWidget {
  const ComunicadosTab({super.key, required this.puedeEditar});

  final bool puedeEditar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comunicados = ref.watch(comunicadosCentroProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return comunicados.when(
      loading: () => const EsqueletoLista(filas: 4, conTarjeta: true),
      error: (e, _) => EstadoError(error: e, reintentar: () => ref.invalidate(comunicadosCentroProvider)),
      data: (lista) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.xxxl),
            children: [
              EncabezadoPestana(
                titulo: 'Comunicados',
                ayuda: 'Avisos a las familias que tienen cuenta: a todo el centro o a ciertas secciones.',
                acciones: [
                  if (puedeEditar)
                    FilledButton.icon(
                      onPressed: () => _nuevo(context, ref),
                      icon: const Icon(Icons.campaign_outlined),
                      label: const Text('Nuevo comunicado'),
                    ),
                ],
              ),
              if (lista.isEmpty)
                const EstadoVacio(
                  icono: Icons.campaign_outlined,
                  titulo: 'Sin comunicados',
                  mensaje: 'Publica avisos de reuniones, suspensiones o actividades. Las familias los ven en la app.',
                ),
              for (final c in lista)
                Card(
                  margin: const EdgeInsets.only(bottom: Espacio.s),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.m, Espacio.xs, Espacio.m),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${c['titulo']}', style: text.titleMedium),
                              Text(
                                [
                                  _fechaHora(c['publicadoEn'] as String),
                                  (c['seccionIds'] as List).isEmpty
                                      ? 'Todo el centro'
                                      : '${(c['seccionIds'] as List).length} ${(c['seccionIds'] as List).length == 1 ? 'sección' : 'secciones'}',
                                  if (c['autor'] != null) '${c['autor']}',
                                ].join(' · '),
                                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: Espacio.s),
                              Text('${c['cuerpo']}'),
                              const SizedBox(height: Espacio.s),
                              Text('Leído por ${c['leidos']} de ${c['destinatarios']} familias',
                                  style: text.labelLarge?.copyWith(color: scheme.primary)),
                            ],
                          ),
                        ),
                        if (puedeEditar)
                          IconButton(
                            tooltip: 'Eliminar',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              if (!await confirmar(context,
                                      titulo: 'Eliminar comunicado',
                                      mensaje: 'Las familias dejarán de verlo.') ||
                                  !context.mounted) {
                                return;
                              }
                              if (await accionCentro(context, ref, (api) => api.delete('/centro/comunicados/${c['id']}'))) {
                                ref.invalidate(comunicadosCentroProvider);
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _nuevo(BuildContext context, WidgetRef ref) async {
    final datos = await ref.read(estructuraProvider.future);
    if (!context.mounted) return;
    final grados = {for (final g in (datos['grados'] as List).cast<Map<String, dynamic>>()) g['id']: g['nombre']};
    final secciones = (datos['secciones'] as List).cast<Map<String, dynamic>>();
    final titulo = TextEditingController();
    final cuerpo = TextEditingController();
    var todo = true;
    final elegidas = <String>{};

    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogo, setState) => DialogoForm(
          titulo: 'Nuevo comunicado',
          textoGuardar: 'Publicar',
          contenido: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final r = await redactarComunicadoIa(dialogo, ref,
                        destinatarios: todo ? null : 'familias de ${elegidas.length} ${elegidas.length == 1 ? 'sección' : 'secciones'}');
                    if (r == null) return;
                    setState(() {
                      titulo.text = r.$1;
                      cuerpo.text = r.$2;
                    });
                  },
                  icon: const Icon(iconoIa),
                  label: const Text('Redactar con IA'),
                ),
              ),
              TextField(
                controller: titulo,
                autofocus: true,
                maxLength: 160,
                decoration: const InputDecoration(labelText: 'Título', hintText: 'Reunión de padres'),
              ),
              TextField(
                controller: cuerpo,
                minLines: 4,
                maxLines: 10,
                maxLength: 4000,
                decoration: const InputDecoration(labelText: 'Mensaje', alignLabelWithHint: true),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: todo,
                onChanged: (v) => setState(() => todo = v),
                title: const Text('Para todo el centro'),
              ),
              if (!todo)
                for (final s in secciones)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: elegidas.contains(s['id']),
                    onChanged: (v) => setState(() => v == true ? elegidas.add(s['id'] as String) : elegidas.remove(s['id'])),
                    title: Text('${grados[s['gradoId']]} ${s['nombre']} · ${jornadas[s['jornada']]}'),
                  ),
            ],
          ),
          guardar: () async {
            if (!todo && elegidas.isEmpty) {
              ScaffoldMessenger.of(dialogo).showSnackBar(const SnackBar(content: Text('Elige al menos una sección.')));
              return false;
            }
            final ok = await accionCentro(dialogo, ref,
                (api) => api.post<void>('/centro/comunicados', body: {
                      'titulo': titulo.text,
                      'cuerpo': cuerpo.text,
                      'seccionIds': todo ? null : elegidas.toList(),
                    }),
                listo: 'Comunicado publicado.');
            if (ok) ref.invalidate(comunicadosCentroProvider);
            return ok;
          },
        ),
      ),
    );
  }
}
