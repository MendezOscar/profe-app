import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/clase.dart';
import '../planes/calculo_parcial.dart';
import '../planes/modelos.dart';

/// PDF del informe de un alumno, del libro de notas y de la lista de asistencia. Se arman en
/// el teléfono, sin internet, con la letra y el logo de la marca. Tamaño carta: el que se
/// imprime en Honduras.
class InformesPdf {
  InformesPdf._();

  static const _azul = PdfColor.fromInt(0xFF2B59C3);
  static const _marino = PdfColor.fromInt(0xFF14213D);
  static const _suave = PdfColor.fromInt(0xFF5B6475);
  static const _rojo = PdfColor.fromInt(0xFFC62828);
  static const _fondo = PdfColor.fromInt(0xFFE8EEFA);

  static pw.ThemeData? _tema;
  static pw.MemoryImage? _logo;

  static Future<void> _cargar() async {
    if (_tema != null) return;
    Future<pw.Font> fuente(String nombre) async => pw.Font.ttf(await rootBundle.load('assets/fonts/$nombre.ttf'));
    _tema = pw.ThemeData.withFont(
      base: await fuente('Archivo-Regular'),
      bold: await fuente('Archivo-ExtraBold'),
      italic: await fuente('Archivo-Regular'),
      boldItalic: await fuente('Archivo-SemiBold'),
    );
    _logo = pw.MemoryImage((await rootBundle.load('assets/brand/logo-azul.png')).buffer.asUint8List());
  }

  static String _puntos(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  static String _fecha(DateTime d) => DateFormat.yMMMMd('es').format(d);

  static pw.Widget _encabezado(String titulo, List<String> lineas) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(titulo, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _marino)),
                    pw.SizedBox(height: 4),
                    for (final l in lineas.where((l) => l.trim().isNotEmpty))
                      pw.Text(l, style: const pw.TextStyle(fontSize: 10, color: _suave)),
                  ],
                ),
              ),
              pw.Image(_logo!, width: 110),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Container(height: 2, color: _marino),
          pw.SizedBox(height: 12),
        ],
      );

  static pw.Widget _pie(pw.Context context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Generado con ProfeApp · ${_fecha(DateTime.now())}', style: const pw.TextStyle(fontSize: 8, color: _suave)),
          pw.Text('Página ${context.pageNumber} de ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: _suave)),
        ],
      );

  static pw.Widget _firma(String docente) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 36),
        child: pw.Row(children: [
          pw.Container(
            width: 220,
            padding: const pw.EdgeInsets.only(top: 4),
            decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _marino))),
            child: pw.Text('$docente\nFirma del docente', style: const pw.TextStyle(fontSize: 9)),
          ),
        ]),
      );

  static pw.Widget _tabla(List<String> encabezados, List<List<String>> filas,
          {Map<int, pw.TableColumnWidth>? anchos, double letra = 9, Set<int> centradas = const {}}) =>
      pw.TableHelper.fromTextArray(
        headers: encabezados,
        data: filas,
        columnWidths: anchos,
        headerStyle: pw.TextStyle(fontSize: letra, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: _marino),
        headerAlignment: pw.Alignment.centerLeft,
        cellAlignment: pw.Alignment.centerLeft,
        cellStyle: pw.TextStyle(fontSize: letra),
        cellAlignments: {for (final i in centradas) i: pw.Alignment.center},
        headerAlignments: {for (final i in centradas) i: pw.Alignment.center},
        oddRowDecoration: const pw.BoxDecoration(color: _fondo),
        border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: .5)),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      );

  /// Informe para el padre o la madre: cómo va el alumno en la asignatura, parcial por
  /// parcial, el detalle del parcial elegido y, si el docente quiere, sus observaciones.
  static Future<Uint8List> informeAlumno({
    required ClaseResumen clase,
    required String docente,
    required AlumnoPlan alumno,
    required List<PlanParcial> planes,
    required PlanParcial detalle,
    List<Observacion> observaciones = const [],
  }) async {
    await _cargar();
    final doc = pw.Document(theme: _tema, title: 'Informe de ${alumno.nombre}', author: docente);
    final calculo = calcularParcial(detalle);
    final nota = calculo.porAlumno[alumno.id]!;

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(40),
      footer: _pie,
      build: (context) => [
        _encabezado('Informe del alumno', [
          '${clase.asignatura} · ${clase.gradoSeccion}${clase.jornada.isEmpty ? '' : ' · ${clase.jornada}'}',
          clase.centro,
          'Docente: $docente',
        ]),
        pw.Text(alumno.nombre, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
        if (alumno.identidad.isNotEmpty) pw.Text('Identidad: ${alumno.identidad}', style: const pw.TextStyle(fontSize: 10, color: _suave)),
        pw.SizedBox(height: 14),
        pw.Text('Resumen por parcial', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        _tabla(
          ['Parcial', 'Nota', 'Faltas', 'Estado'],
          [
            for (final p in planes)
              if (p.actividades.isNotEmpty || p.sesiones.isNotEmpty)
                () {
                  final n = calcularParcial(p).porAlumno[alumno.id];
                  final evaluados = p.actividades
                      .where((a) => p.calificaciones[a.id]?[alumno.id] != null)
                      .fold(0.0, (s, a) => s + a.puntos);
                  return [
                    p.parcial.titulo,
                    n == null ? '—' : (p.cerrado ? '${n.nota}' : '${_puntos(n.obtenidos)} de ${_puntos(evaluados)} pts'),
                    n == null ? '—' : '${n.inasistencias}',
                    p.cerrado ? 'Cerrado' : 'En curso',
                  ];
                }(),
          ],
          anchos: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(2), 2: pw.FlexColumnWidth(1), 3: pw.FlexColumnWidth(1.5)},
          letra: 10,
          centradas: const {1, 2, 3},
        ),
        pw.SizedBox(height: 16),
        pw.Text('${detalle.parcial.titulo}: actividades', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        pw.Text(
          '${_puntos(nota.obtenidos)} puntos obtenidos'
          '${nota.pendientes > 0 ? ' · ${nota.pendientes} ${nota.pendientes == 1 ? 'actividad pendiente' : 'actividades pendientes'}' : ''}'
          ' · ${nota.inasistencias} ${nota.inasistencias == 1 ? 'falta' : 'faltas'}',
          style: const pw.TextStyle(fontSize: 10, color: _suave),
        ),
        pw.SizedBox(height: 6),
        if (detalle.actividades.isEmpty)
          pw.Text('Todavía no hay actividades en este parcial.', style: const pw.TextStyle(fontSize: 10))
        else
          _tabla(
            ['Actividad', 'Rubro', 'Fecha', 'Obtuvo'],
            [
              for (final a in detalle.actividades)
                [
                  a.titulo,
                  detalle.rubros.where((r) => r.id == a.rubroId).firstOrNull?.nombre ?? '',
                  DateFormat('d/M/yyyy').format(a.fecha),
                  switch (detalle.calificaciones[a.id]?[alumno.id]) {
                    final double v => '${_puntos(v)} / ${_puntos(a.puntos)}',
                    null => 'Pendiente / ${_puntos(a.puntos)}',
                  },
                ],
            ],
            anchos: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(2), 2: pw.FlexColumnWidth(1.4), 3: pw.FlexColumnWidth(1.6)},
            letra: 9.5,
            centradas: const {2, 3},
          ),
        if (observaciones.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          pw.Text('Observaciones', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          for (final o in observaciones)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 90,
                    child: pw.Text('${DateFormat('d/M/yyyy').format(o.fecha)}\n${o.tipo.etiqueta}',
                        style: pw.TextStyle(
                            fontSize: 9, color: o.tipo == TipoObservacion.mejora ? _rojo : _azul)),
                  ),
                  pw.Expanded(child: pw.Text(o.texto, style: const pw.TextStyle(fontSize: 10))),
                ],
              ),
            ),
        ],
        _firma(docente),
      ],
    ));
    return doc.save();
  }

  /// Libro de notas del parcial: una fila por alumno con lo obtenido en cada actividad, la
  /// nota y las faltas. Con muchas actividades no caben: se muestra el total por rubro.
  static Future<Uint8List> libroDeNotas({required ClaseResumen clase, required String docente, required PlanParcial plan}) async {
    await _cargar();
    final doc = pw.Document(theme: _tema, title: 'Libro de notas · ${clase.asignatura}', author: docente);
    final calculo = calcularParcial(plan);
    final porActividad = plan.actividades.length <= 12;
    final columnas = porActividad
        ? [for (final a in plan.actividades) '${a.titulo}\n(${_puntos(a.puntos)})']
        : [for (final r in plan.rubros) '${r.nombre}\n(${_puntos(r.puntos)})'];
    String celda(AlumnoPlan al, int i) {
      if (porActividad) {
        final v = plan.calificaciones[plan.actividades[i].id]?[al.id];
        return v == null ? '—' : _puntos(v);
      }
      final rubro = plan.rubros[i];
      return _puntos(plan.actividades
          .where((a) => a.rubroId == rubro.id)
          .fold(0.0, (s, a) => s + (plan.calificaciones[a.id]?[al.id] ?? 0)));
    }

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter.landscape,
      margin: const pw.EdgeInsets.all(28),
      footer: _pie,
      build: (context) => [
        _encabezado('Libro de notas · ${plan.parcial.titulo}', [
          '${clase.asignatura} · ${clase.gradoSeccion}${clase.jornada.isEmpty ? '' : ' · ${clase.jornada}'}',
          clase.centro,
          'Docente: $docente${plan.cerrado ? ' · Parcial cerrado' : ' · Parcial en curso'}',
        ]),
        _tabla(
          ['N.º', 'Alumno', ...columnas, 'Nota', 'Faltas'],
          [
            for (final (i, al) in plan.alumnos.indexed)
              [
                '${i + 1}',
                al.nombre,
                for (var c = 0; c < columnas.length; c++) celda(al, c),
                '${calculo.porAlumno[al.id]!.nota}',
                '${calculo.porAlumno[al.id]!.inasistencias}',
              ],
          ],
          anchos: {
            0: const pw.FixedColumnWidth(22),
            1: const pw.FlexColumnWidth(4),
            for (var c = 0; c < columnas.length; c++) c + 2: const pw.FlexColumnWidth(1),
            columnas.length + 2: const pw.FixedColumnWidth(34),
            columnas.length + 3: const pw.FixedColumnWidth(34),
          },
          letra: columnas.length > 8 ? 7 : 8,
          centradas: {0, for (var c = 2; c < columnas.length + 4; c++) c},
        ),
        if (!porActividad)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6),
            child: pw.Text('Con ${plan.actividades.length} actividades se muestra el total por rubro.',
                style: const pw.TextStyle(fontSize: 8, color: _suave)),
          ),
        _firma(docente),
      ],
    ));
    return doc.save();
  }

  /// Lista de asistencia del parcial: alumnos por fecha. Vacío es presente; A ausente,
  /// T tarde, J justificada. De a 18 fechas por tabla para que quepa en la hoja.
  static Future<Uint8List> listaAsistencia({required ClaseResumen clase, required String docente, required PlanParcial plan}) async {
    await _cargar();
    final doc = pw.Document(theme: _tema, title: 'Asistencia · ${clase.asignatura}', author: docente);
    final sesiones = [...plan.sesiones]..sort((a, b) => a.fecha.compareTo(b.fecha));
    const porTabla = 18;
    String marca(EstadoAsistencia? e) => switch (e) {
          EstadoAsistencia.ausente => 'A',
          EstadoAsistencia.tarde => 'T',
          EstadoAsistencia.justificada => 'J',
          _ => '',
        };
    int ausencias(String alumnoId) =>
        sesiones.where((s) => plan.asistencias[s.id]?[alumnoId] == EstadoAsistencia.ausente).length;

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter.landscape,
      margin: const pw.EdgeInsets.all(28),
      footer: _pie,
      build: (context) => [
        _encabezado('Asistencia · ${plan.parcial.titulo}', [
          '${clase.asignatura} · ${clase.gradoSeccion}${clase.jornada.isEmpty ? '' : ' · ${clase.jornada}'}',
          clase.centro,
          'Docente: $docente · ${sesiones.length} ${sesiones.length == 1 ? 'día' : 'días'} de clase',
        ]),
        if (sesiones.isEmpty)
          pw.Text('Todavía no hay listas en este parcial.')
        else
          for (var inicio = 0; inicio < sesiones.length; inicio += porTabla) ...[
            () {
              final tramo = sesiones.skip(inicio).take(porTabla).toList();
              final ultimo = inicio + porTabla >= sesiones.length;
              return _tabla(
                ['N.º', 'Alumno', for (final s in tramo) DateFormat('d/M').format(s.fecha), if (ultimo) 'Faltas'],
                [
                  for (final (i, al) in plan.alumnos.indexed)
                    [
                      '${i + 1}',
                      al.nombre,
                      for (final s in tramo) marca(plan.asistencias[s.id]?[al.id]),
                      if (ultimo) '${ausencias(al.id)}',
                    ],
                ],
                anchos: {
                  0: const pw.FixedColumnWidth(22),
                  1: const pw.FlexColumnWidth(4),
                  for (var c = 0; c < tramo.length; c++) c + 2: const pw.FixedColumnWidth(26),
                  if (ultimo) tramo.length + 2: const pw.FixedColumnWidth(36),
                },
                letra: 7.5,
                centradas: {0, for (var c = 2; c < tramo.length + 3; c++) c},
              );
            }(),
            pw.SizedBox(height: 12),
          ],
        pw.Text('Vacío: presente · A: ausente · T: tarde · J: justificada. Las faltas cuentan sólo las ausencias.',
            style: const pw.TextStyle(fontSize: 8, color: _suave)),
        _firma(docente),
      ],
    ));
    return doc.save();
  }
}
