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

/// Varias actividades calificadas de una pasada: cuando el docente revisa el cuaderno y
/// aprovecha para poner las notas atrasadas. Dos modos: una nota por actividad, o una
/// sola nota sobre el total que se reparte en proporción a lo que vale cada actividad.
class CalificarVariasPage extends ConsumerWidget {
  const CalificarVariasPage({super.key, required this.claseId, required this.parcial, required this.actividadIds});

  final String claseId;
  final String parcial;
  final List<String> actividadIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(planProvider((claseId, parcial)));
    return plan.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(appBar: AppBar(), body: Center(child: Text('$error'))),
      data: (plan) {
        final actividades = [
          for (final a in plan.actividades)
            if (actividadIds.contains(a.id)) a,
        ];
        if (actividades.isEmpty) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('Esas actividades ya no existen.')));
        }
        return _Captura(key: ValueKey(actividadIds.join(',')), plan: plan, actividades: actividades);
      },
    );
  }
}

class _Captura extends ConsumerStatefulWidget {
  const _Captura({super.key, required this.plan, required this.actividades});

  final PlanParcial plan;
  final List<Actividad> actividades;

  @override
  ConsumerState<_Captura> createState() => _CapturaState();
}

class _CapturaState extends ConsumerState<_Captura> {
  /// actividadId → alumnoId → nota, lo que se ve y se guarda.
  late final Map<String, Map<String, double>> _notas = {
    for (final a in widget.actividades) a.id: {...?widget.plan.calificaciones[a.id]},
  };
  final Map<String, TextEditingController> _campos = {};
  final Map<String, FocusNode> _focos = {};
  final Set<String> _errores = {};
  var _combinada = false;
  var _cambios = false;
  late final ProviderContainer _contenedor;

  PlanParcial get _plan => widget.plan;
  List<Actividad> get _actividades => widget.actividades;
  double get _total => _actividades.fold(0.0, (s, a) => s + a.puntos);

  @override
  void initState() {
    super.initState();
    _contenedor = ProviderScope.containerOf(context, listen: false);
  }

  @override
  void dispose() {
    for (final c in _campos.values) {
      c.dispose();
    }
    for (final f in _focos.values) {
      f.dispose();
    }
    if (_cambios) {
      _contenedor
        ..invalidate(planProvider((_plan.claseId, _plan.parcial.clave)))
        ..invalidate(tableroProvider)
        ..read(syncControllerProvider.notifier).programar();
    }
    super.dispose();
  }

  static String _texto(double? v) => v == null ? '' : formatoPuntos(v);

  /// La combinada sólo se muestra si el alumno tiene todas las notas; si falta alguna, vacía.
  double? _combinadaDe(String alumnoId) {
    var suma = 0.0;
    for (final a in _actividades) {
      final v = _notas[a.id]![alumnoId];
      if (v == null) return null;
      suma += v;
    }
    return suma;
  }

  String _clave(String alumnoId, String? actividadId) => '$alumnoId|${actividadId ?? 'total'}';

  TextEditingController _campo(String alumnoId, String? actividadId) => _campos.putIfAbsent(
        _clave(alumnoId, actividadId),
        () => TextEditingController(
            text: _texto(actividadId == null ? _combinadaDe(alumnoId) : _notas[actividadId]![alumnoId])),
      );

  FocusNode _foco(String alumnoId, String? actividadId) =>
      _focos.putIfAbsent(_clave(alumnoId, actividadId), FocusNode.new);

  /// Al cambiar de modo, los campos del otro modo se rehacen con lo ya capturado.
  void _cambiarModo(bool combinada) {
    for (final a in _plan.alumnos) {
      if (combinada) {
        _campos[_clave(a.id, null)]?.text = _texto(_combinadaDe(a.id));
      } else {
        for (final act in _actividades) {
          _campos[_clave(a.id, act.id)]?.text = _texto(_notas[act.id]![a.id]);
        }
      }
    }
    setState(() {
      _combinada = combinada;
      _errores.clear();
    });
  }

  Future<void> _guardar(AlumnoPlan alumno, Actividad actividad, double? valor) async {
    if (valor == null) {
      _notas[actividad.id]!.remove(alumno.id);
    } else {
      _notas[actividad.id]![alumno.id] = valor;
    }
    _cambios = true;
    await ref.read(planesRepositoryProvider).calificar(actividad.id, alumno.id, valor);
  }

  Future<void> _escribir(AlumnoPlan alumno, Actividad? actividad, String texto) async {
    final limpio = texto.trim();
    final valor = limpio.isEmpty ? null : leerPuntos(limpio);
    final maximo = actividad?.puntos ?? _total;
    final clave = _clave(alumno.id, actividad?.id);
    if (limpio.isNotEmpty && (valor == null || valor < 0 || valor > maximo)) {
      setState(() => _errores.add(clave));
      return;
    }
    setState(() => _errores.remove(clave));

    if (actividad != null) {
      await _guardar(alumno, actividad, valor);
      return;
    }
    // Combinada: se reparte; vacía deja pendientes todas.
    final partes = valor == null ? null : repartirNota(valor, [for (final a in _actividades) a.puntos]);
    for (final (i, a) in _actividades.indexed) {
      await _guardar(alumno, a, partes?[i]);
    }
    setState(() {});
  }

  /// Llena lo vacío con el máximo o con 0 en todas las actividades elegidas.
  Future<void> _llenarVacios(bool maximo) async {
    for (final alumno in _plan.alumnos) {
      for (final a in _actividades) {
        if (_notas[a.id]![alumno.id] != null) continue;
        final valor = maximo ? a.puntos : 0.0;
        _campos[_clave(alumno.id, a.id)]?.text = _texto(valor);
        await _guardar(alumno, a, valor);
      }
      _campos[_clave(alumno.id, null)]?.text = _texto(_combinadaDe(alumno.id));
    }
    setState(() {});
  }

  /// Orden de "Siguiente": por alumno y, dentro de él, por actividad; como se lee la fila.
  void _siguiente(int alumno, int actividad) {
    final porFila = _combinada ? 1 : _actividades.length;
    var a = alumno, c = actividad + 1;
    if (c >= porFila) {
      c = 0;
      a++;
    }
    if (a >= _plan.alumnos.length) {
      FocusScope.of(context).unfocus();
      return;
    }
    _foco(_plan.alumnos[a].id, _combinada ? null : _actividades[c].id).requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final completos = _plan.alumnos.where((al) => _actividades.every((a) => _notas[a.id]![al.id] != null)).length;

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
            Text('Calificar ${_actividades.length} actividades'),
            Text('Valen ${formatoPuntos(_total)} pts en total',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          if (!_plan.cerrado)
            PopupMenuButton<bool>(
              tooltip: 'Llenar los vacíos',
              icon: const Icon(Icons.playlist_add_check),
              onSelected: _llenarVacios,
              itemBuilder: (context) => const [
                PopupMenuItem(value: true, child: Text('Nota completa a los que faltan')),
                PopupMenuItem(value: false, child: Text('0 a los que faltan (no entregaron)')),
              ],
            ),
        ],
      ),
      body: ContenidoCentrado(
        maxAncho: 820,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (i, a) in _actividades.indexed)
                    Chip(
                      avatar: CircleAvatar(
                        backgroundColor: scheme.primary,
                        child: Text('${i + 1}', style: TextStyle(color: scheme.onPrimary, fontSize: 12)),
                      ),
                      label: Text('${a.titulo} · ${formatoPuntos(a.puntos)} pts'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: SegmentedButton<bool>(
                style: SegmentedButton.styleFrom(shape: const RoundedRectangleBorder()),
                segments: const [
                  ButtonSegment(value: false, icon: Icon(Icons.view_column_outlined), label: Text('Nota por actividad')),
                  ButtonSegment(value: true, icon: Icon(Icons.functions), label: Text('Una nota para todas')),
                ],
                selected: {_combinada},
                onSelectionChanged: (s) => _cambiarModo(s.first),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                _combinada
                    ? 'Escribe la nota sobre ${formatoPuntos(_total)}; se reparte según lo que vale cada actividad. '
                        '$completos de ${_plan.alumnos.length} completos.'
                    : '"Siguiente" pasa a la próxima actividad y luego al próximo alumno. '
                        '$completos de ${_plan.alumnos.length} completos.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            if (_plan.cerrado)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('El parcial está cerrado. Reábrelo desde el plan para corregir notas.',
                    style: text.bodySmall?.copyWith(color: scheme.error)),
              ),
            const Divider(height: 2),
            Expanded(
              child: ListView.separated(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.only(bottom: 48),
                itemCount: _plan.alumnos.length,
                separatorBuilder: (_, _) => const Divider(height: 1, thickness: 1),
                itemBuilder: (context, i) => _fila(context, i),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fila(BuildContext context, int i) {
    final alumno = _plan.alumnos[i];
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final ultimoAlumno = i == _plan.alumnos.length - 1;

    Widget campo(Actividad? actividad, int indice, double maximo) {
      final ultimo = ultimoAlumno && (actividad == null || indice == _actividades.length - 1);
      final caja = SizedBox(
        width: actividad == null ? 120 : 84,
        child: TextField(
          controller: _campo(alumno.id, actividad?.id),
          focusNode: _foco(alumno.id, actividad?.id),
          enabled: !_plan.cerrado,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')), LengthLimitingTextInputFormatter(5)],
          textAlign: TextAlign.center,
          textInputAction: ultimo ? TextInputAction.done : TextInputAction.next,
          decoration: InputDecoration(
            isDense: true,
            hintText: '—',
            suffixText: '/${formatoPuntos(maximo)}',
            errorText: _errores.contains(_clave(alumno.id, actividad?.id)) ? '0–${formatoPuntos(maximo)}' : null,
            contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          ),
          onChanged: (v) => _escribir(alumno, actividad, v),
          onSubmitted: (_) => _siguiente(i, indice),
        ),
      );
      if (actividad == null) return caja;
      // El número de la actividad va afuera, como insignia igual a la de arriba: dentro de
      // la caja se confundía con la nota.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: actividad.titulo,
            excludeSemantics: true,
            child: CircleAvatar(
              radius: 11,
              backgroundColor: scheme.primary,
              child: Text('${indice + 1}', style: TextStyle(color: scheme.onPrimary, fontSize: 12)),
            ),
          ),
          const SizedBox(width: 6),
          caja,
        ],
      );
    }

    final nombre = Row(
      children: [
        SizedBox(
          width: 28,
          child: Text('${i + 1}', style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ),
        Expanded(child: Text(alumno.nombre, maxLines: 2, overflow: TextOverflow.ellipsis)),
      ],
    );
    final campos = _combinada
        ? [campo(null, 0, _total)]
        : [for (final (j, a) in _actividades.indexed) campo(a, j, a.puntos)];

    // En pantallas anchas todo en una línea; en el teléfono los campos bajan debajo del nombre.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: LayoutBuilder(
        builder: (context, c) {
          final enLinea = _combinada || c.maxWidth >= 280 + campos.length * 124;
          if (enLinea) {
            return Row(
              children: [
                Expanded(child: nombre),
                const SizedBox(width: 8),
                ...[for (final w in campos) Padding(padding: const EdgeInsets.only(left: 8), child: w)],
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              nombre,
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Wrap(spacing: 16, runSpacing: 8, children: campos),
              ),
            ],
          );
        },
      ),
    );
  }
}
