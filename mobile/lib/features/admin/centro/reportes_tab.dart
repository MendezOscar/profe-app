import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/informes/compartir.dart';
import '../../../core/providers.dart';
import '../../../theme/tokens.dart';
import '../../../ui/esqueleto.dart';
import '../../../ui/estado_error.dart';
import '../../../ui/estado_vacio.dart';
import 'comun_centro.dart';
import 'matricula.dart';

final reportesProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
    (ref) => ref.watch(apiClientProvider).get('/centro/reportes', parse: (d) => d as Map<String, dynamic>));

/// CSV con BOM para que Excel respete las tildes, separado por comas.
Uint8List csvBytes(List<List<Object?>> filas) {
  String celda(Object? v) {
    final t = v?.toString() ?? '';
    return t.contains(RegExp('[",\n]')) ? '"${t.replaceAll('"', '""')}"' : t;
  }

  return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(filas.map((f) => f.map(celda).join(',')).join('\r\n'))]);
}

/// Matrícula y movimientos, rendimiento por asignatura, alumnos en riesgo y asistencia.
class ReportesTab extends ConsumerWidget {
  const ReportesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportes = ref.watch(reportesProvider);
    return reportes.when(
      loading: () => const EsqueletoLista(filas: 6, conTarjeta: true),
      error: (e, _) => EstadoError(error: e, reintentar: () => ref.invalidate(reportesProvider)),
      data: (r) => RefreshIndicator(
        onRefresh: () => ref.refresh(reportesProvider.future),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.xxxl),
              children: r['anio'] == null
                  ? const [
                      EstadoVacio(
                        icono: Icons.insights_outlined,
                        titulo: 'Sin año lectivo',
                        mensaje: 'Los reportes aparecen cuando hay un año lectivo actual con secciones y alumnos.',
                      ),
                    ]
                  : [
                      EncabezadoPestana(
                        titulo: 'Reportes ${r['anio']}',
                        ayuda: 'Con lo registrado hasta hoy: matrícula del centro, notas que cerraron los docentes y la lista del día.',
                      ),
                      _Matricula(r['matricula'] as Map<String, dynamic>),
                      const SizedBox(height: Espacio.xl),
                      _Riesgo((r['riesgo'] as List).cast<Map<String, dynamic>>()),
                      const SizedBox(height: Espacio.xl),
                      _Rendimiento((r['rendimiento'] as List).cast<Map<String, dynamic>>()),
                      const SizedBox(height: Espacio.xl),
                      _Asistencia((r['asistencia'] as List).cast<Map<String, dynamic>>()),
                    ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto, {this.accion});

  final String texto;
  final Widget? accion;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Espacio.s),
        child: Row(
          children: [
            Expanded(child: Text(texto.toUpperCase(), style: Theme.of(context).textTheme.labelSmall)),
            ?accion,
          ],
        ),
      );
}

class _Dato extends StatelessWidget {
  const _Dato(this.etiqueta, this.valor, {this.alerta = false});

  final String etiqueta;
  final String valor;
  final bool alerta;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(etiqueta.toUpperCase(), style: text.labelSmall),
        Text(valor, style: text.titleLarge?.copyWith(color: alerta ? Theme.of(context).colorScheme.error : null)),
      ],
    );
  }
}

class _Matricula extends StatelessWidget {
  const _Matricula(this.m);

  final Map<String, dynamic> m;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final secciones = (m['porSeccion'] as List).cast<Map<String, dynamic>>();
    final edades = (m['porEdad'] as List).cast<Map<String, dynamic>>();
    final total = (m['activos'] as int) + (m['retirados'] as int) + (m['trasladados'] as int);
    final desercion = total == 0 ? 0.0 : 100 * (m['retirados'] as int) / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Titulo(
          'Matrícula',
          accion: TextButton.icon(
            onPressed: () => compartirArchivo(
              context,
              csvBytes([
                ['Sección', 'Jornada', 'Activos', 'Cupo', 'Femenino', 'Masculino', 'Sin dato de sexo', 'Retirados', 'Trasladados'],
                for (final s in secciones)
                  [s['seccion'], s['jornada'], s['activos'], s['cupo'], s['femenino'], s['masculino'], s['sinSexo'], s['retirados'], s['trasladados']],
              ]),
              'Matricula por seccion.csv',
              'text/csv',
            ),
            icon: const Icon(Icons.download_outlined),
            label: const Text('CSV'),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(Espacio.l),
            child: Wrap(
              spacing: 32,
              runSpacing: 16,
              children: [
                _Dato('Activos', '${m['activos']}'),
                _Dato('Nuevo ingreso', '${m['nuevos']}'),
                _Dato('Reingreso', '${m['reingresos']}'),
                _Dato('Traslado entrante', '${m['trasladosEntrantes']}'),
                _Dato('Retirados', '${m['retirados']}', alerta: (m['retirados'] as int) > 0),
                _Dato('Trasladados', '${m['trasladados']}'),
                _Dato('Deserción', '${desercion.toStringAsFixed(1)} %', alerta: desercion > 0),
              ],
            ),
          ),
        ),
        const SizedBox(height: Espacio.s),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Sección')),
              DataColumn(label: Text('Activos'), numeric: true),
              DataColumn(label: Text('F'), numeric: true),
              DataColumn(label: Text('M'), numeric: true),
              DataColumn(label: Text('Sin dato'), numeric: true),
              DataColumn(label: Text('Retirados'), numeric: true),
              DataColumn(label: Text('Trasladados'), numeric: true),
            ],
            rows: [
              for (final s in secciones)
                DataRow(cells: [
                  DataCell(Text('${s['seccion']} · ${jornadas[s['jornada']]}')),
                  DataCell(Text('${s['activos']}${s['cupo'] == null ? '' : ' / ${s['cupo']}'}',
                      style: s['cupo'] != null && (s['activos'] as int) > (s['cupo'] as int)
                          ? TextStyle(color: Theme.of(context).colorScheme.error)
                          : null)),
                  DataCell(Text('${s['femenino']}')),
                  DataCell(Text('${s['masculino']}')),
                  DataCell(Text('${s['sinSexo']}')),
                  DataCell(Text('${s['retirados']}')),
                  DataCell(Text('${s['trasladados']}')),
                ]),
            ],
          ),
        ),
        if (edades.isNotEmpty) ...[
          const SizedBox(height: Espacio.s),
          Wrap(
            spacing: Espacio.s,
            runSpacing: Espacio.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Por edad:', style: text.labelLarge),
              for (final e in edades)
                Chip(label: Text('${e['edad'] == null ? 'Sin fecha de nacimiento' : '${e['edad']} años'}: ${e['alumnos']}')),
            ],
          ),
        ],
        if ((m['activos'] as int) > 0 && secciones.every((s) => s['sinSexo'] == s['activos']))
          Padding(
            padding: const EdgeInsets.only(top: Espacio.xs),
            child: Text('El sexo y la edad salen de la ficha de cada alumno (el archivo de SACE no los trae).',
                style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
      ],
    );
  }
}

class _Riesgo extends StatelessWidget {
  const _Riesgo(this.lista);

  final List<Map<String, dynamic>> lista;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Titulo(
          'Alumnos en riesgo (${lista.length})',
          accion: lista.isEmpty
              ? null
              : TextButton.icon(
                  onPressed: () => compartirArchivo(
                    context,
                    csvBytes([
                      ['Alumno', 'Sección', 'Motivos'],
                      for (final r in lista) [r['nombre'], r['seccion'], (r['motivos'] as List).join('; ')],
                    ]),
                    'Alumnos en riesgo.csv',
                    'text/csv',
                  ),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('CSV'),
                ),
        ),
        Text('Con nota por debajo de la mínima en alguna asignatura, o con al menos 3 ausencias y el 10 % de los días.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: Espacio.s),
        if (lista.isEmpty) Text('Ningún alumno en riesgo con lo registrado hasta hoy.', style: text.bodyMedium),
        for (final r in lista)
          Card(
            margin: const EdgeInsets.only(bottom: Espacio.xs),
            child: ListTile(
              leading: Icon(Icons.warning_amber_rounded, color: scheme.error),
              title: Text('${r['nombre']}'),
              subtitle: Text('${r['seccion']} · ${(r['motivos'] as List).join(' · ')}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => abrirFicha(context, r['alumnoId'] as String),
            ),
          ),
      ],
    );
  }
}

class _Rendimiento extends StatelessWidget {
  const _Rendimiento(this.secciones);

  final List<Map<String, dynamic>> secciones;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Titulo('Rendimiento por asignatura'),
        if (secciones.isEmpty)
          Text('Aparece cuando los docentes cierran parciales en sus cuadros de SACE.', style: text.bodyMedium),
        for (final s in secciones)
          Card(
            margin: const EdgeInsets.only(bottom: Espacio.s),
            child: ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text('${s['seccion']}', style: text.titleSmall),
              childrenPadding: const EdgeInsets.fromLTRB(Espacio.l, 0, Espacio.l, Espacio.m),
              children: [
                for (final a in (s['asignaturas'] as List).cast<Map<String, dynamic>>())
                  Padding(
                    padding: const EdgeInsets.only(bottom: Espacio.s),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${a['asignatura']}', style: text.bodyMedium),
                              Text('${a['docente']}', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 150,
                          child: (a['evaluados'] as int) == 0
                              ? Text('Sin notas cerradas', style: text.bodySmall)
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${(100 * (a['aprobados'] as int) / (a['evaluados'] as int)).round()} % aprueba',
                                      style: text.labelLarge?.copyWith(
                                        color: (a['aprobados'] as int) * 10 >= (a['evaluados'] as int) * 7 ? scheme.primary : scheme.error,
                                      ),
                                    ),
                                    Text('Promedio ${a['promedio']} · ${a['evaluados']} alumnos', style: text.bodySmall),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Asistencia extends StatelessWidget {
  const _Asistencia(this.secciones);

  final List<Map<String, dynamic>> secciones;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Titulo('Asistencia (lista del día)'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Sección')),
              DataColumn(label: Text('Días con lista'), numeric: true),
              DataColumn(label: Text('Asistencia'), numeric: true),
              DataColumn(label: Text('Ausencias'), numeric: true),
              DataColumn(label: Text('Tardes'), numeric: true),
              DataColumn(label: Text('Justificadas'), numeric: true),
            ],
            rows: [
              for (final s in secciones)
                DataRow(cells: [
                  DataCell(Text('${s['seccion']}')),
                  DataCell(Text('${s['dias']}')),
                  DataCell(Text(s['porcentaje'] == null ? '—' : '${s['porcentaje']} %',
                      style: s['porcentaje'] != null && (s['porcentaje'] as num) < 90 ? TextStyle(color: scheme.error) : null)),
                  DataCell(Text('${s['ausencias']}')),
                  DataCell(Text('${s['tardes']}')),
                  DataCell(Text('${s['justificadas']}')),
                ]),
            ],
          ),
        ),
      ],
    );
  }
}
