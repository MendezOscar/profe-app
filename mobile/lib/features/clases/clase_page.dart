import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/clase.dart';
import '../../core/providers.dart';

/// Captura de una clase, una columna a la vez: en el teléfono es más rápido bajar por la
/// lista escribiendo con el teclado numérico que moverse por una cuadrícula ancha.
/// Las columnas son las que trae la plantilla de SACE, sean las que sean.
class ClasePage extends ConsumerWidget {
  const ClasePage({super.key, required this.claseId});

  final String claseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clase = ref.watch(claseProvider(claseId));
    return clase.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(appBar: AppBar(), body: Center(child: Text('$error'))),
      data: (detalle) => _Captura(detalle: detalle),
    );
  }
}

class _Captura extends ConsumerStatefulWidget {
  const _Captura({required this.detalle});

  final ClaseDetalle detalle;

  @override
  ConsumerState<_Captura> createState() => _CapturaState();
}

class _CapturaState extends ConsumerState<_Captura> {
  late final Map<String, Map<String, int>> _valores = {
    for (final e in widget.detalle.valores.entries) e.key: {...e.value},
  };
  final Map<String, String> _errores = {};
  var _columna = 0;
  var _exportando = false;
  List<TextEditingController> _controllers = [];
  List<FocusNode> _focus = [];

  ClaseDetalle get _clase => widget.detalle;

  @override
  void initState() {
    super.initState();
    _prepararColumna();
  }

  @override
  void dispose() {
    _liberar();
    super.dispose();
  }

  void _liberar() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focus) {
      f.dispose();
    }
  }

  void _prepararColumna() {
    _liberar();
    _errores.clear();
    if (_clase.columnas.isEmpty) return;
    final clave = _clase.columnas[_columna].clave;
    _controllers = [
      for (final a in _clase.alumnos) TextEditingController(text: _valores[a.id]?[clave]?.toString() ?? ''),
    ];
    _focus = [for (final _ in _clase.alumnos) FocusNode()];
  }

  Future<void> _guardar(Alumno alumno, String texto) async {
    final columna = _clase.columnas[_columna];
    final limpio = texto.trim();
    final valor = limpio.isEmpty ? null : int.tryParse(limpio);

    if (limpio.isNotEmpty && (valor == null || valor < columna.tipo.minimo || valor > columna.tipo.maximo)) {
      setState(() => _errores[alumno.id] = '${columna.tipo.minimo}–${columna.tipo.maximo}');
      return;
    }

    setState(() {
      _errores.remove(alumno.id);
      if (valor == null) {
        _valores[alumno.id]?.remove(columna.clave);
      } else {
        (_valores[alumno.id] ??= {})[columna.clave] = valor;
      }
    });
    await ref.read(clasesRepositoryProvider).guardarValor(alumno.id, columna.clave, valor);
  }

  /// Pide a la API el cuadro relleno y lo guarda donde el docente elija, listo para
  /// subirlo en SACE. Avisa antes si hay notas a medio capturar.
  Future<void> _exportar() async {
    final repo = ref.read(clasesRepositoryProvider);
    final cuadro = await repo.paraExportar(_clase.resumen.id);

    if (cuadro.faltantes.isNotEmpty && mounted) {
      final seguir = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Hay notas sin capturar'),
          content: Text('${cuadro.faltantes.join('\n')}\n\nSe exportarán vacías. ¿Continuar?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Revisar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Exportar igual')),
          ],
        ),
      );
      if (seguir != true) return;
    }

    setState(() => _exportando = true);
    try {
      final bytes = await ref.read(exportadorCuadroProvider).exportar(cuadro);
      final extension = cuadro.nombreArchivo.toLowerCase().endsWith('.xlsx') ? 'xlsx' : 'xls';
      await FilePicker.saveFile(
        dialogTitle: 'Guardar cuadro para SACE',
        fileName: cuadro.nombreArchivo,
        type: FileType.custom,
        allowedExtensions: [extension],
        bytes: bytes,
      );
      _avisar('Cuadro listo. Súbelo en SACE: Notas → Cargar Archivos Notas.');
    } on ApiException catch (error) {
      _avisar(error.isNetworkError
          ? 'Necesitas internet para generar el archivo. Lo capturado sigue guardado en el teléfono.'
          : error.message);
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  void _avisar(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _eliminar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar la clase?'),
        content: const Text('Se borran del teléfono los alumnos y todo lo capturado en esta clase.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    await ref.read(clasesRepositoryProvider).eliminar(_clase.resumen.id);
    ref.invalidate(clasesProvider);
    if (mounted) context.pop();
  }

  int _capturados(String clave) => _clase.alumnos.where((a) => _valores[a.id]?[clave] != null).length;

  @override
  Widget build(BuildContext context) {
    final resumen = _clase.resumen;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(resumen.asignatura),
            Text(
              [resumen.gradoSeccion, resumen.jornada].where((t) => t.isNotEmpty).join(' · '),
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Exportar para SACE',
            onPressed: _exportando ? null : _exportar,
            icon: _exportando
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_file),
          ),
          // onSelected y no onTap del ítem: onTap corre antes de cerrar el menú y el
          // cierre se llevaría por delante el diálogo de confirmación.
          PopupMenuButton<String>(
            onSelected: (_) => _eliminar(),
            itemBuilder: (context) => const [PopupMenuItem(value: 'eliminar', child: Text('Eliminar clase'))],
          ),
        ],
      ),
      body: _clase.columnas.isEmpty
          ? const Center(child: Text('La plantilla no trae columnas para capturar.'))
          : Column(
              children: [
                SizedBox(
                  height: 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    children: [
                      for (final (i, columna) in _clase.columnas.indexed)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            selected: i == _columna,
                            label: Text('${columna.titulo}  ${_capturados(columna.clave)}/${_clase.alumnos.length}'),
                            onSelected: (_) => setState(() {
                              _columna = i;
                              _prepararColumna();
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    key: ValueKey(_columna),
                    padding: const EdgeInsets.only(bottom: 48),
                    itemCount: _clase.alumnos.length,
                    itemBuilder: (context, i) {
                      final alumno = _clase.alumnos[i];
                      final ultimo = i == _clase.alumnos.length - 1;
                      return ListTile(
                        leading: Text('${i + 1}', style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                        minLeadingWidth: 24,
                        title: Text(alumno.nombre, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(alumno.identidad, style: text.bodySmall),
                        trailing: SizedBox(
                          width: 76,
                          child: TextField(
                            controller: _controllers[i],
                            focusNode: _focus[i],
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                            textAlign: TextAlign.center,
                            textInputAction: ultimo ? TextInputAction.done : TextInputAction.next,
                            decoration: InputDecoration(
                              isDense: true,
                              errorText: _errores[alumno.id],
                              contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            onChanged: (value) => _guardar(alumno, value),
                            onSubmitted: (_) => ultimo ? _focus[i].unfocus() : _focus[i + 1].requestFocus(),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
