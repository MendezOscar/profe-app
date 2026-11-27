import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/clase.dart';
import '../../core/planes/modelos.dart';
import '../../core/providers.dart';
import '../../core/sync/sync_controller.dart';
import '../../theme/tokens.dart';
import '../../ui/esqueleto.dart';
import '../../ui/estado_error.dart';
import '../../ui/estado_vacio.dart';
import '../../ui/shell.dart';

/// Equipos de trabajo de una asignatura. Se arman una vez y sirven para calificar cualquier
/// trabajo en grupo: la nota del equipo pasa a cada integrante.
class EquiposPage extends ConsumerWidget {
  const EquiposPage({super.key, required this.claseId});

  final String claseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clase = ref.watch(claseProvider(claseId));
    final equipos = ref.watch(equiposProvider(claseId));
    return clase.when(
      loading: () => const EsqueletoPagina(),
      error: (error, _) => PaginaError(error: error, reintentar: () => ref.invalidate(claseProvider(claseId))),
      data: (clase) => Scaffold(
        appBar: AppBar(
          leading: BackButton(
            onPressed: () => context.canPop() ? context.pop() : context.go('/inicio/asignaturas/$claseId'),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Equipos'),
              Text(
                '${clase.resumen.asignatura} · ${clase.resumen.gradoSeccion}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Armar al azar',
              icon: const Icon(Icons.shuffle),
              onPressed: () => _alAzar(context, ref, clase, equipos.valueOrNull ?? const []),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'nuevo-equipo',
          shape: const RoundedRectangleBorder(),
          onPressed: () => editarEquipo(context, ref, clase, equipos.valueOrNull ?? const []),
          icon: const Icon(Icons.group_add_outlined),
          label: const Text('Nuevo equipo'),
        ),
        body: equipos.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => PaginaError(error: error, reintentar: () => ref.invalidate(equiposProvider(claseId))),
          data: (lista) => lista.isEmpty
              ? EstadoVacio(
                  icono: Icons.groups_outlined,
                  titulo: 'Sin equipos todavía',
                  mensaje: 'Arma los equipos de los trabajos en grupo. Al calificar una actividad, pones una nota '
                      'por equipo y pasa a cada integrante.',
                  accion: OutlinedButton.icon(
                    onPressed: () => _alAzar(context, ref, clase, lista),
                    icon: const Icon(Icons.shuffle),
                    label: const Text('Armar al azar'),
                  ),
                )
              : _Lista(clase: clase, equipos: lista),
        ),
      ),
    );
  }

  /// Reparte a los alumnos que no tienen equipo en equipos de un tamaño dado.
  Future<void> _alAzar(BuildContext context, WidgetRef ref, ClaseDetalle clase, List<Equipo> equipos) async {
    final ocupados = {for (final e in equipos) ...e.miembros};
    final libres = [for (final a in clase.alumnos) if (!ocupados.contains(a.id)) a.id];
    if (libres.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Todos los alumnos ya tienen equipo.')));
      return;
    }
    final tamano = await showDialog<int>(
      context: context,
      builder: (context) => _ElegirTamano(libres: libres.length),
    );
    if (tamano == null) return;
    libres.shuffle(Random());
    final repo = ref.read(planesRepositoryProvider);
    final grupos = (libres.length / tamano).ceil();
    // Reparte por turnos: los equipos quedan parejos (de 4 y 5, no de 5 y 1).
    final reparto = List.generate(grupos, (_) => <String>[]);
    for (final (i, id) in libres.indexed) {
      reparto[i % grupos].add(id);
    }
    final creados = <String>[];
    for (final (i, miembros) in reparto.indexed) {
      creados.add(await repo.guardarEquipo(clase.resumen.id, nombre: 'Equipo ${equipos.length + i + 1}', miembros: miembros));
    }
    _cambiado(ref, clase.resumen.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${creados.length} equipos armados'),
      action: SnackBarAction(
        label: 'Deshacer',
        onPressed: () async {
          for (final id in creados) {
            await repo.eliminarEquipo(id);
          }
          _cambiado(ref, clase.resumen.id);
        },
      ),
    ));
  }
}

void _cambiado(WidgetRef ref, String claseId) {
  ref.invalidate(equiposProvider(claseId));
  ref.read(syncControllerProvider.notifier).programar();
}

class _ElegirTamano extends StatefulWidget {
  const _ElegirTamano({required this.libres});

  final int libres;

  @override
  State<_ElegirTamano> createState() => _ElegirTamanoState();
}

class _ElegirTamanoState extends State<_ElegirTamano> {
  var _tamano = 4;

  @override
  Widget build(BuildContext context) {
    final grupos = (widget.libres / _tamano).ceil();
    return AlertDialog(
      shape: const RoundedRectangleBorder(),
      title: const Text('Armar equipos al azar'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.libres} alumnos sin equipo.'),
          const SizedBox(height: Espacio.l),
          Row(
            children: [
              const Expanded(child: Text('Integrantes por equipo')),
              IconButton(
                tooltip: 'Menos',
                onPressed: _tamano > 2 ? () => setState(() => _tamano--) : null,
                icon: const Icon(Icons.remove),
              ),
              Text('$_tamano', style: Theme.of(context).textTheme.titleLarge),
              IconButton(
                tooltip: 'Más',
                onPressed: _tamano < 10 ? () => setState(() => _tamano++) : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          Text('Quedan $grupos equipos.', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, _tamano), child: const Text('Armar')),
      ],
    );
  }
}

class _Lista extends ConsumerWidget {
  const _Lista({required this.clase, required this.equipos});

  final ClaseDetalle clase;
  final List<Equipo> equipos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final nombres = {for (final a in clase.alumnos) a.id: a.nombre};
    final ocupados = {for (final e in equipos) ...e.miembros};
    final sinEquipo = clase.alumnos.where((a) => !ocupados.contains(a.id)).length;
    return ContenidoCentrado(
      maxAncho: 720,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.bajoBotonFlotante),
        children: [
          if (sinEquipo > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: Espacio.m),
              child: Text(
                sinEquipo == 1 ? '1 alumno sin equipo.' : '$sinEquipo alumnos sin equipo.',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          for (final e in equipos)
            Card(
              margin: const EdgeInsets.only(bottom: Espacio.s),
              child: ListTile(
                title: Text(e.nombre, style: text.titleMedium),
                subtitle: Text(
                  [for (final m in e.miembros) if (nombres[m] case final n?) n].join(' · '),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text('${e.miembros.length}', style: text.labelLarge),
                onTap: () => editarEquipo(context, ref, clase, equipos, equipo: e),
              ),
            ),
        ],
      ),
    );
  }
}

/// Alta o edición de un equipo: nombre e integrantes. Muestra en qué equipo está ya cada alumno.
Future<void> editarEquipo(BuildContext context, WidgetRef ref, ClaseDetalle clase, List<Equipo> equipos,
    {Equipo? equipo}) async {
  final resultado = await showDialog<_ResultadoEquipo>(
    context: context,
    builder: (_) => _FormEquipo(clase: clase, equipos: equipos, equipo: equipo),
  );
  if (resultado == null) return;
  final repo = ref.read(planesRepositoryProvider);
  if (resultado.eliminar) {
    await repo.eliminarEquipo(equipo!.id);
    _cambiado(ref, clase.resumen.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('"${equipo.nombre}" eliminado'),
      action: SnackBarAction(
        label: 'Deshacer',
        onPressed: () async {
          await repo.restaurarEquipo(equipo.id);
          _cambiado(ref, clase.resumen.id);
        },
      ),
    ));
    return;
  }
  // Un alumno está en un solo equipo: si se pasó a este, sale del anterior.
  for (final otro in equipos) {
    if (otro.id == equipo?.id) continue;
    final quedan = otro.miembros.where((m) => !resultado.miembros.contains(m)).toList();
    if (quedan.length != otro.miembros.length) {
      await repo.guardarEquipo(clase.resumen.id, id: otro.id, nombre: otro.nombre, miembros: quedan);
    }
  }
  await repo.guardarEquipo(clase.resumen.id, id: equipo?.id, nombre: resultado.nombre, miembros: resultado.miembros);
  _cambiado(ref, clase.resumen.id);
}

typedef _ResultadoEquipo = ({String nombre, List<String> miembros, bool eliminar});

class _FormEquipo extends StatefulWidget {
  const _FormEquipo({required this.clase, required this.equipos, this.equipo});

  final ClaseDetalle clase;
  final List<Equipo> equipos;
  final Equipo? equipo;

  @override
  State<_FormEquipo> createState() => _FormEquipoState();
}

class _FormEquipoState extends State<_FormEquipo> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.equipo?.nombre ?? 'Equipo ${widget.equipos.length + 1}');
  late final Set<String> _miembros = {...?widget.equipo?.miembros};

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final enOtro = {
      for (final e in widget.equipos)
        if (e.id != widget.equipo?.id)
          for (final m in e.miembros) m: e.nombre,
    };
    return AlertDialog(
      shape: const RoundedRectangleBorder(),
      title: Text(widget.equipo == null ? 'Nuevo equipo' : 'Editar equipo'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nombre,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [LengthLimitingTextInputFormatter(60)],
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: (v) => (v?.trim().isEmpty ?? true) ? 'Escribe un nombre' : null,
              ),
              const SizedBox(height: Espacio.m),
              Text('Integrantes: ${_miembros.length}', style: text.titleSmall),
              const SizedBox(height: Espacio.xs),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final a in widget.clase.alumnos)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _miembros.contains(a.id),
                        onChanged: (v) => setState(() => v == true ? _miembros.add(a.id) : _miembros.remove(a.id)),
                        title: Text(a.nombre, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: enOtro[a.id] == null
                            ? null
                            : Text('Ahora en ${enOtro[a.id]}', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.equipo != null)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            onPressed: () => Navigator.pop(context, (nombre: '', miembros: const <String>[], eliminar: true)),
            child: const Text('Eliminar'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            if (_miembros.isEmpty) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Elige al menos un integrante.')));
              return;
            }
            Navigator.pop(context, (
              nombre: _nombre.text,
              miembros: [for (final a in widget.clase.alumnos) if (_miembros.contains(a.id)) a.id],
              eliminar: false,
            ));
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
