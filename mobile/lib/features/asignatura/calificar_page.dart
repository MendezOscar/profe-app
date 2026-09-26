import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/planes/calculo_parcial.dart';
import '../../core/planes/modelos.dart';
import '../../core/providers.dart';
import '../../core/sync/sync_controller.dart';
import '../../ui/barra_teclado.dart';
import '../../ui/shell.dart';
import 'plan_tab.dart';

/// Captura de una actividad: bajar por la lista escribiendo con el teclado numérico
/// ("Siguiente" o Enter pasa al próximo alumno). Todo se guarda al escribir.
class CalificarPage extends ConsumerWidget {
  const CalificarPage({super.key, required this.claseId, required this.parcial, required this.actividadId});

  final String claseId;
  final String parcial;
  final String actividadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(planProvider((claseId, parcial)));
    return plan.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(appBar: AppBar(), body: Center(child: Text('$error'))),
      data: (plan) {
        final actividad = plan.actividades.where((a) => a.id == actividadId).firstOrNull;
        if (actividad == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('La actividad ya no existe.')));
        }
        // La clave evita reusar el estado si se abre otra actividad en la misma ruta.
        return _Captura(key: ValueKey(actividadId), plan: plan, actividad: actividad);
      },
    );
  }
}

class _Captura extends ConsumerStatefulWidget {
  const _Captura({super.key, required this.plan, required this.actividad});

  final PlanParcial plan;
  final Actividad actividad;

  @override
  ConsumerState<_Captura> createState() => _CapturaState();
}

class _CapturaState extends ConsumerState<_Captura> {
  late final Map<String, double> _notas = {...?widget.plan.calificaciones[widget.actividad.id]};
  late final Map<String, TextEditingController> _controllers = {
    for (final a in widget.plan.alumnos) a.id: TextEditingController(text: _texto(_notas[a.id])),
  };
  late final Map<String, FocusNode> _focus = {for (final a in widget.plan.alumnos) a.id: FocusNode()};
  final Map<String, String> _errores = {};
  final _buscar = TextEditingController();
  var _cambios = false;

  /// El ref no se puede usar en dispose: se guarda el contenedor para refrescar al salir.
  late final ProviderContainer _contenedor;

  PlanParcial get _plan => widget.plan;
  Actividad get _actividad => widget.actividad;
  bool get _soloLectura => _plan.cerrado;

  static String _texto(double? v) => v == null ? '' : formatoPuntos(v);

  @override
  void initState() {
    super.initState();
    _contenedor = ProviderScope.containerOf(context, listen: false);
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    _buscar.dispose();
    // Al salir se refrescan el plan y el tablero una sola vez, no en cada tecla.
    if (_cambios) {
      _contenedor
        ..invalidate(planProvider((_plan.claseId, _plan.parcial.clave)))
        ..invalidate(tableroProvider)
        ..read(syncControllerProvider.notifier).programar();
    }
    super.dispose();
  }

  Future<void> _guardar(AlumnoPlan alumno, String texto) async {
    final limpio = texto.trim();
    final valor = limpio.isEmpty ? null : leerPuntos(limpio);
    if (limpio.isNotEmpty && (valor == null || valor < 0 || valor > _actividad.puntos)) {
      setState(() => _errores[alumno.id] = '0–${formatoPuntos(_actividad.puntos)}');
      return;
    }
    setState(() {
      _errores.remove(alumno.id);
      if (valor == null) {
        _notas.remove(alumno.id);
      } else {
        _notas[alumno.id] = valor;
      }
    });
    _cambios = true;
    await ref.read(planesRepositoryProvider).calificar(_actividad.id, alumno.id, valor);
  }

  /// "Todos entregaron completo" o "los que faltan no entregaron": llena sólo lo vacío.
  Future<void> _llenarVacios(double valor) async {
    for (final a in _plan.alumnos.where((a) => _notas[a.id] == null)) {
      _controllers[a.id]!.text = _texto(valor);
      await _guardar(a, _texto(valor));
    }
  }

  void _siguiente(List<AlumnoPlan> visibles, int i) {
    if (i + 1 < visibles.length) {
      _focus[visibles[i + 1].id]!.requestFocus();
    } else {
      _focus[visibles[i].id]!.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final filtro = _buscar.text.trim().toLowerCase();
    final visibles = [
      for (final a in _plan.alumnos)
        if (filtro.isEmpty || a.nombre.toLowerCase().contains(filtro)) a,
    ];
    final hechas = _plan.alumnos.where((a) => _notas[a.id] != null).length;
    final promedio = hechas == 0 ? null : _notas.values.fold(0.0, (s, v) => s + v) / hechas;
    final rubro = _plan.rubros.where((r) => r.id == _actividad.rubroId).firstOrNull;

    return Scaffold(
      // bottomSheet y no bottomNavigationBar: se acomoda sobre el teclado.
      bottomSheet: const BarraTeclado(),
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => context.canPop() ? context.pop() : context.go('/inicio/asignaturas/${_plan.claseId}'),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_actividad.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              '${rubro?.nombre ?? ''} · vale ${formatoPuntos(_actividad.puntos)} pts',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          if (!_soloLectura)
            PopupMenuButton<double>(
              tooltip: 'Llenar los vacíos',
              icon: const Icon(Icons.playlist_add_check),
              onSelected: _llenarVacios,
              itemBuilder: (context) => [
                PopupMenuItem(
                    value: _actividad.puntos,
                    child: Text('Poner ${formatoPuntos(_actividad.puntos)} a los que faltan')),
                const PopupMenuItem(value: 0, child: Text('Poner 0 a los que faltan (no entregaron)')),
              ],
            ),
        ],
      ),
      body: ContenidoCentrado(
        maxAncho: 720,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      label: '$hechas de ${_plan.alumnos.length} calificados',
                      child: LinearProgressIndicator(
                        value: _plan.alumnos.isEmpty ? 0 : hechas / _plan.alumnos.length,
                        minHeight: 8,
                        backgroundColor: scheme.primaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('$hechas/${_plan.alumnos.length}', style: text.labelLarge),
                  if (promedio != null) ...[
                    const SizedBox(width: 12),
                    Text('Prom. ${formatoPuntos(double.parse(promedio.toStringAsFixed(1)))}',
                        style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            if (_plan.alumnos.length > 12)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _buscar,
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar alumno',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            if (_soloLectura)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('El parcial está cerrado. Reábrelo desde el plan para corregir notas.',
                    style: text.bodySmall?.copyWith(color: scheme.error)),
              ),
            const Divider(height: 2),
            Expanded(
              child: ListView.builder(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.only(bottom: 48),
                itemCount: visibles.length,
                itemBuilder: (context, i) {
                  final alumno = visibles[i];
                  final ultimo = i == visibles.length - 1;
                  final numero = _plan.alumnos.indexOf(alumno) + 1;
                  return ListTile(
                    leading: Text('$numero', style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    minLeadingWidth: 24,
                    title: Text(alumno.nombre, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: SizedBox(
                      width: 88,
                      child: TextField(
                        controller: _controllers[alumno.id],
                        focusNode: _focus[alumno.id],
                        enabled: !_soloLectura,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                          LengthLimitingTextInputFormatter(5),
                        ],
                        textAlign: TextAlign.center,
                        textInputAction: ultimo ? TextInputAction.done : TextInputAction.next,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: '—',
                          errorText: _errores[alumno.id],
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onChanged: (v) => _guardar(alumno, v),
                        onSubmitted: (_) => _siguiente(visibles, i),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
