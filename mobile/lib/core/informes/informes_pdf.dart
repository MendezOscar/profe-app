import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/clase.dart';
import '../planes/calculo_parcial.dart';
import '../planes/modelos.dart';

part 'portafolio_pdf.dart';

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
  // ── Documentos del centro ────────────────────────────────────────────────

  static const _resultados = {
    'aprobado': 'Aprobado',
    'recuperacion': 'Recuperación',
    'reprobado': 'Reprobado',
    'en_curso': 'En curso',
    'sin_notas': 'Sin notas',
  };

  static const _estadosNota = {
    'aprobada': 'Aprobada',
    'recuperacion': 'Recuperación',
    'reprobada': 'Reprobada',
    'en_curso': 'En curso',
  };

  static pw.Widget _firmas(List<String> cargos) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 48),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [
            for (final c in cargos)
              pw.Container(
                width: 180,
                padding: const pw.EdgeInsets.only(top: 4),
                decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _marino))),
                child: pw.Text(c, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9)),
              ),
          ],
        ),
      );

  /// Boleta de calificaciones de cada alumno (una página por alumno), con lo que cada
  /// docente cerró: parciales, final, recuperación, inasistencias y resultado. [consolidado]
  /// es la respuesta de /centro/secciones/{id}/consolidado; [alumnos] limita a esos ids.
  static Future<Uint8List> boletas(Map<String, dynamic> consolidado, {Set<String>? alumnos}) async {
    await _cargar();
    final asignaturas = (consolidado['asignaturas'] as List).cast<Map<String, dynamic>>();
    final maxParciales = asignaturas.fold(0, (n, a) => (a['parciales'] as List).length > n ? (a['parciales'] as List).length : n);
    final romanos = ['I', 'II', 'III', 'IV', 'V', 'VI'];
    final filas = (consolidado['alumnos'] as List).cast<Map<String, dynamic>>()
        .where((a) => alumnos == null || alumnos.contains(a['alumnoId']));
    final doc = pw.Document(theme: _tema, title: 'Boletas ${consolidado['seccion']}', author: '${consolidado['centro']}');
    String n(Object? v) => v == null ? '' : '$v';

    for (final a in filas) {
      final notas = (a['notas'] as List).cast<Map<String, dynamic>?>();
      final tabla = <List<String>>[];
      var inasistencias = 0;
      for (final (i, asig) in asignaturas.indexed) {
        final nota = notas[i];
        if (nota == null) continue;
        inasistencias += nota['inasistencias'] as int;
        final parciales = (nota['parciales'] as List).cast<int?>();
        tabla.add([
          '${asig['nombre']}',
          for (var p = 0; p < maxParciales; p++) p < parciales.length ? n(parciales[p]) : '',
          n(nota['final']),
          n(nota['recuperacion']),
          _estadosNota[nota['estado']] ?? '',
        ]);
      }
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _encabezado('Boleta de calificaciones', [
              '${consolidado['centro']}',
              '${consolidado['seccion']} · Jornada ${consolidado['jornada']} · Año lectivo ${consolidado['anio']}',
            ]),
            pw.Text('${a['nombre']}', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
            pw.Text('Identidad: ${a['identidad']}', style: const pw.TextStyle(fontSize: 10, color: _suave)),
            pw.SizedBox(height: 14),
            if (tabla.isEmpty)
              pw.Text('Todavía no hay notas cerradas por los docentes.', style: const pw.TextStyle(fontSize: 11))
            else
              _tabla(
                ['Asignatura', for (var p = 0; p < maxParciales; p++) 'P${romanos[p]}', 'Final', 'Recup.', 'Estado'],
                tabla,
                anchos: {0: const pw.FlexColumnWidth(3)},
                letra: 10,
                centradas: {for (var c = 1; c <= maxParciales + 2; c++) c},
              ),
            pw.SizedBox(height: 14),
            pw.Row(children: [
              pw.Text('Resultado: ', style: const pw.TextStyle(fontSize: 11)),
              pw.Text(_resultados[a['resultado']] ?? '',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: a['resultado'] == 'aprobado' ? _azul : a['resultado'] == 'reprobado' ? _rojo : _marino,
                  )),
              pw.Spacer(),
              pw.Text('Inasistencias: $inasistencias', style: const pw.TextStyle(fontSize: 11)),
            ]),
            if ((a['conducta'] as List?)?.any((c) => c != null) ?? false) ...[
              pw.SizedBox(height: 6),
              pw.Text(
                'Conducta: ${[
                  for (final (i, c) in (a['conducta'] as List).indexed)
                    if (i < (maxParciales == 0 ? 4 : maxParciales)) 'P${romanos[i]} ${c ?? '—'}',
                ].join('   ')}',
                style: const pw.TextStyle(fontSize: 11),
              ),
            ],
            if ((a['comentario'] as String?)?.isNotEmpty ?? false) ...[
              pw.SizedBox(height: 10),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(8),
                color: _fondo,
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('OBSERVACIONES', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _suave)),
                  pw.SizedBox(height: 3),
                  pw.Text(a['comentario'] as String, style: const pw.TextStyle(fontSize: 10, lineSpacing: 2)),
                ]),
              ),
            ],
            pw.SizedBox(height: 6),
            pw.Text(
              'Nota mínima para aprobar: ${consolidado['notaMinima']}. La final es el promedio de los parciales; con final '
              'menor a la mínima, el alumno va a recuperación. La nota oficial es la registrada en SACE.',
              style: const pw.TextStyle(fontSize: 8, color: _suave),
            ),
            pw.Spacer(),
            _firmas(['Maestro guía', 'Dirección', 'Firma del padre, madre o encargado']),
            pw.SizedBox(height: 10),
            pw.Text('Generado con ProfeApp · ${_fecha(DateTime.now())}', style: const pw.TextStyle(fontSize: 8, color: _suave)),
          ],
        ),
      ));
    }
    return doc.save();
  }

  /// Constancia de estudio: el alumno está matriculado en el centro este año lectivo.
  static Future<Uint8List> constanciaEstudio({
    required String centro,
    required String alumno,
    required String identidad,
    required String seccion,
    required int anio,
    String? jornada,
  }) async {
    await _cargar();
    final doc = pw.Document(theme: _tema, title: 'Constancia de estudio de $alumno', author: centro);
    final hoy = DateTime.now();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(56),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _encabezado('Constancia de estudio', [centro]),
          pw.SizedBox(height: 24),
          pw.Text('A quien interese:', style: const pw.TextStyle(fontSize: 12)),
          pw.SizedBox(height: 16),
          pw.Text(
            'La dirección de $centro hace constar que $alumno, con número de identidad $identidad, está '
            'matriculado(a) en este centro educativo en $seccion${jornada == null ? '' : ', jornada $jornada'}, '
            'durante el año lectivo $anio.',
            style: const pw.TextStyle(fontSize: 12, lineSpacing: 4),
            textAlign: pw.TextAlign.justify,
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Y para los fines que al interesado convengan, se extiende la presente el ${_fecha(hoy)}.',
            style: const pw.TextStyle(fontSize: 12, lineSpacing: 4),
          ),
          pw.Spacer(),
          _firmas(['Dirección', 'Secretaría']),
          pw.SizedBox(height: 10),
          pw.Text('Sello del centro', style: const pw.TextStyle(fontSize: 9, color: _suave)),
        ],
      ),
    ));
    return doc.save();
  }

  // ── Informe con IA para la dirección ───────────────────────────────────────

  static Future<Uint8List> informeDireccion(Map<String, dynamic> informe, {required String centro}) async {
    await _cargar();
    final doc = pw.Document(theme: _tema, title: 'Informe $centro', author: centro);
    pw.Widget lista(String titulo, String clave) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(height: 14),
            pw.Text(titulo, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _marino)),
            for (final x in (informe[clave] as List).cast<String>())
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 5, left: 8),
                child: pw.Bullet(text: x, style: const pw.TextStyle(fontSize: 11, lineSpacing: 2)),
              ),
          ],
        );
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(48),
      build: (context) => [
        _encabezado('Informe para la dirección', [centro, _fecha(DateTime.now())]),
        pw.SizedBox(height: 12),
        pw.Text('${informe['resumen']}', style: const pw.TextStyle(fontSize: 11, lineSpacing: 3), textAlign: pw.TextAlign.justify),
        lista('Fortalezas', 'fortalezas'),
        lista('Alertas', 'alertas'),
        lista('Recomendaciones', 'recomendaciones'),
        pw.SizedBox(height: 18),
        pw.Text('Redactado con el asistente de IA de ProfeApp a partir de los reportes del centro. Revisado por la dirección.',
            style: const pw.TextStyle(fontSize: 8, color: _suave)),
      ],
    ));
    return doc.save();
  }

  // ── Examen ──────────────────────────────────────────────────────────────────

  /// Examen para imprimir, con espacio para nombre y fecha. Con [conClave], la hoja del docente
  /// con la respuesta de cada pregunta.
  static Future<Uint8List> examen(Map<String, dynamic> e,
      {required String asignatura, required String grado, bool conClave = false}) async {
    await _cargar();
    final doc = pw.Document(theme: _tema, title: '${e['titulo']}');
    final preguntas = (e['preguntas'] as List).cast<Map<String, dynamic>>();
    const letras = 'abcdefgh';
    String pts(Object? v) => '${_puntos((v as num).toDouble())} ${v == 1 ? 'punto' : 'puntos'}';
    final total = preguntas.fold<double>(0, (s, p) => s + (p['puntos'] as num).toDouble());

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.fromLTRB(48, 40, 48, 40),
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox()
          : pw.Text('${e['titulo']}${conClave ? ' · clave' : ''}', style: const pw.TextStyle(fontSize: 8, color: _suave)),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Página ${context.pageNumber} de ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: _suave)),
      ),
      build: (context) => [
        _encabezado(conClave ? 'Clave: ${e['titulo']}' : '${e['titulo']}', [asignatura, grado, 'Valor: ${_puntos(total)} puntos']),
        pw.SizedBox(height: 12),
        if (!conClave) ...[
          pw.Row(children: [
            pw.Expanded(flex: 3, child: pw.Text('Nombre: ________________________________________', style: const pw.TextStyle(fontSize: 11))),
            pw.Expanded(child: pw.Text('Fecha: __________', style: const pw.TextStyle(fontSize: 11))),
          ]),
          pw.SizedBox(height: 6),
          pw.Text('Nota: _______ / ${_puntos(total)}', style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 10),
          pw.Text('${e['instrucciones']}', style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic)),
          pw.SizedBox(height: 6),
        ],
        for (final (i, p) in preguntas.indexed)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 10),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('${i + 1}. ${p['enunciado']} (${pts(p['puntos'])})', style: const pw.TextStyle(fontSize: 11, lineSpacing: 2)),
                if (conClave)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 14, top: 3),
                    child: pw.Text('Respuesta: ${p['respuesta']}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _azul)),
                  )
                else if (p['tipo'] == 'opcion_multiple')
                  for (final (j, o) in (p['opciones'] as List).indexed)
                    pw.Padding(padding: const pw.EdgeInsets.only(left: 14, top: 3), child: pw.Text('${letras[j]}) $o', style: const pw.TextStyle(fontSize: 11)))
                else if (p['tipo'] == 'verdadero_falso')
                  pw.Padding(padding: const pw.EdgeInsets.only(left: 14, top: 3), child: pw.Text('(   ) Verdadero      (   ) Falso', style: const pw.TextStyle(fontSize: 11)))
                else
                  for (var l = 0; l < (p['tipo'] == 'desarrollo' ? 5 : 2); l++)
                    pw.Container(
                      width: double.infinity,
                      height: 18,
                      margin: const pw.EdgeInsets.only(left: 14),
                      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _suave, width: 0.5))),
                    ),
              ],
            ),
          ),
      ],
    ));
    return doc.save();
  }

  // ── Carnet estudiantil ──────────────────────────────────────────────────────

  /// Carnets tamaño tarjeta (85.6 × 54 mm), 8 por hoja carta para recortar. [c] es lo que
  /// devuelve la API: centro, color, lema, logo y alumnos (con foto en base64).
  static Future<Uint8List> carnets(Map<String, dynamic> c) async {
    await _cargar();
    final centro = c['centro'] as String;
    final doc = pw.Document(theme: _tema, title: 'Carnets $centro', author: centro);
    final color = PdfColor.fromHex(c['color'] as String);
    final claro = color.luminance > 0.6;
    final sobreColor = claro ? _marino : PdfColors.white;
    final logo = c['logo'] == null ? null : pw.MemoryImage(base64Decode(c['logo'] as String));
    final lema = c['lema'] as String?;
    final anio = c['anio'];
    final alumnos = (c['alumnos'] as List).cast<Map<String, dynamic>>();
    const ancho = 85.6 * PdfPageFormat.mm;
    const alto = 54 * PdfPageFormat.mm;
    final borde = PdfColor.fromInt(0xFFB0B7C3);

    pw.Widget dato(String etiqueta, String valor) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2.5),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(etiqueta.toUpperCase(), style: const pw.TextStyle(fontSize: 4.5, color: _suave)),
            pw.Text(valor, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: _marino), maxLines: 1),
          ]),
        );

    pw.Widget tarjeta(Map<String, dynamic> a) => pw.Container(
          width: ancho,
          height: alto,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: borde, width: 0.5),
            borderRadius: pw.BorderRadius.circular(3 * PdfPageFormat.mm),
          ),
          child: pw.ClipRRect(
            horizontalRadius: 3 * PdfPageFormat.mm,
            verticalRadius: 3 * PdfPageFormat.mm,
            child: pw.Column(children: [
              pw.Container(
                height: 12 * PdfPageFormat.mm,
                color: color,
                padding: const pw.EdgeInsets.symmetric(horizontal: 6),
                child: pw.Row(children: [
                  if (logo != null) ...[
                    pw.Container(
                      width: 9 * PdfPageFormat.mm,
                      height: 9 * PdfPageFormat.mm,
                      padding: const pw.EdgeInsets.all(1),
                      decoration: pw.BoxDecoration(color: PdfColors.white, borderRadius: pw.BorderRadius.circular(2)),
                      child: pw.Image(logo, fit: pw.BoxFit.contain),
                    ),
                    pw.SizedBox(width: 5),
                  ],
                  pw.Expanded(
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(centro.toUpperCase(),
                            maxLines: 2, style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: sobreColor)),
                        pw.Text('CARNET ESTUDIANTIL $anio', style: pw.TextStyle(fontSize: 5, color: sobreColor, letterSpacing: 0.5)),
                      ],
                    ),
                  ),
                ]),
              ),
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.fromLTRB(6, 5, 6, 3),
                  child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Container(
                      width: 21 * PdfPageFormat.mm,
                      height: 28 * PdfPageFormat.mm,
                      decoration: pw.BoxDecoration(border: pw.Border.all(color: borde, width: 0.5)),
                      child: a['foto'] == null
                          ? pw.Center(child: pw.Text('FOTO', style: const pw.TextStyle(fontSize: 6, color: _suave)))
                          : pw.Image(pw.MemoryImage(base64Decode(a['foto'] as String)), fit: pw.BoxFit.cover),
                    ),
                    pw.SizedBox(width: 6),
                    pw.Expanded(
                      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                        pw.Text('${a['nombre']}',
                            maxLines: 2, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _marino)),
                        dato('Identidad', '${a['identidad']}'),
                        dato('Grado y sección', '${a['seccion']}'),
                        dato('Jornada', '${a['jornada']}'.isEmpty ? '' : '${a['jornada'][0].toUpperCase()}${'${a['jornada']}'.substring(1)}'),
                      ]),
                    ),
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: 'ProfeApp|$centro|${a['identidad']}|${a['nombre']}|$anio',
                      width: 14 * PdfPageFormat.mm,
                      height: 14 * PdfPageFormat.mm,
                      color: _marino,
                    ),
                  ]),
                ),
              ),
              pw.Container(
                height: 4.5 * PdfPageFormat.mm,
                width: double.infinity,
                color: color,
                alignment: pw.Alignment.center,
                child: lema == null
                    ? null
                    : pw.Text(lema, maxLines: 1, style: pw.TextStyle(fontSize: 5, color: sobreColor, fontStyle: pw.FontStyle.italic)),
              ),
            ]),
          ),
        );

    const porHoja = 8;
    for (var i = 0; i < alumnos.length; i += porHoja) {
      final hoja = alumnos.skip(i).take(porHoja).toList();
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(12 * PdfPageFormat.mm),
        build: (context) => pw.Wrap(
          spacing: 8 * PdfPageFormat.mm,
          runSpacing: 6 * PdfPageFormat.mm,
          children: [for (final a in hoja) tarjeta(a)],
        ),
      ));
    }
    return doc.save();
  }
}
