import 'dart:async';

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
import '../../theme/tokens.dart';
import '../../ui/esqueleto.dart';
import '../../ui/estado_error.dart';
import '../../ui/estado_vacio.dart';
import '../ia/asistente_ia.dart';

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
      loading: () => const EsqueletoPagina(),
      error: (error, _) => PaginaError(error: error, reintentar: () => ref.invalidate(planProvider((claseId, parcial)))),
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

  /// Modo tanda: el ícono de cada alumno toma las fotos de su trabajo y al final se mandan
  /// todas juntas (cuestan la mitad; la IA responde en unos minutos).
  var _enTanda = false;
  final Map<String, List<Uint8List>> _fotosTanda = {};

  /// Mientras haya una tanda en proceso se pregunta cada 20 segundos si ya terminó.
  Timer? _sondeo;

  PlanParcial get _plan => widget.plan;
  Actividad get _actividad => widget.actividad;
  bool get _soloLectura => _plan.cerrado;

  static String _texto(double? v) => v == null ? '' : formatoPuntos(v);

  @override
  void initState() {
    super.initState();
    _contenedor = ProviderScope.containerOf(context, listen: false);
    _sondeo = Timer.periodic(const Duration(seconds: 20), (_) {
      final tandas = ref.read(tandasIaProvider(_actividad.id)).valueOrNull;
      if (tandas != null && tandas.any((t) => t['estado'] == 'procesando')) ref.invalidate(tandasIaProvider(_actividad.id));
    });
    // Al salir de un campo con un valor fuera de rango se vacía: lo que se ve es lo guardado.
    for (final a in _plan.alumnos) {
      _focus[a.id]!.addListener(() {
        if (!_focus[a.id]!.hasFocus && _errores.containsKey(a.id)) {
          _controllers[a.id]!.clear();
          setState(() => _errores.remove(a.id));
        }
      });
    }
  }

  @override
  void dispose() {
    _sondeo?.cancel();
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
      // Al teclear "15" en una de 10 ya se había guardado el "1": se quita para que no
      // quede una nota que el docente no quiso poner.
      final habia = _notas.remove(alumno.id) != null;
      setState(() => _errores[alumno.id] = '0–${formatoPuntos(_actividad.puntos)}');
      if (habia) {
        _cambios = true;
        await ref.read(planesRepositoryProvider).calificar(_actividad.id, alumno.id, null);
      }
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

  /// Clave o criterios de la actividad para el asistente; se pide la primera vez.
  String? _criteriosIa;

  Future<void> _conFoto(AlumnoPlan alumno) async {
    final nota = await calificarConFotoIa(context, ref, _plan, _actividad,
        criterios: _criteriosIa, alCriterios: (c) => _criteriosIa = c);
    if (nota == null || !mounted) return;
    _controllers[alumno.id]!.text = formatoPuntos(nota);
    await _guardar(alumno, formatoPuntos(nota));
  }

  Future<void> _iniciarTanda() async {
    final clave = await prepararTandaIa(context, ref, criterios: _criteriosIa);
    if (clave == null || !mounted) return;
    _criteriosIa = clave;
    setState(() => _enTanda = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Toca la cámara de cada alumno y toma su trabajo. Al final, «Enviar a la IA».')));
  }

  Future<void> _salirDeTanda() async {
    if (_fotosTanda.isNotEmpty) {
      final salir = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: const RoundedRectangleBorder(),
          title: const Text('¿Salir sin enviar?'),
          content: Text('Se descartan las fotos de ${_fotosTanda.length} '
              '${_fotosTanda.length == 1 ? 'trabajo' : 'trabajos'}.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Seguir en la tanda')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Descartar')),
          ],
        ),
      );
      if (salir != true || !mounted) return;
    }
    setState(() {
      _enTanda = false;
      _fotosTanda.clear();
    });
  }

  Future<void> _fotoTanda(AlumnoPlan alumno) async {
    final fotos = await tomarFotosTrabajo(context, listo: 'Listo, siguiente alumno');
    if (fotos.isEmpty || !mounted) return;
    setState(() => _fotosTanda[alumno.id] = fotos);
  }

  Future<void> _enviarTanda() async {
    final enviados = await enviarTandaIa(context, ref, _plan, _actividad, _criteriosIa ?? '', Map.of(_fotosTanda));
    if (enviados == 0 || !mounted) return;
    setState(() {
      for (final id in _fotosTanda.keys.take(enviados).toList()) {
        _fotosTanda.remove(id);
      }
      if (_fotosTanda.isEmpty) _enTanda = false;
    });
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: const RoundedRectangleBorder(),
        icon: const Icon(iconoIa),
        title: const Text('La IA está calificando'),
        content: Text('Mandaste $enviados ${enviados == 1 ? 'trabajo' : 'trabajos'}. Tarda unos minutos: puedes salir '
            'y volver a esta actividad. Las notas sugeridas aparecen junto a cada alumno para que las revises.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
      ),
    );
  }

  Future<void> _revisarSugerencia(AlumnoPlan alumno, double sugerida, String justificacion) async {
    final nota = await revisarSugerenciaIa(context, _actividad, sugerida, justificacion);
    if (nota == null || !mounted) return;
    _controllers[alumno.id]!.text = formatoPuntos(nota);
    await _guardar(alumno, formatoPuntos(nota));
  }

  /// Pone las notas sugeridas a los que aún no tienen nota. Se puede deshacer.
  Future<void> _usarSugerencias(List<(AlumnoPlan, double)> sugeridas) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: const RoundedRectangleBorder(),
        title: Text('¿Usar las ${sugeridas.length} notas sugeridas?'),
        content: const Text('Se ponen solo a los alumnos que aún no tienen nota. Es una sugerencia: '
            'si dudas de alguna, tócala para ver por qué y cámbiala.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Usar todas')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    for (final (alumno, nota) in sugeridas) {
      _controllers[alumno.id]!.text = formatoPuntos(nota);
      await _guardar(alumno, formatoPuntos(nota));
    }
    messenger.showSnackBar(SnackBar(
      content: Text('${sugeridas.length} notas sugeridas puestas'),
      action: SnackBarAction(
        label: 'Deshacer',
        onPressed: () async {
          for (final (alumno, _) in sugeridas) {
            if (!mounted) return;
            _controllers[alumno.id]!.clear();
            await _guardar(alumno, '');
          }
        },
      ),
    ));
  }

  /// "Todos entregaron completo" o "los que faltan no entregaron": llena sólo lo vacío.
  /// Se puede deshacer: llena de golpe a toda la sección.
  Future<void> _llenarVacios(double valor) async {
    final vacios = _plan.alumnos.where((a) => _notas[a.id] == null).toList();
    if (vacios.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    for (final a in vacios) {
      _controllers[a.id]!.text = _texto(valor);
      await _guardar(a, _texto(valor));
    }
    messenger.showSnackBar(SnackBar(
      content: Text('${formatoPuntos(valor)} puesto a ${vacios.length} ${vacios.length == 1 ? 'alumno' : 'alumnos'}'),
      action: SnackBarAction(
        label: 'Deshacer',
        onPressed: () async {
          for (final a in vacios) {
            if (!mounted) return;
            _controllers[a.id]!.clear();
            await _guardar(a, '');
          }
        },
      ),
    ));
  }

  /// Una nota por equipo que pasa a cada integrante. Después se puede ajustar a alguno en la
  /// lista, como cualquier nota. Se puede deshacer.
  Future<void> _porEquipo() async {
    final equipos = ref.read(equiposProvider(_plan.claseId)).valueOrNull ?? const <Equipo>[];
    final enClase = {for (final a in _plan.alumnos) a.id: a};
    final notas = await showDialog<Map<String, double>>(
      context: context,
      builder: (_) => _NotasPorEquipo(equipos: equipos, maximo: _actividad.puntos),
    );
    if (notas == null || notas.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final antes = <AlumnoPlan, double?>{};
    for (final e in equipos) {
      final valor = notas[e.id];
      if (valor == null) continue;
      for (final m in e.miembros) {
        final alumno = enClase[m];
        if (alumno == null) continue;
        antes[alumno] = _notas[m];
        _controllers[m]!.text = _texto(valor);
        await _guardar(alumno, _texto(valor));
      }
    }
    messenger.showSnackBar(SnackBar(
      content: Text('Nota puesta a ${antes.length} ${antes.length == 1 ? 'alumno' : 'alumnos'} de ${notas.length} '
          '${notas.length == 1 ? 'equipo' : 'equipos'}'),
      action: SnackBarAction(
        label: 'Deshacer',
        onPressed: () async {
          for (final MapEntry(key: alumno, value: valor) in antes.entries) {
            if (!mounted) return;
            _controllers[alumno.id]!.text = _texto(valor);
            await _guardar(alumno, _texto(valor));
          }
        },
      ),
    ));
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

    // Sugerencias de las tandas: la más reciente de cada alumno; se muestran mientras no tenga nota.
    final tandas = ref.watch(tandasIaProvider(_actividad.id)).valueOrNull ?? const [];
    final enProceso = tandas.where((t) => t['estado'] == 'procesando').fold(0, (s, t) => s + (t['trabajos'] as int));
    final sugerencias = <String, Map<String, dynamic>>{
      for (final t in tandas)
        for (final r in (t['resultados'] as List).cast<Map<String, dynamic>>()) r['alumnoId'] as String: r,
    };
    final porRevisar = [
      for (final a in _plan.alumnos)
        if (_notas[a.id] == null)
          if (sugerencias[a.id]?['nota'] case final num n) (a, n.toDouble()),
    ];

    return Scaffold(
      // bottomSheet y no bottomNavigationBar: se acomoda sobre el teclado.
      bottomSheet: const BarraTeclado(),
      floatingActionButton: _enTanda && _fotosTanda.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _enviarTanda,
              icon: const Icon(iconoIa),
              label: Text('Enviar ${_fotosTanda.length} a la IA'),
            )
          : null,
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
            IconButton(
              tooltip: _enTanda ? 'Salir de la tanda' : 'Calificar en tanda con fotos (IA)',
              icon: Icon(_enTanda ? Icons.close : Icons.burst_mode_outlined),
              onPressed: _enTanda ? _salirDeTanda : _iniciarTanda,
            ),
          if (!_soloLectura && (ref.watch(equiposProvider(_plan.claseId)).valueOrNull?.isNotEmpty ?? false))
            IconButton(
              tooltip: 'Calificar por equipo',
              icon: const Icon(Icons.groups_outlined),
              onPressed: _porEquipo,
            ),
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
              padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.m, Espacio.l, Espacio.s),
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
                  const SizedBox(width: Espacio.m),
                  Text('$hechas/${_plan.alumnos.length}', style: text.labelLarge),
                  if (promedio != null) ...[
                    const SizedBox(width: Espacio.m),
                    Text('Prom. ${formatoPuntos(double.parse(promedio.toStringAsFixed(1)))}',
                        style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            if (_plan.alumnos.length > 12)
              Padding(
                padding: const EdgeInsets.fromLTRB(Espacio.l, 0, Espacio.l, Espacio.s),
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
            if (_enTanda)
              _Aviso(
                icono: Icons.burst_mode_outlined,
                texto: 'Tanda: toca la cámara de cada alumno y toma su trabajo. '
                    '${_fotosTanda.length} ${_fotosTanda.length == 1 ? 'listo' : 'listos'}.',
              ),
            if (enProceso > 0)
              _Aviso(
                cargando: true,
                texto: 'La IA está calificando $enProceso ${enProceso == 1 ? 'trabajo' : 'trabajos'}. '
                    'Tarda unos minutos; puedes salir y volver.',
              ),
            if (porRevisar.isNotEmpty && !_soloLectura)
              _Aviso(
                icono: iconoIa,
                texto: 'La IA sugirió ${porRevisar.length} ${porRevisar.length == 1 ? 'nota' : 'notas'}. '
                    'Toca cada una para ver por qué.',
                accion: TextButton(onPressed: () => _usarSugerencias(porRevisar), child: const Text('Usar todas')),
              ),
            if (_soloLectura)
              Padding(
                padding: const EdgeInsets.fromLTRB(Espacio.l, 0, Espacio.l, Espacio.s),
                child: Text('El parcial está cerrado. Reábrelo desde el plan para corregir notas.',
                    style: text.bodySmall?.copyWith(color: scheme.error)),
              ),
            const Divider(height: 2),
            Expanded(
              child: visibles.isEmpty
                  ? EstadoVacio(
                      icono: Icons.search_off,
                      titulo: 'Nadie coincide con «${_buscar.text.trim()}»',
                      mensaje: 'Revisa cómo se escribe o busca por un apellido.',
                      accion: OutlinedButton(
                        onPressed: () => setState(_buscar.clear),
                        child: const Text('Ver todos'),
                      ),
                    )
                  : ListView.builder(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.only(bottom: Espacio.xxxl),
                itemCount: visibles.length,
                itemBuilder: (context, i) {
                  final alumno = visibles[i];
                  final ultimo = i == visibles.length - 1;
                  final numero = _plan.alumnos.indexOf(alumno) + 1;
                  return ListTile(
                    leading: Text('$numero', style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    minLeadingWidth: 24,
                    title: Text(alumno.nombre, maxLines: 2, overflow: TextOverflow.ellipsis),
                    // El aviso va bajo el nombre: dentro de la caja angosta no se leía.
                    subtitle: _errores[alumno.id] != null
                        ? Text('Debe ser de 0 a ${formatoPuntos(_actividad.puntos)}. No se guardó.',
                            style: text.bodySmall?.copyWith(color: scheme.error))
                        : _notas[alumno.id] == null && !_soloLectura
                            ? switch (sugerencias[alumno.id]) {
                                {'nota': final num n, 'justificacion': final String j} => InkWell(
                                    onTap: () => _revisarSugerencia(alumno, n.toDouble(), j),
                                    child: Text('IA sugiere ${formatoPuntos(n.toDouble())} · revisar',
                                        style: text.bodySmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600)),
                                  ),
                                {'justificacion': final String j} => Text('IA: $j',
                                    maxLines: 2, overflow: TextOverflow.ellipsis,
                                    style: text.bodySmall?.copyWith(color: scheme.error)),
                                _ => null,
                              }
                            : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!_soloLectura && _enTanda)
                          IconButton(
                            tooltip: _fotosTanda.containsKey(alumno.id) ? 'Tomar otra vez' : 'Tomar el trabajo',
                            icon: _fotosTanda.containsKey(alumno.id)
                                ? Icon(Icons.check_circle, color: scheme.primary)
                                : const Icon(Icons.photo_camera_outlined),
                            onPressed: () => _fotoTanda(alumno),
                          )
                        else if (!_soloLectura)
                          IconButton(
                            tooltip: 'Calificar con foto (IA)',
                            icon: const Icon(Icons.document_scanner_outlined),
                            onPressed: () => _conFoto(alumno),
                          ),
                        SizedBox(
                      width: 88,
                      child: Semantics(
          label: 'Nota de ${alumno.nombre}',
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
                          // Borde rojo sin texto: el mensaje está en el subtítulo.
                          errorText: _errores[alumno.id] == null ? null : '',
                          errorStyle: const TextStyle(height: 0, fontSize: 0),
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onChanged: (v) => _guardar(alumno, v),
                        onSubmitted: (_) => _siguiente(visibles, i),
                      ),
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
    );
  }
}

/// Una franja informativa sobre la lista (tanda en curso, sugerencias por revisar).
class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto, this.icono, this.cargando = false, this.accion});

  final String texto;
  final IconData? icono;
  final bool cargando;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: Espacio.l, vertical: Espacio.s),
      child: Row(children: [
        if (cargando)
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
        else
          Icon(icono, size: 20, color: scheme.onSecondaryContainer),
        const SizedBox(width: Espacio.m),
        Expanded(child: Text(texto, style: TextStyle(color: scheme.onSecondaryContainer))),
        ?accion,
      ]),
    );
  }
}

/// Un campo por equipo; devuelve las notas escritas (equipo → puntos).
class _NotasPorEquipo extends StatefulWidget {
  const _NotasPorEquipo({required this.equipos, required this.maximo});

  final List<Equipo> equipos;
  final double maximo;

  @override
  State<_NotasPorEquipo> createState() => _NotasPorEquipoState();
}

class _NotasPorEquipoState extends State<_NotasPorEquipo> {
  final _form = GlobalKey<FormState>();
  late final _campos = {for (final e in widget.equipos) e.id: TextEditingController()};

  @override
  void dispose() {
    for (final c in _campos.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: const RoundedRectangleBorder(),
      title: const Text('Calificar por equipo'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _form,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text('La nota pasa a cada integrante. Deja vacío un equipo para no tocarlo.',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: Espacio.m),
              for (final e in widget.equipos)
                Padding(
                  padding: const EdgeInsets.only(bottom: Espacio.s),
                  child: TextFormField(
                    controller: _campos[e.id],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')), LengthLimitingTextInputFormatter(5)],
                    decoration: InputDecoration(
                      labelText: '${e.nombre} (${e.miembros.length})',
                      suffixText: '/${formatoPuntos(widget.maximo)}',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final n = leerPuntos(v);
                      return n == null || n < 0 || n > widget.maximo ? 'De 0 a ${formatoPuntos(widget.maximo)}' : null;
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(context, {
              for (final MapEntry(key: id, value: c) in _campos.entries)
                if (leerPuntos(c.text) case final n?) id: n,
            });
          },
          child: const Text('Poner notas'),
        ),
      ],
    );
  }
}
