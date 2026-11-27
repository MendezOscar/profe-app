import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/informes/compartir.dart';
import '../../../core/informes/informes_pdf.dart';
import '../../../core/providers.dart';
import '../../../theme/tokens.dart';
import '../../../ui/esqueleto.dart';
import '../../../ui/estado_error.dart';
import '../../../ui/estado_vacio.dart';
import '../../ia/asistente_ia.dart' show iconoIa;
import 'centro_ia.dart';

final consolidadoProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, seccion) =>
    ref.watch(apiClientProvider).get('/centro/secciones/$seccion/consolidado', parse: (d) => d as Map<String, dynamic>));

const _resultados = {
  'aprobado': 'Aprobado',
  'recuperacion': 'Recuperación',
  'reprobado': 'Reprobado',
  'en_curso': 'En curso',
  'sin_notas': 'Sin notas',
};

/// Cuadro de la sección con todas las asignaturas, armado con lo que cerró cada docente;
/// boletas en PDF y los cuadros de SACE de la sección en un .zip.
class ConsolidadoPage extends ConsumerWidget {
  const ConsolidadoPage({super.key, required this.seccionId, required this.titulo});

  final String seccionId;
  final String titulo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consolidado = ref.watch(consolidadoProvider(seccionId));
    return Scaffold(
      appBar: AppBar(
        title: Text('Consolidado · $titulo'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () => ref.invalidate(consolidadoProvider(seccionId)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: consolidado.when(
        loading: () => const EsqueletoLista(filas: 8),
        error: (e, _) => EstadoError(error: e, reintentar: () => ref.invalidate(consolidadoProvider(seccionId))),
        data: (c) => _Contenido(c: c, seccionId: seccionId, titulo: titulo),
      ),
    );
  }
}

class _Contenido extends ConsumerWidget {
  const _Contenido({required this.c, required this.seccionId, required this.titulo});

  final Map<String, dynamic> c;
  final String seccionId;
  final String titulo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final asignaturas = (c['asignaturas'] as List).cast<Map<String, dynamic>>();
    final alumnos = (c['alumnos'] as List).cast<Map<String, dynamic>>().where((a) => a['estadoMatricula'] == 'activa').toList();
    final conteo = <String, int>{};
    for (final a in alumnos) {
      conteo[a['resultado'] as String] = (conteo[a['resultado']] ?? 0) + 1;
    }

    Color? colorDe(String? estado) => switch (estado) {
          'aprobada' => scheme.primary,
          'recuperacion' => scheme.tertiary,
          'reprobada' => scheme.error,
          _ => null,
        };

    return ListView(
      padding: const EdgeInsets.all(Espacio.l),
      children: [
        Wrap(
          spacing: Espacio.s,
          runSpacing: Espacio.s,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final r in ['aprobado', 'recuperacion', 'reprobado', 'en_curso'])
              if ((conteo[r] ?? 0) > 0) Chip(label: Text('${_resultados[r]}: ${conteo[r]}')),
            FilledButton.icon(
              onPressed: alumnos.isEmpty
                  ? null
                  : () async {
                      final bytes = await InformesPdf.boletas(c, alumnos: {for (final a in alumnos) a['alumnoId'] as String});
                      if (context.mounted) await compartirPdf(context, bytes, nombreArchivo('Boletas $titulo'));
                    },
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Boletas de la sección'),
            ),
            OutlinedButton.icon(
              onPressed: alumnos.isEmpty
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => ComentariosBoletaPage(seccionId: seccionId, titulo: titulo),
                      )),
              icon: const Icon(iconoIa),
              label: const Text('Comentarios de boleta'),
            ),
            OutlinedButton.icon(
              onPressed: asignaturas.isEmpty ? null : () => _cuadros(context, ref),
              icon: const Icon(Icons.folder_zip_outlined),
              label: const Text('Cuadros de SACE (.zip)'),
            ),
          ],
        ),
        const SizedBox(height: Espacio.s),
        Text(
          'Nota mínima ${c['notaMinima']}. La final es el promedio de los parciales que cerró cada docente '
          '(con nivelación); con final menor, va a recuperación.',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: Espacio.l),
        if (asignaturas.isEmpty)
          const EstadoVacio(
            icono: Icons.table_chart_outlined,
            titulo: 'Sin cuadros de esta sección',
            mensaje: 'Aparecen cuando los docentes del centro importan en ProfeApp los cuadros de SACE de la sección.',
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: Espacio.l,
              headingRowHeight: 64,
              columns: [
                const DataColumn(label: Text('Alumno')),
                for (final a in asignaturas)
                  DataColumn(
                    numeric: true,
                    label: Tooltip(
                      message: '${a['nombre']} · ${a['docente']}',
                      child: SizedBox(
                        width: 90,
                        child: Text('${a['nombre']}', maxLines: 3, overflow: TextOverflow.ellipsis, style: text.labelSmall),
                      ),
                    ),
                  ),
                const DataColumn(label: Text('Conducta')),
                const DataColumn(label: Text('Resultado')),
                const DataColumn(label: Text('')),
              ],
              rows: [
                for (final al in alumnos)
                  DataRow(cells: [
                    DataCell(Text('${al['nombre']}')),
                    for (final n in (al['notas'] as List).cast<Map<String, dynamic>?>())
                      DataCell(
                        n == null
                            ? const Text('—')
                            : Tooltip(
                                message: [
                                  'Parciales: ${(n['parciales'] as List).map((p) => p ?? '·').join(' / ')}',
                                  if (n['recuperacion'] != null) 'Recuperación: ${n['recuperacion']}',
                                  'Inasistencias: ${n['inasistencias']}',
                                ].join('\n'),
                                child: Text(
                                  n['final'] == null
                                      ? '${(n['parciales'] as List).where((p) => p != null).length}/${(n['parciales'] as List).length}'
                                      : '${n['recuperacion'] != null && n['estado'] != 'recuperacion' ? n['recuperacion'] : n['final']}',
                                  style: text.bodyMedium?.copyWith(
                                    color: colorDe(n['estado'] as String?),
                                    fontWeight: n['final'] == null ? null : FontWeight.w700,
                                  ),
                                ),
                              ),
                      ),
                    DataCell(Text(((al['conducta'] as List?) ?? const []).map((c) => c ?? '–').join(' '))),
                    DataCell(Text(_resultados[al['resultado']] ?? '',
                        style: text.labelLarge?.copyWith(
                          color: switch (al['resultado']) {
                            'aprobado' => scheme.primary,
                            'reprobado' => scheme.error,
                            'recuperacion' => scheme.tertiary,
                            _ => scheme.onSurfaceVariant,
                          },
                        ))),
                    DataCell(IconButton(
                      tooltip: 'Boleta de ${al['nombre']}',
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      onPressed: () async {
                        final bytes = await InformesPdf.boletas(c, alumnos: {al['alumnoId'] as String});
                        if (context.mounted) await compartirPdf(context, bytes, nombreArchivo('Boleta ${al['nombre']}'));
                      },
                    )),
                  ]),
              ],
            ),
          ),
        const SizedBox(height: Espacio.m),
        Text('En curso: la cifra «2/4» indica cuántos parciales de esa asignatura ya cerró el docente.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }

  Future<void> _cuadros(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await ref.read(apiClientProvider).getBytes('/centro/secciones/$seccionId/cuadros-sace');
      if (context.mounted) {
        await compartirArchivo(context, bytes, '${nombreArchivo('Cuadros SACE $titulo')}.zip', 'application/zip');
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.isNetworkError ? 'Necesitas internet.' : e.message)));
    }
  }
}
