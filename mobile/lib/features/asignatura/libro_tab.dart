import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/planes/calculo_parcial.dart';
import '../../core/planes/modelos.dart';
import '../../core/providers.dart';
import '../../ui/estado_vacio.dart';
import '../../ui/shell.dart';
import 'parcial_cerrado.dart';
import 'plan_tab.dart';

/// Nota mínima para aprobar en SACE. Ver docs/formato-sace.md.
const notaAprobacion = 70;

/// Libro de notas del parcial: tabla alumno × actividad en pantallas anchas y lista con
/// desglose en el teléfono. Desde aquí se cierra el parcial.
class LibroTab extends ConsumerWidget {
  const LibroTab({super.key, required this.plan});

  final PlanParcial plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (plan.alumnos.isEmpty) {
      return const EstadoVacio(
        icono: Icons.groups_outlined,
        titulo: 'Sin alumnos',
        mensaje: 'El cuadro de SACE no trae alumnos activos.',
      );
    }
    final resultado = calcularParcial(plan);
    final compacto = Ancho.de(context) == Ancho.compacto;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (plan.cerrado) ParcialCerrado(plan: plan),
        _Encabezado(plan: plan, resultado: resultado),
        const Divider(height: 2),
        Expanded(
          child: compacto
              ? _ListaAlumnos(plan: plan, resultado: resultado)
              : _Tabla(plan: plan, resultado: resultado),
        ),
      ],
    );
  }
}

class _Encabezado extends ConsumerWidget {
  const _Encabezado({required this.plan, required this.resultado});

  final PlanParcial plan;
  final ResultadoParcial resultado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notas = resultado.porAlumno.values.map((n) => n.nota).toList();
    final promedio = notas.isEmpty ? 0 : notas.reduce((a, b) => a + b) / notas.length;
    final aprobados = notas.where((n) => n >= notaAprobacion).length;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 24,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Wrap(
            spacing: 24,
            children: [
              _Cifra(valor: promedio.toStringAsFixed(1), etiqueta: 'Promedio'),
              _Cifra(valor: '$aprobados', etiqueta: 'Aprueban'),
              _Cifra(valor: '${notas.length - aprobados}', etiqueta: 'Bajo $notaAprobacion'),
              _Cifra(valor: formatoPuntos(resultado.asignado), etiqueta: 'Pts evaluados'),
            ],
          ),
          if (!plan.cerrado)
            FilledButton.icon(
              onPressed: () => cerrarParcial(context, ref, plan),
              icon: const Icon(Icons.task_alt),
              label: const Text('Cerrar parcial'),
            )
          else
            OutlinedButton.icon(
              onPressed: () => context.go('/inicio/asignaturas/${plan.claseId}/cuadro'),
              icon: const Icon(Icons.upload_file),
              label: Text('Exportar', style: text.labelLarge),
            ),
        ],
      ),
    );
  }
}

class _Cifra extends StatelessWidget {
  const _Cifra({required this.valor, required this.etiqueta});

  final String valor;
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(valor, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        Text(etiqueta.toUpperCase(), style: text.labelSmall),
      ],
    );
  }
}

/// Nota con color: bajo 70 en rojo, para verlo de un vistazo.
class _Nota extends StatelessWidget {
  const _Nota(this.nota);

  final NotaAlumno nota;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final baja = nota.nota < notaAprobacion;
    return Container(
      width: 48,
      padding: const EdgeInsets.symmetric(vertical: 6),
      color: baja ? scheme.errorContainer : scheme.primaryContainer,
      alignment: Alignment.center,
      child: Text(
        '${nota.nota}',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: baja ? scheme.onErrorContainer : scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _ListaAlumnos extends StatelessWidget {
  const _ListaAlumnos({required this.plan, required this.resultado});

  final PlanParcial plan;
  final ResultadoParcial resultado;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 48),
      itemCount: plan.alumnos.length,
      separatorBuilder: (_, _) => const Divider(height: 1, thickness: 1),
      itemBuilder: (context, i) {
        final alumno = plan.alumnos[i];
        final nota = resultado.porAlumno[alumno.id]!;
        return ListTile(
          leading: Text('${i + 1}', style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
          minLeadingWidth: 24,
          title: Text(alumno.nombre, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text([
            if (nota.pendientes > 0) '${nota.pendientes} pendientes',
            if (nota.inasistencias > 0) '${nota.inasistencias} faltas',
          ].join(' · ')),
          trailing: _Nota(nota),
          onTap: () => showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            isScrollControlled: true,
            shape: const RoundedRectangleBorder(),
            builder: (_) => _Desglose(plan: plan, alumno: alumno, nota: nota),
          ),
        );
      },
    );
  }
}

class _Desglose extends StatelessWidget {
  const _Desglose({required this.plan, required this.alumno, required this.nota});

  final PlanParcial plan;
  final AlumnoPlan alumno;
  final NotaAlumno nota;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Row(
              children: [
                Expanded(child: Text(alumno.nombre, style: text.titleLarge)),
                _Nota(nota),
              ],
            ),
            Text('${formatoPuntos(nota.obtenidos)} pts obtenidos · ${nota.inasistencias} faltas',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            for (final rubro in plan.rubros) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(rubro.nombre.toUpperCase(), style: text.labelSmall),
              ),
              for (final a in plan.actividades.where((a) => a.rubroId == rubro.id))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text(a.titulo)),
                      Text(
                        switch (plan.calificaciones[a.id]?[alumno.id]) {
                          final double v => '${formatoPuntos(v)} / ${formatoPuntos(a.puntos)}',
                          null => 'pendiente / ${formatoPuntos(a.puntos)}',
                        },
                        style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tabla completa: nota y faltas primero (lo que va a SACE), luego cada actividad.
/// Cada celda se edita ahí mismo, como en una hoja de cálculo: Enter baja al siguiente
/// alumno en la misma actividad. La nota se recalcula al salir de la celda.
class _Tabla extends ConsumerStatefulWidget {
  const _Tabla({required this.plan, required this.resultado});

  final PlanParcial plan;
  final ResultadoParcial resultado;

  @override
  ConsumerState<_Tabla> createState() => _TablaState();
}

class _TablaState extends ConsumerState<_Tabla> {
  final Map<String, FocusNode> _focos = {};

  FocusNode _foco(String actividadId, String alumnoId) =>
      _focos.putIfAbsent('$actividadId|$alumnoId', FocusNode.new);

  @override
  void dispose() {
    for (final f in _focos.values) {
      f.dispose();
    }
    _horizontal.dispose();
    super.dispose();
  }

  final _horizontal = ScrollController();

  static const _anchoNumero = 44.0;
  static const _anchoAlumno = 260.0;
  static const _anchoNota = 76.0;
  static const _anchoFaltas = 68.0;
  static const _anchoActividad = 104.0;
  static const _altoFila = 56.0;

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final resultado = widget.resultado;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final ancho = _anchoNumero + _anchoAlumno + _anchoNota + _anchoFaltas + plan.actividades.length * _anchoActividad + 16;
    final cabecera = text.labelMedium?.copyWith(fontWeight: FontWeight.w600);

    Widget celda(double w, Widget child, {Alignment align = Alignment.centerRight}) =>
        SizedBox(width: w, child: Align(alignment: align, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: child)));

    // Virtualizada: sólo se construyen las filas visibles. Con DataTable, una sección de 45
    // alumnos y 40 actividades eran 1,800 campos a la vez y la web se trababa.
    return Scrollbar(
      controller: _horizontal,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _horizontal,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: ancho,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 64,
                child: Row(
                  children: [
                    celda(_anchoNumero, Text('#', style: cabecera), align: Alignment.centerLeft),
                    celda(_anchoAlumno, Text('Alumno', style: cabecera), align: Alignment.centerLeft),
                    celda(_anchoNota, Text('Nota', style: cabecera)),
                    celda(_anchoFaltas, Text('Faltas', style: cabecera)),
                    for (final a in plan.actividades)
                      celda(
                        _anchoActividad,
                        Tooltip(
                          message: a.descripcion ?? a.titulo,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(a.titulo, style: cabecera, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end),
                              Text('${formatoPuntos(a.puntos)} pts',
                                  style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 2),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 48),
                  itemExtent: _altoFila,
                  itemCount: plan.alumnos.length,
                  itemBuilder: (context, i) {
                    final alumno = plan.alumnos[i];
                    final nota = resultado.porAlumno[alumno.id]!;
                    return DecoratedBox(
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outlineVariant))),
                      child: Row(
                        children: [
                          celda(_anchoNumero, Text('${i + 1}'), align: Alignment.centerLeft),
                          celda(_anchoAlumno, Text(alumno.nombre, overflow: TextOverflow.ellipsis), align: Alignment.centerLeft),
                          celda(_anchoNota, _Nota(nota)),
                          celda(_anchoFaltas, Text('${nota.inasistencias}')),
                          for (final a in plan.actividades)
                            celda(
                              _anchoActividad,
                              _CeldaNota(
                                key: ValueKey('${a.id}|${alumno.id}'),
                                plan: plan,
                                actividad: a,
                                alumno: alumno,
                                foco: _foco(a.id, alumno.id),
                                siguiente: i + 1 < plan.alumnos.length ? _foco(a.id, plan.alumnos[i + 1].id) : null,
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

/// Celda editable del libro. Guarda al escribir; al salir refresca nota y tablero.
class _CeldaNota extends ConsumerStatefulWidget {
  const _CeldaNota({
    super.key,
    required this.plan,
    required this.actividad,
    required this.alumno,
    required this.foco,
    this.siguiente,
  });

  final PlanParcial plan;
  final Actividad actividad;
  final AlumnoPlan alumno;
  final FocusNode foco;
  final FocusNode? siguiente;

  @override
  ConsumerState<_CeldaNota> createState() => _CeldaNotaState();
}

class _CeldaNotaState extends ConsumerState<_CeldaNota> {
  late final _texto = TextEditingController(text: _formato(_valor));
  var _error = false;
  var _cambio = false;

  double? get _valor => widget.plan.calificaciones[widget.actividad.id]?[widget.alumno.id];

  static String _formato(double? v) => v == null ? '' : formatoPuntos(v);

  @override
  void initState() {
    super.initState();
    widget.foco.addListener(_alSalir);
  }

  @override
  void didUpdateWidget(covariant _CeldaNota anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.foco != widget.foco) {
      anterior.foco.removeListener(_alSalir);
      widget.foco.addListener(_alSalir);
    }
    // Lo que llegó de otro dispositivo, sin pisar lo que se está escribiendo.
    if (!widget.foco.hasFocus && !_error && _formato(_valor) != _texto.text) _texto.text = _formato(_valor);
  }

  @override
  void dispose() {
    widget.foco.removeListener(_alSalir);
    _texto.dispose();
    super.dispose();
  }

  void _alSalir() {
    if (widget.foco.hasFocus || !_cambio) return;
    _cambio = false;
    planCambiado(ref, widget.plan.claseId, widget.plan.parcial.clave);
  }

  Future<void> _guardar(String texto) async {
    final limpio = texto.trim();
    final valor = limpio.isEmpty ? null : leerPuntos(limpio);
    final invalido = limpio.isNotEmpty && (valor == null || valor < 0 || valor > widget.actividad.puntos);
    setState(() => _error = invalido);
    if (invalido) return;
    _cambio = true;
    await ref.read(planesRepositoryProvider).calificar(widget.actividad.id, widget.alumno.id, valor);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 64,
      child: Tooltip(
        message: _error ? 'Entre 0 y ${formatoPuntos(widget.actividad.puntos)}' : '',
        child: TextField(
          controller: _texto,
          focusNode: widget.foco,
          enabled: !widget.plan.cerrado,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            LengthLimitingTextInputFormatter(5),
          ],
          textAlign: TextAlign.center,
          textInputAction: widget.siguiente == null ? TextInputAction.done : TextInputAction.next,
          decoration: InputDecoration(
            isDense: true,
            hintText: '—',
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: _error ? scheme.error : scheme.outlineVariant, width: _error ? 2 : 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: _error ? scheme.error : scheme.primary, width: 2),
            ),
          ),
          onChanged: _guardar,
          onSubmitted: (_) => widget.siguiente == null ? widget.foco.unfocus() : widget.siguiente!.requestFocus(),
        ),
      ),
    );
  }
}

/// Muestra lo que falta revisar y, si el docente confirma, pasa notas y faltas al cuadro.
Future<void> cerrarParcial(BuildContext context, WidgetRef ref, PlanParcial plan) async {
  final advertencias = calcularParcial(plan).advertencias(plan);
  final text = Theme.of(context).textTheme;
  final confirmar = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: const RoundedRectangleBorder(),
      title: Text('Cerrar ${plan.parcial.titulo}'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'La nota de cada alumno${plan.parcial.inasistenciasClave != null ? ' y sus faltas' : ''} '
                'pasan al cuadro de SACE, listas para exportar. Puedes reabrir el parcial si necesitas corregir.',
              ),
              const SizedBox(height: 16),
              if (advertencias.isEmpty)
                const Row(children: [
                  Icon(Icons.check_circle_outline),
                  SizedBox(width: 8),
                  Expanded(child: Text('Todo en orden.')),
                ])
              else ...[
                Text('ANTES DE CERRAR, REVISA', style: text.labelSmall),
                const SizedBox(height: 8),
                for (final a in advertencias)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber, size: 20, color: Theme.of(context).colorScheme.error),
                        const SizedBox(width: 8),
                        Expanded(child: Text(a)),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Revisar')),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(advertencias.isEmpty ? 'Cerrar parcial' : 'Cerrar igual'),
        ),
      ],
    ),
  );
  if (confirmar != true) return;

  await ref.read(planesRepositoryProvider).cerrar(plan);
  ref.invalidate(claseProvider(plan.claseId));
  planCambiado(ref, plan.claseId, plan.parcial.clave);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('${plan.parcial.titulo} cerrado. Las notas ya están en el cuadro.'),
    action: SnackBarAction(
      label: 'Exportar',
      onPressed: () => context.go('/inicio/asignaturas/${plan.claseId}/cuadro'),
    ),
  ));
}
