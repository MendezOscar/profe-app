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
/// Tocar una celda permite corregir esa nota ahí mismo.
class _Tabla extends ConsumerWidget {
  const _Tabla({required this.plan, required this.resultado});

  final PlanParcial plan;
  final ResultadoParcial resultado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 48),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 64,
            columnSpacing: 20,
            headingTextStyle: text.labelMedium?.copyWith(fontWeight: FontWeight.w600),
            columns: [
              const DataColumn(label: Text('#')),
              const DataColumn(label: Text('Alumno')),
              const DataColumn(label: Text('Nota'), numeric: true),
              const DataColumn(label: Text('Faltas'), numeric: true),
              for (final a in plan.actividades)
                DataColumn(
                  numeric: true,
                  tooltip: a.descripcion ?? a.titulo,
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(a.titulo, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end),
                        Text('${formatoPuntos(a.puntos)} pts',
                            style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
            ],
            rows: [
              for (final (i, alumno) in plan.alumnos.indexed)
                DataRow(cells: [
                  DataCell(Text('${i + 1}')),
                  DataCell(ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Text(alumno.nombre, overflow: TextOverflow.ellipsis),
                  )),
                  DataCell(_Nota(resultado.porAlumno[alumno.id]!)),
                  DataCell(Text('${resultado.porAlumno[alumno.id]!.inasistencias}')),
                  for (final a in plan.actividades)
                    DataCell(
                      Text(
                        switch (plan.calificaciones[a.id]?[alumno.id]) {
                          final double v => formatoPuntos(v),
                          null => '—',
                        },
                        style: TextStyle(
                            color: plan.calificaciones[a.id]?[alumno.id] == null ? scheme.onSurfaceVariant : null),
                      ),
                      onTap: plan.cerrado ? null : () => _editarCelda(context, ref, alumno, a),
                    ),
                ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editarCelda(BuildContext context, WidgetRef ref, AlumnoPlan alumno, Actividad actividad) async {
    final actual = plan.calificaciones[actividad.id]?[alumno.id];
    final campo = TextEditingController(text: actual == null ? '' : formatoPuntos(actual));
    final form = GlobalKey<FormState>();
    final guardar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: const RoundedRectangleBorder(),
        title: Text(actividad.titulo),
        content: Form(
          key: form,
          child: TextFormField(
            controller: campo,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(
              labelText: alumno.nombre,
              suffixText: '/ ${formatoPuntos(actividad.puntos)}',
              helperText: 'Vacío = pendiente',
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              final n = leerPuntos(v);
              return n == null || n < 0 || n > actividad.puntos ? '0–${formatoPuntos(actividad.puntos)}' : null;
            },
            onFieldSubmitted: (_) {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (guardar != true) return;
    final texto = campo.text.trim();
    await ref.read(planesRepositoryProvider).calificar(actividad.id, alumno.id, texto.isEmpty ? null : leerPuntos(texto));
    planCambiado(ref, plan.claseId, plan.parcial.clave);
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
