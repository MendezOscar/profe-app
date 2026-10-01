import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/planes/calculo_parcial.dart';
import '../../core/planes/modelos.dart';
import '../../core/providers.dart';
import '../../core/sync/sync_controller.dart';
import '../../ui/barra_puntos.dart';
import '../../ui/shell.dart';
import '../asignatura/plan_tab.dart';
import '../../theme/tokens.dart';
import '../../ui/esqueleto.dart';
import '../../ui/estado_error.dart';

/// Moldes de plan reutilizables. Aplicarlos a una asignatura copia los rubros: cambiar la
/// plantilla después no toca los planes que ya están en marcha.
class PlantillasPage extends ConsumerWidget {
  const PlantillasPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plantillas = ref.watch(plantillasProvider);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Rúbricas de evaluación')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'nueva-plantilla',
        shape: const RoundedRectangleBorder(),
        onPressed: () => editarPlantilla(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nueva rúbrica'),
      ),
      body: plantillas.when(
        loading: () => const EsqueletoLista(filas: 4, conTarjeta: true),
        error: (error, _) => EstadoError(error: error, reintentar: () => ref.invalidate(plantillasProvider)),
        data: (lista) {
          final propias = lista.where((p) => !p.prearmada).toList();
          final prearmadas = lista.where((p) => p.prearmada).toList();
          return ContenidoCentrado(
            maxAncho: 720,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.bajoBotonFlotante),
              children: [
                Text(
                  'Una rúbrica de evaluación reparte los 100 puntos de un parcial en rubros. Úsala al importar cuadros '
                  'o desde el plan de cada asignatura.',
                  style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: Espacio.l),
                if (propias.isNotEmpty) ...[
                  Text('MIS RÚBRICAS', style: text.labelSmall),
                  const SizedBox(height: Espacio.s),
                  for (final p in propias) _TarjetaPlantilla(plantilla: p),
                  const SizedBox(height: Espacio.l),
                ],
                Text('INCLUIDAS', style: text.labelSmall),
                const SizedBox(height: Espacio.s),
                for (final p in prearmadas) _TarjetaPlantilla(plantilla: p),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TarjetaPlantilla extends ConsumerWidget {
  const _TarjetaPlantilla({required this.plantilla});

  final Plantilla plantilla;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Espacio.s),
      child: Card(
        child: InkWell(
          onTap: () => editarPlantilla(context, ref, plantilla: plantilla),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.m, Espacio.xs, Espacio.m),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(plantilla.nombre, style: text.titleMedium),
                      const SizedBox(height: Espacio.xs),
                      Text(plantilla.rubros.map((r) => '${r.nombre} ${formatoPuntos(r.puntos)}').join(' · ')),
                    ],
                  ),
                ),
                if (plantilla.prearmada)
                  IconButton(
                    tooltip: 'Duplicar para editar',
                    onPressed: () => editarPlantilla(context, ref, plantilla: plantilla),
                    icon: const Icon(Icons.copy_outlined),
                  )
                else
                  IconButton(
                    tooltip: 'Eliminar',
                    onPressed: () async {
                      await ref.read(planesRepositoryProvider).eliminarPlantilla(plantilla.id);
                      ref.invalidate(plantillasProvider);
                      ref.read(syncControllerProvider.notifier).programar();
                    },
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Editor de plantilla. Una incluida se guarda como copia propia.
Future<void> editarPlantilla(BuildContext context, WidgetRef ref, {Plantilla? plantilla}) async {
  final guardada = await showDialog<bool>(
    context: context,
    builder: (_) => _EditorPlantilla(plantilla: plantilla),
  );
  if (guardada == true) {
    ref.invalidate(plantillasProvider);
    ref.read(syncControllerProvider.notifier).programar();
  }
}

class _EditorPlantilla extends ConsumerStatefulWidget {
  const _EditorPlantilla({this.plantilla});

  final Plantilla? plantilla;

  @override
  ConsumerState<_EditorPlantilla> createState() => _EditorPlantillaState();
}

class _EditorPlantillaState extends ConsumerState<_EditorPlantilla> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(
    text: widget.plantilla == null
        ? ''
        : widget.plantilla!.prearmada
            ? '${widget.plantilla!.nombre} (copia)'
            : widget.plantilla!.nombre,
  );
  late final List<(TextEditingController, TextEditingController)> _rubros = [
    for (final r in widget.plantilla?.rubros ?? const [RubroPlantilla('Tareas', 40), RubroPlantilla('Examen', 60)])
      (TextEditingController(text: r.nombre), TextEditingController(text: formatoPuntos(r.puntos))),
  ];

  @override
  void dispose() {
    _nombre.dispose();
    for (final (n, p) in _rubros) {
      n.dispose();
      p.dispose();
    }
    super.dispose();
  }

  double get _total => _rubros.fold(0.0, (s, r) => s + (leerPuntos(r.$2.text) ?? 0));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: const RoundedRectangleBorder(),
      title: Text(widget.plantilla == null || widget.plantilla!.prearmada ? 'Nueva rúbrica' : 'Editar rúbrica'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nombre,
                  autofocus: widget.plantilla == null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (v) => (v?.trim().isEmpty ?? true) ? 'Escribe un nombre' : null,
                ),
                const SizedBox(height: Espacio.l),
                BarraPuntos(valor: _total, etiqueta: 'Total'),
                const SizedBox(height: Espacio.l),
                for (final (i, (nombre, puntos)) in _rubros.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Espacio.m),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: nombre,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(labelText: 'Rubro ${i + 1}'),
                            validator: (v) => (v?.trim().isEmpty ?? true) ? 'Falta' : null,
                          ),
                        ),
                        const SizedBox(width: Espacio.s),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: puntos,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                            decoration: const InputDecoration(labelText: 'Puntos'),
                            onChanged: (_) => setState(() {}),
                            validator: (v) {
                              final n = leerPuntos(v);
                              return n == null || n <= 0 ? '> 0' : null;
                            },
                          ),
                        ),
                        IconButton(
                          tooltip: 'Quitar rubro',
                          onPressed: _rubros.length == 1
                              ? null
                              : () => setState(() {
                                    final quitado = _rubros.removeAt(i);
                                    quitado.$1.dispose();
                                    quitado.$2.dispose();
                                  }),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _rubros.add((TextEditingController(), TextEditingController()))),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar rubro'),
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

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    await ref.read(planesRepositoryProvider).guardarPlantilla(
          id: widget.plantilla?.id,
          nombre: _nombre.text,
          rubros: [for (final (n, p) in _rubros) RubroPlantilla(n.text.trim(), leerPuntos(p.text)!)],
        );
    if (mounted) Navigator.pop(context, true);
  }
}
