import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/esqueleto.dart';
import '../../ui/estado_error.dart';

const _romanos = ['I', 'II', 'III', 'IV'];
const _letras = ['A', 'B', 'C', 'D', 'E'];

/// Conducta (A–E) de la sección del maestro guía, parcial por parcial. Va a las boletas y la
/// ve la familia. Se guarda en el servidor (necesita internet).
class ConductaPage extends ConsumerStatefulWidget {
  const ConductaPage({super.key, required this.seccionId, required this.titulo});

  final String seccionId;
  final String titulo;

  @override
  ConsumerState<ConductaPage> createState() => _ConductaPageState();
}

class _ConductaPageState extends ConsumerState<ConductaPage> {
  var _parcial = 1;
  List<Map<String, dynamic>>? _alumnos;
  final _notas = <String, String?>{};
  var _cambios = false;
  var _guardando = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _alumnos = null;
      _error = null;
    });
    try {
      final r = await ref.read(apiClientProvider).get('/mi-centro/secciones/${widget.seccionId}/conducta',
          query: {'parcial': _parcial}, parse: (d) => d as Map<String, dynamic>);
      if (!mounted) return;
      setState(() {
        _alumnos = (r['alumnos'] as List).cast<Map<String, dynamic>>();
        _notas
          ..clear()
          ..addAll({for (final a in _alumnos!) a['alumnoId'] as String: a['nota'] as String?});
        _cambios = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiClientProvider).put<void>('/mi-centro/secciones/${widget.seccionId}/conducta', body: {
        'parcial': _parcial,
        'notas': [for (final e in _notas.entries) {'alumnoId': e.key, 'nota': e.value}],
      });
      if (!mounted) return;
      setState(() => _cambios = false);
      messenger.showSnackBar(SnackBar(content: Text('Conducta del parcial ${_romanos[_parcial - 1]} guardada.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.isNetworkError ? 'Necesitas internet para guardar.' : e.message)));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _cambiarParcial(int p) async {
    if (_cambios &&
        await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                shape: const RoundedRectangleBorder(),
                title: const Text('Cambios sin guardar'),
                content: const Text('Si cambias de parcial se pierden las notas que no guardaste.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Quedarme')),
                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cambiar')),
                ],
              ),
            ) !=
            true) {
      return;
    }
    setState(() => _parcial = p);
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final sinNota = _notas.values.where((n) => n == null).length;
    return Scaffold(
      appBar: AppBar(title: Text('Conducta · ${widget.titulo}')),
      bottomNavigationBar: _alumnos == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(Espacio.l),
                child: FilledButton(
                  onPressed: _guardando || !_cambios ? null : _guardar,
                  child: Text(_cambios ? 'Guardar conducta${sinNota > 0 ? ' ($sinNota sin nota)' : ''}' : 'Conducta guardada'),
                ),
              ),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Espacio.l),
            child: SegmentedButton<int>(
              segments: [for (var i = 1; i <= 4; i++) ButtonSegment(value: i, label: Text('Parcial ${_romanos[i - 1]}'))],
              selected: {_parcial},
              showSelectedIcon: false,
              onSelectionChanged: (s) => _cambiarParcial(s.first),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _error != null
                ? EstadoError(error: _error!, reintentar: _cargar)
                : _alumnos == null
                    ? const EsqueletoLista(filas: 8)
                    : ListView(
                        children: [
                          for (final a in _alumnos!)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: Espacio.l, vertical: Espacio.xs),
                              child: Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                runSpacing: Espacio.xs,
                                children: [
                                  Text('${a['nombre']}', style: Theme.of(context).textTheme.bodyLarge),
                                  SegmentedButton<String>(
                                    segments: [for (final l in _letras) ButtonSegment(value: l, label: Text(l))],
                                    selected: {if (_notas[a['alumnoId']] case final n?) n},
                                    emptySelectionAllowed: true,
                                    showSelectedIcon: false,
                                    onSelectionChanged: (s) => setState(() {
                                      _notas[a['alumnoId'] as String] = s.isEmpty ? null : s.first;
                                      _cambios = true;
                                    }),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
