import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/clase.dart';
import '../../core/providers.dart';
import '../../core/sync/sync_controller.dart';
import '../../ui/barra_teclado.dart';
import 'eliminar_clase.dart';

/// El cuadro de SACE tal cual: captura directa de sus columnas, una a la vez, y exportar.
/// Lo normal es que NOTA TOTAL e INASISTENCIAS lleguen al cerrar el parcial; aquí se
/// corrigen a mano o se llenan NIVELACIÓN y RECUPERACIÓN.
/// En el teléfono, una columna a la vez: es más rápido bajar por la lista escribiendo con
/// el teclado numérico que moverse por una cuadrícula ancha. Con pantalla ancha (tablet,
/// web) se ve el cuadro entero, alumnos por columnas, y se edita en la celda.
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
  final Map<(int, int), FocusNode> _focosTabla = {};

  ClaseDetalle get _clase => widget.detalle;

  @override
  void initState() {
    super.initState();
    _prepararColumna();
  }

  @override
  void dispose() {
    _liberar();
    for (final f in _focosTabla.values) {
      f.dispose();
    }
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

  Future<void> _guardar(Alumno alumno, String texto) => _guardarEn(alumno, _clase.columnas[_columna], texto);

  /// Guarda una celda; si el valor no cabe en la columna devuelve el rango permitido.
  Future<String?> _guardarCelda(Alumno alumno, Columna columna, String texto) async {
    final limpio = texto.trim();
    final valor = limpio.isEmpty ? null : int.tryParse(limpio);
    if (limpio.isNotEmpty && (valor == null || valor < columna.tipo.minimo || valor > columna.tipo.maximo)) {
      return '${columna.tipo.minimo}–${columna.tipo.maximo}';
    }
    setState(() {
      if (valor == null) {
        _valores[alumno.id]?.remove(columna.clave);
      } else {
        (_valores[alumno.id] ??= {})[columna.clave] = valor;
      }
    });
    await ref.read(clasesRepositoryProvider).guardarValor(alumno.id, columna.clave, valor);
    ref.invalidate(claseProvider(_clase.resumen.id));
    ref.read(syncControllerProvider.notifier).programar();
    return null;
  }

  FocusNode _focoTabla(int fila, int columna) => _focosTabla.putIfAbsent((fila, columna), FocusNode.new);

  Future<void> _guardarEn(Alumno alumno, Columna columna, String texto) async {
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
    // Para que al volver a entrar no se muestre lo que había antes de este cambio.
    ref.invalidate(claseProvider(_clase.resumen.id));
    ref.read(syncControllerProvider.notifier).programar();
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

  Future<void> _eliminar() => eliminarClase(context, ref, _clase.resumen);

  int _capturados(String clave) => _clase.alumnos.where((a) => _valores[a.id]?[clave] != null).length;

  @override
  Widget build(BuildContext context) {
    final resumen = _clase.resumen;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      // bottomSheet y no bottomNavigationBar: se acomoda sobre el teclado.
      bottomSheet: const BarraTeclado(),
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
          : LayoutBuilder(
              builder: (context, limites) => limites.maxWidth >= _Tabla.anchoMinimo
                  ? _Tabla(
                      clase: _clase,
                      valores: _valores,
                      ancho: limites.maxWidth,
                      foco: _focoTabla,
                      guardar: _guardarCelda,
                    )
                  : _porColumna(text, scheme),
            ),
    );
  }

  Widget _porColumna(TextTheme text, ColorScheme scheme) => Column(
              children: [
                SizedBox(
                  height: 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
            );
}

/// El cuadro entero: una fila por alumno y una columna por cada columna de SACE, agrupadas
/// por parcial. Enter baja al siguiente alumno en la misma columna.
class _Tabla extends StatelessWidget {
  const _Tabla({required this.clase, required this.valores, required this.ancho, required this.foco, required this.guardar});

  final ClaseDetalle clase;
  final Map<String, Map<String, int>> valores;
  final double ancho;
  final FocusNode Function(int fila, int columna) foco;
  final Future<String?> Function(Alumno alumno, Columna columna, String texto) guardar;

  static const _numero = 44.0;
  static const _nombreMinimo = 260.0;
  static const _celda = 104.0;
  static const _fila = 52.0;

  /// Desde aquí cabe el cuadro entero con los nombres legibles (con scroll lateral si hace falta).
  static const anchoMinimo = 720.0;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final columnas = clase.columnas;
    final total = clase.alumnos.length;
    final nombre = (ancho - 32 - _numero - columnas.length * _celda).clamp(_nombreMinimo, 520.0);
    final anchoTabla = 32 + _numero + nombre + columnas.length * _celda;

    // Grupos seguidos con el mismo nombre: PARCIAL I (INASISTENCIAS, NOTA TOTAL)…
    final grupos = <(String, int)>[];
    for (final c in columnas) {
      if (grupos.isNotEmpty && grupos.last.$1 == c.grupo) {
        grupos.last = (c.grupo, grupos.last.$2 + 1);
      } else {
        grupos.add((c.grupo, 1));
      }
    }
    final borde = BorderSide(color: scheme.outlineVariant);

    Widget encabezado(String texto, double w, {TextStyle? estilo, Alignment alineado = Alignment.center}) => Container(
          width: w,
          alignment: alineado,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(border: Border(left: borde)),
          child: Text(texto, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: estilo),
        );

    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: anchoTabla,
          child: Column(
            children: [
              Container(
                color: scheme.surfaceContainerHigh,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    SizedBox(
                      height: 36,
                      child: Row(
                        children: [
                          SizedBox(width: _numero + nombre),
                          for (final (grupo, n) in grupos)
                            encabezado(grupo, n * _celda, estilo: text.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: scheme.outlineVariant),
                    SizedBox(
                      height: 44,
                      child: Row(
                        children: [
                          SizedBox(width: _numero, child: Text('#', style: text.labelSmall)),
                          SizedBox(width: nombre, child: Text('ALUMNO · $total', style: text.labelSmall)),
                          for (final c in columnas)
                            encabezado(
                              c.grupo == c.nombre ? '' : c.nombre,
                              _celda,
                              estilo: text.labelSmall,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: scheme.outline),
              Expanded(
                child: ListView.builder(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.only(bottom: 48),
                  itemExtent: _fila,
                  itemCount: total,
                  itemBuilder: (context, i) {
                    final alumno = clase.alumnos[i];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: i.isOdd ? scheme.surfaceContainerLowest : null,
                        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: _numero,
                            child: Text('${i + 1}', style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                          ),
                          SizedBox(
                            width: nombre,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(alumno.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
                                Text(alumno.identidad, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          for (final (j, c) in columnas.indexed)
                            Container(
                              width: _celda,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(border: Border(left: borde)),
                              child: _Celda(
                                key: ValueKey('${alumno.id}|${c.clave}'),
                                valor: valores[alumno.id]?[c.clave],
                                foco: foco(i, j),
                                siguiente: i + 1 < total ? foco(i + 1, j) : null,
                                guardar: (texto) => guardar(alumno, c, texto),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Celda extends StatefulWidget {
  const _Celda({super.key, required this.valor, required this.foco, required this.siguiente, required this.guardar});

  final int? valor;
  final FocusNode foco;
  final FocusNode? siguiente;
  final Future<String?> Function(String texto) guardar;

  @override
  State<_Celda> createState() => _CeldaState();
}

class _CeldaState extends State<_Celda> {
  late final _texto = TextEditingController(text: widget.valor?.toString() ?? '');
  String? _error;

  @override
  void didUpdateWidget(covariant _Celda anterior) {
    super.didUpdateWidget(anterior);
    final nuevo = widget.valor?.toString() ?? '';
    if (!widget.foco.hasFocus && _error == null && nuevo != _texto.text) _texto.text = nuevo;
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Tooltip(
        message: _error ?? '',
        child: TextField(
          controller: _texto,
          focusNode: widget.foco,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
          textAlign: TextAlign.center,
          textInputAction: widget.siguiente == null ? TextInputAction.done : TextInputAction.next,
          decoration: InputDecoration(
            isDense: true,
            hintText: '—',
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
            enabledBorder: _error == null
                ? null
                : OutlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.error, width: 2)),
          ),
          onChanged: (texto) async {
            final error = await widget.guardar(texto);
            if (mounted && error != _error) setState(() => _error = error);
          },
          onSubmitted: (_) => widget.siguiente == null ? widget.foco.unfocus() : widget.siguiente!.requestFocus(),
        ),
      );
}
