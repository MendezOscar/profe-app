import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/esqueleto.dart';
import '../../ui/estado_error.dart';

const _estados = {null: 'Presente', 'A': 'Ausente', 'T': 'Tarde', 'J': 'Justificada'};

String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Lista del día de la sección del maestro guía. Se guarda en el servidor (necesita
/// internet): la ven el centro y las familias. Tocar alterna presente y ausente; el estado
/// abre las demás opciones.
class ListaDiariaPage extends ConsumerStatefulWidget {
  const ListaDiariaPage({super.key, required this.seccionId, required this.titulo});

  final String seccionId;
  final String titulo;

  @override
  ConsumerState<ListaDiariaPage> createState() => _ListaDiariaPageState();
}

class _ListaDiariaPageState extends ConsumerState<ListaDiariaPage> {
  DateTime _fecha = DateUtils.dateOnly(DateTime.now());
  List<Map<String, dynamic>>? _alumnos;
  final _marcas = <String, String?>{};
  var _tomada = false;
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
      final r = await ref.read(apiClientProvider).get('/mi-centro/secciones/${widget.seccionId}/asistencia',
          query: {'fecha': _iso(_fecha)}, parse: (d) => d as Map<String, dynamic>);
      if (!mounted) return;
      setState(() {
        _alumnos = (r['alumnos'] as List).cast<Map<String, dynamic>>();
        _marcas
          ..clear()
          ..addAll({for (final a in _alumnos!) a['alumnoId'] as String: a['estado'] as String?});
        _tomada = r['tomada'] == true;
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
      await ref.read(apiClientProvider).put<void>('/mi-centro/secciones/${widget.seccionId}/asistencia', body: {
        'fecha': _iso(_fecha),
        'marcas': [
          for (final e in _marcas.entries)
            if (e.value != null) {'alumnoId': e.key, 'estado': e.value},
        ],
      });
      if (!mounted) return;
      setState(() {
        _tomada = true;
        _cambios = false;
      });
      messenger.showSnackBar(const SnackBar(content: Text('Lista guardada. La ven el centro y las familias.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.isNetworkError ? 'Necesitas internet para guardar la lista.' : e.message)));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final faltas = _marcas.values.where((e) => e != null).length;

    return Scaffold(
      appBar: AppBar(title: Text('Lista del día · ${widget.titulo}')),
      bottomNavigationBar: _alumnos == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(Espacio.l),
                child: FilledButton(
                  onPressed: _guardando || (_tomada && !_cambios) ? null : _guardar,
                  child: Text(_tomada && !_cambios ? 'Lista guardada' : 'Guardar lista ($faltas ${faltas == 1 ? 'falta' : 'faltas'})'),
                ),
              ),
            ),
      body: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.event),
            title: Text(MaterialLocalizations.of(context).formatFullDate(_fecha)),
            subtitle: Text(_tomada ? 'Ya se pasó lista este día' : 'Aún sin lista'),
            trailing: TextButton(
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _fecha,
                  firstDate: DateTime(_fecha.year - 1),
                  lastDate: DateUtils.dateOnly(DateTime.now()),
                );
                if (d == null) return;
                _fecha = d;
                await _cargar();
              },
              child: const Text('Cambiar día'),
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
                            ListTile(
                              minTileHeight: Medida.tactil,
                              title: Text('${a['nombre']}'),
                              subtitle: a['excusa'] == null
                                  ? null
                                  : Text('${a['excusa']}', style: text.bodySmall?.copyWith(color: scheme.tertiary)),
                              onTap: () => setState(() {
                                final id = a['alumnoId'] as String;
                                _marcas[id] = _marcas[id] == null ? 'A' : null;
                                _cambios = true;
                              }),
                              trailing: PopupMenuButton<String?>(
                                tooltip: 'Cambiar estado',
                                onSelected: (e) => setState(() {
                                  _marcas[a['alumnoId'] as String] = e;
                                  _cambios = true;
                                }),
                                itemBuilder: (_) => [
                                  for (final e in _estados.entries) PopupMenuItem(value: e.key, child: Text(e.value)),
                                ],
                                child: Chip(
                                  label: Text(_estados[_marcas[a['alumnoId']]]!),
                                  backgroundColor: switch (_marcas[a['alumnoId']]) {
                                    'A' => scheme.errorContainer,
                                    'T' || 'J' => scheme.tertiaryContainer,
                                    _ => null,
                                  },
                                  labelStyle: text.labelLarge,
                                ),
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
