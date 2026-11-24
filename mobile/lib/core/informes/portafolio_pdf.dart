part of 'informes_pdf.dart';

/// Lo de una clase que va al portafolio: todos sus parciales, el sexo de los alumnos, el
/// horario y, si se pudo consultar, el programa oficial.
class ClasePortafolio {
  const ClasePortafolio({required this.clase, required this.planes, this.sexos = const {}, this.horario, this.programa});

  final ClaseResumen clase;
  final List<PlanParcial> planes;

  /// alumnoId → 'F' o 'M'.
  final Map<String, String> sexos;
  final Horario? horario;

  /// Lo que devuelve /ia/programa (null sin programa o sin internet).
  final Map<String, dynamic>? programa;

  List<AlumnoPlan> get alumnos => planes.isEmpty ? const [] : planes.first.alumnos;
  String get titulo => '${clase.asignatura} · ${clase.gradoSeccion}';
}

/// Lo que llenó el docente en la pantalla del portafolio.
class DatosPortafolio {
  const DatosPortafolio({
    required this.docente,
    required this.campos,
    required this.media,
    required this.anio,
    this.introduccion = '',
    this.objetivos = '',
  });

  final String docente;

  /// dni, titulos, aniosServicio, telefono, correo, centro, codigoCentro, tipoAdministracion,
  /// director, telefonoDirector, zona, lugar, municipio, departamento.
  final Map<String, dynamic> campos;

  /// Estructura de Media (si no, la de Básica), según el formato departamental 2026.
  final bool media;
  final int anio;
  final String introduccion;
  final String objetivos;

  String campo(String clave) => (campos[clave] as String?)?.trim() ?? '';
}

/// Edad aproximada por el año de inscripción en la identidad (0801-2012-01234 → 2012).
int? edadPorIdentidad(String identidad, int anio) {
  final d = identidad.replaceAll(RegExp(r'\D'), '');
  if (d.length != 13) return null;
  final nacio = int.parse(d.substring(4, 8));
  final edad = anio - nacio;
  return edad >= 3 && edad <= 30 ? edad : null;
}

/// Portafolio del docente con la estructura del formato departamental 2026: lo que la app ya
/// tiene sale lleno (datos, matrícula, horario, contenidos, rúbricas, tareas, notas, nivelación)
/// y cada sección termina con la lista de documentos que el docente agrega a mano.
class PortafolioPdf {
  PortafolioPdf._();

  static const _meses = ['Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre'];

  static Future<Uint8List> generar(DatosPortafolio d, List<ClasePortafolio> clases) async {
    await InformesPdf._cargar();
    final doc = pw.Document(theme: InformesPdf._tema, title: 'Portafolio docente ${d.anio}', author: d.docente);
    final secciones = _secciones(d, clases);

    // Carátula.
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(56),
      build: (_) => pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text('SECRETARÍA DE EDUCACIÓN', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: InformesPdf._suave)),
          pw.SizedBox(height: 4),
          pw.Text(d.campo('centro'), style: const pw.TextStyle(fontSize: 12, color: InformesPdf._suave), textAlign: pw.TextAlign.center),
          pw.SizedBox(height: 90),
          pw.Text('Portafolio Docente', style: pw.TextStyle(fontSize: 34, fontWeight: pw.FontWeight.bold, color: InformesPdf._marino)),
          pw.SizedBox(height: 10),
          pw.Container(width: 120, height: 3, color: InformesPdf._azul),
          pw.SizedBox(height: 30),
          pw.Text(d.docente, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text(d.campo('centro'), style: const pw.TextStyle(fontSize: 13), textAlign: pw.TextAlign.center),
          pw.SizedBox(height: 90),
          pw.Text('${d.anio}', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: InformesPdf._marino)),
        ],
      ),
    ));

    // Portada: I. Datos generales.
    final grados = {for (final c in clases) c.clase.gradoSeccion}.join(', ');
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(40),
      footer: InformesPdf._pie,
      build: (_) => [
        _tituloSeccion('I. Datos Generales'),
        _ficha([
          ('Nombre del docente', d.docente),
          ('DNI', d.campo('dni')),
          ('Títulos obtenidos', d.campo('titulos')),
          ('Años de servicio', d.campo('aniosServicio')),
          ('Teléfono', d.campo('telefono')),
          ('Correo electrónico', d.campo('correo')),
          ('Grado(s) / sección', grados),
          ('Nombre del centro educativo', d.campo('centro')),
          ('Código del centro educativo', d.campo('codigoCentro')),
          ('Tipo de administración', d.campo('tipoAdministracion')),
          ('Nivel educativo', d.media ? 'Educación Media' : 'Educación Básica'),
          ('Director(a) del centro educativo', d.campo('director')),
          ('Teléfono del director(a)', d.campo('telefonoDirector')),
          ('Zona', d.campo('zona')),
          ('Lugar', d.campo('lugar')),
          ('Municipio', d.campo('municipio')),
          ('Departamento', d.campo('departamento')),
        ]),
      ],
    ));

    // Índice.
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(40),
      footer: InformesPdf._pie,
      build: (_) => [
        _tituloSeccion('Índice'),
        for (final s in secciones) ...[
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8, bottom: 2),
            child: pw.Text(s.titulo, style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold, color: InformesPdf._marino)),
          ),
          for (final i in s.items)
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 14, bottom: 1.5),
              child: pw.Row(children: [
                pw.Expanded(child: pw.Text('• ${i.nombre}', style: const pw.TextStyle(fontSize: 10))),
                pw.Text(i.contenido == null ? 'Para agregar' : 'Incluido',
                    style: pw.TextStyle(fontSize: 8.5, color: i.contenido == null ? InformesPdf._suave : InformesPdf._azul)),
              ]),
            ),
        ],
      ],
    ));

    // II a XI.
    for (final s in secciones) {
      final pendientes = s.items.where((i) => i.contenido == null).toList();
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(40),
        footer: InformesPdf._pie,
        build: (_) => [
          _tituloSeccion(s.titulo),
          for (final i in s.items)
            if (i.contenido case final contenido?) ...[
              _subtitulo(i.nombre),
              ...contenido(),
              pw.SizedBox(height: 14),
            ],
          if (pendientes.isNotEmpty) _paraAgregar(pendientes.map((i) => i.nombre).toList()),
        ],
      ));
    }
    return doc.save();
  }

  // ── Estructura ─────────────────────────────────────────────────────────────

  static List<_Seccion> _secciones(DatosPortafolio d, List<ClasePortafolio> clases) {
    final basica = !d.media;
    _Item hecho(String nombre, List<pw.Widget> Function() contenido) => _Item(nombre, contenido);
    _Item manual(String nombre) => _Item(nombre, null);
    _Item texto(String nombre, String t) => t.trim().isEmpty ? manual(nombre) : hecho(nombre, () => _parrafos(t));
    final conProgramas = clases.where((c) => c.programa != null).toList();

    return [
      _Seccion('II. Presentación', [
        texto('Introducción', d.introduccion),
        texto('Objetivos', d.objetivos),
        manual('Hoja de vida (sin diplomas), acuerdos y documentos personales'),
      ]),
      _Seccion('III. Información Estadística', [
        hecho('Matrícula SACE', () => _matricula(clases, d.anio)),
        if (basica) ...[
          hecho('Matrícula por edad y sexo', () => _edadSexo(clases, d.anio)),
          hecho('Partes mensuales', () => _partesMensuales(clases)),
          hecho('Informe estadístico por parcial', () => _estadistico(clases)),
        ],
      ]),
      _Seccion('IV. Organización del Grado', [
        manual('Calendario escolar'),
        clases.any((c) => c.horario?.dias.isNotEmpty ?? false) ? hecho('Horario de clases', () => _horario(clases)) : manual('Horario de clases'),
        manual(d.media ? 'Asociación de Padres de Familia, APF del grado (maestro guía)' : 'Asociación de Padres de Familia, APF del grado'),
        manual('Directiva de grado'),
        if (basica) manual('Comité de merienda escolar'),
        manual('Círculos de estudio'),
        manual('Horario de aseo'),
        manual('Tutores y pupilos'),
      ]),
      _Seccion(d.media ? 'V. Planificación Docente por Asignatura' : 'V. Planificación Docente', [
        if (d.media) ...[manual('Jornalización'), manual('Plan de unidad'), manual('Plan semanal o diario')]
        else ...[manual('Plan Operativo Anual, POA (de grado)'), manual('Planificación docente (según consenso con el director)')],
      ]),
      _Seccion('VI. Contenidos Curriculares', [
        conProgramas.isEmpty
            ? manual('Áreas curriculares (según carga académica)')
            : hecho('Áreas curriculares (según carga académica)', () => _contenidos(conProgramas)),
      ]),
      _Seccion('VII. Trabajos Realizados Dentro y Fuera del Aula', [
        hecho('Asignación y control de tareas', () => _tareas(clases)),
        hecho('Rúbrica de evaluación por asignatura', () => _rubricas(clases)),
        if (basica) manual('Carpeta del alumno (fuera del portafolio)'),
      ]),
      _Seccion('VIII. Control y Evaluación de los Aprendizajes', [
        manual(d.media ? 'Pruebas diagnósticas por asignatura y análisis de resultados' : 'Análisis de los resultados de pruebas diagnósticas del grado'),
        manual('Lista de asistencia diaria o libreta de control de asistencia (fuera del portafolio)'),
        manual(d.media ? 'Informe de excelencia y rendimiento académico (9.° grado, Español y Matemáticas)'
            : 'Informe de excelencia y rendimiento académico (3.°, 6.° y 9.° grado)'),
        manual(d.media ? 'Pruebas escritas (pautas debidamente autorizadas)' : 'Pruebas escritas'),
        hecho('Cuadro control de evaluaciones por parcial', () => _cuadroControl(clases)),
        hecho('Notas SACE', () => _notasSace(clases)),
        manual('Registro de asistencia a reuniones de Redes Educativas'),
      ]),
      _Seccion('IX. Nivelación de los Aprendizajes', [
        hecho('Plan de nivelación y mejora de los aprendizajes', () => _nivelacion(clases)),
      ]),
      _Seccion('X. Participación Comunitaria', [manual('Convocatoria a reuniones'), manual('Lista de asistencia')]),
      _Seccion('XI. Anexos', [manual('Fotografías'), manual('Documentos de gestión de aula')]),
    ];
  }

  // ── Piezas ─────────────────────────────────────────────────────────────────

  static pw.Widget _tituloSeccion(String t) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(children: [
            pw.Expanded(child: pw.Text(t, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: InformesPdf._marino))),
            pw.Image(InformesPdf._logo!, width: 80),
          ]),
          pw.SizedBox(height: 6),
          pw.Container(height: 2, color: InformesPdf._marino),
          pw.SizedBox(height: 12),
        ],
      );

  static pw.Widget _subtitulo(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text(t, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: InformesPdf._azul)),
      );

  static pw.Widget _claseTitulo(ClasePortafolio c) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6, bottom: 4),
        child: pw.Text(c.titulo, style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
      );

  static pw.Widget _ficha(List<(String, String)> filas) => pw.Table(
        columnWidths: const {0: pw.FlexColumnWidth(2), 1: pw.FlexColumnWidth(3)},
        border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: .5)),
        children: [
          for (final (k, v) in filas)
            pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6), child: pw.Text(k, style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold))),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 6),
                child: v.isEmpty
                    ? pw.Container(height: 12, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey500, width: .5))))
                    : pw.Text(v, style: const pw.TextStyle(fontSize: 10.5)),
              ),
            ]),
        ],
      );

  static List<pw.Widget> _parrafos(String t) => [
        for (final p in t.split(RegExp(r'\n\s*\n|\n')).where((p) => p.trim().isNotEmpty))
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Text(p.trim(), style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 2), textAlign: pw.TextAlign.justify),
          ),
      ];

  static pw.Widget _paraAgregar(List<String> items) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 10),
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: InformesPdf._azul, width: 1)),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Agregue a continuación', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: InformesPdf._marino)),
            pw.SizedBox(height: 6),
            for (final i in items)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Row(children: [
                  pw.Container(width: 9, height: 9, decoration: pw.BoxDecoration(border: pw.Border.all(color: InformesPdf._suave, width: .8))),
                  pw.SizedBox(width: 6),
                  pw.Expanded(child: pw.Text(i, style: const pw.TextStyle(fontSize: 10))),
                ]),
              ),
          ],
        ),
      );

  static String _n(num v) => v is double ? InformesPdf._puntos(v) : '$v';

  // ── III. Información estadística ───────────────────────────────────────────

  static List<pw.Widget> _matricula(List<ClasePortafolio> clases, int anio) => [
        for (final c in clases) ...[
          _claseTitulo(c),
          InformesPdf._tabla(
            ['N.°', 'Identidad', 'Nombre', 'Sexo', 'Edad'],
            [
              for (final (i, a) in c.alumnos.indexed)
                ['${i + 1}', a.identidad, a.nombre, c.sexos[a.id] ?? '', '${edadPorIdentidad(a.identidad, anio) ?? ''}'],
            ],
            anchos: const {0: pw.FixedColumnWidth(26), 1: pw.FlexColumnWidth(2.2), 2: pw.FlexColumnWidth(5), 3: pw.FixedColumnWidth(34), 4: pw.FixedColumnWidth(34)},
            centradas: const {0, 3, 4},
          ),
          pw.Text('Matrícula: ${c.alumnos.length} · F: ${c.sexos.values.where((s) => s == 'F').length} · '
              'M: ${c.sexos.values.where((s) => s == 'M').length}',
              style: const pw.TextStyle(fontSize: 9, color: InformesPdf._suave)),
        ],
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Text('Edad aproximada según el año de inscripción de la identidad.', style: const pw.TextStyle(fontSize: 8, color: InformesPdf._suave)),
        ),
      ];

  static List<pw.Widget> _edadSexo(List<ClasePortafolio> clases, int anio) => [
        for (final c in clases) ...[
          _claseTitulo(c),
          () {
            final conteo = <int?, Map<String, int>>{};
            for (final a in c.alumnos) {
              final e = edadPorIdentidad(a.identidad, anio);
              final s = c.sexos[a.id] ?? '?';
              (conteo[e] ??= {})[s] = (conteo[e]![s] ?? 0) + 1;
            }
            final edades = conteo.keys.toList()..sort((a, b) => (a ?? 99).compareTo(b ?? 99));
            final sinSexo = c.alumnos.where((a) => c.sexos[a.id] == null).length;
            return InformesPdf._tabla(
              ['Edad', 'Femenino', 'Masculino', if (sinSexo > 0) 'Sin marcar', 'Total'],
              [
                for (final e in edades)
                  [
                    e == null ? 'Sin dato' : '$e años',
                    '${conteo[e]!['F'] ?? 0}',
                    '${conteo[e]!['M'] ?? 0}',
                    if (sinSexo > 0) '${conteo[e]!['?'] ?? 0}',
                    '${conteo[e]!.values.fold(0, (s, n) => s + n)}',
                  ],
                [
                  'Total',
                  '${c.sexos.values.where((s) => s == 'F').length}',
                  '${c.sexos.values.where((s) => s == 'M').length}',
                  if (sinSexo > 0) '$sinSexo',
                  '${c.alumnos.length}',
                ],
              ],
              centradas: const {1, 2, 3, 4},
            );
          }(),
        ],
      ];

  static List<pw.Widget> _partesMensuales(List<ClasePortafolio> clases) => [
        for (final c in clases) ...[
          _claseTitulo(c),
          () {
            final filas = <List<String>>[];
            for (final (i, mes) in _meses.indexed) {
              var sesiones = 0, ausencias = 0, tardes = 0;
              for (final p in c.planes) {
                for (final s in p.sesiones.where((s) => s.fecha.month == i + 2)) {
                  sesiones++;
                  final estados = p.asistencias[s.id]?.values ?? const <EstadoAsistencia>[];
                  ausencias += estados.where((e) => e == EstadoAsistencia.ausente).length;
                  tardes += estados.where((e) => e == EstadoAsistencia.tarde).length;
                }
              }
              if (sesiones == 0) continue;
              final posibles = sesiones * c.alumnos.length;
              final porcentaje = posibles == 0 ? 100 : (100 * (posibles - ausencias) / posibles).round();
              filas.add([mes, '${c.alumnos.length}', '$sesiones', '$ausencias', '$tardes', '$porcentaje %']);
            }
            return filas.isEmpty
                ? pw.Text('Todavía no hay listas de asistencia.', style: const pw.TextStyle(fontSize: 9.5, color: InformesPdf._suave))
                : InformesPdf._tabla(['Mes', 'Matrícula', 'Días con lista', 'Ausencias', 'Tardanzas', 'Asistencia'], filas,
                    centradas: const {1, 2, 3, 4, 5});
          }(),
        ],
      ];

  static List<pw.Widget> _estadistico(List<ClasePortafolio> clases) => [
        for (final c in clases) ...[
          _claseTitulo(c),
          () {
            final filas = <List<String>>[];
            for (final p in c.planes.where((p) => p.calificaciones.values.any((m) => m.isNotEmpty))) {
              final notas = calcularParcial(p).porAlumno.values.map((n) => n.nota).toList();
              if (notas.isEmpty) continue;
              final aprobados = notas.where((n) => n >= 70).length;
              filas.add([
                p.parcial.titulo + (p.cerrado ? '' : ' (en curso)'),
                '${notas.length}',
                '$aprobados',
                '${notas.length - aprobados}',
                '${(100 * aprobados / notas.length).round()} %',
                (notas.fold(0, (s, n) => s + n) / notas.length).toStringAsFixed(1),
              ]);
            }
            return filas.isEmpty
                ? pw.Text('Todavía no hay notas.', style: const pw.TextStyle(fontSize: 9.5, color: InformesPdf._suave))
                : InformesPdf._tabla(['Parcial', 'Evaluados', 'Aprobados', 'Reprobados', '% aprobación', 'Promedio'], filas,
                    centradas: const {1, 2, 3, 4, 5});
          }(),
        ],
      ];

  // ── IV y VI ────────────────────────────────────────────────────────────────

  static List<pw.Widget> _horario(List<ClasePortafolio> clases) {
    const dias = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
    final filas = [
      for (final c in clases)
        for (final dia in c.horario?.dias ?? const <DiaClase>[]) (dia, c),
    ]..sort((a, b) => a.$1.dia != b.$1.dia ? a.$1.dia.compareTo(b.$1.dia) : a.$1.inicio.compareTo(b.$1.inicio));
    return [
      InformesPdf._tabla(
        ['Día', 'Hora', 'Asignatura', 'Grado y sección', 'Lugar'],
        [
          for (final (dia, c) in filas)
            [dias[dia.dia - 1], '${dia.inicio} a ${dia.fin}', c.clase.asignatura, c.clase.gradoSeccion, c.horario!.lugar],
        ],
        anchos: const {0: pw.FlexColumnWidth(1.4), 1: pw.FlexColumnWidth(1.6), 2: pw.FlexColumnWidth(3), 3: pw.FlexColumnWidth(3), 4: pw.FlexColumnWidth(2)},
      ),
    ];
  }

  static List<pw.Widget> _contenidos(List<ClasePortafolio> clases) => [
        for (final c in clases) ...[
          _claseTitulo(c),
          if ((c.programa!['resultados'] as List).isEmpty)
            pw.Text('Programación oficial de la Secretaría de Educación por mes '
                '(${(c.programa!['meses'] as List).join(', ').toLowerCase()}).',
                style: const pw.TextStyle(fontSize: 9.5))
          else ...[
            pw.Text('Programa oficial de la Secretaría de Educación'
                '${c.programa!['horasSemana'] == null ? '' : ' · ${c.programa!['horasSemana']} horas semanales'}. Resultados de aprendizaje:',
                style: const pw.TextStyle(fontSize: 9.5, color: InformesPdf._suave)),
            pw.SizedBox(height: 3),
            for (final r in (c.programa!['resultados'] as List).cast<Map<String, dynamic>>())
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 8, bottom: 2),
                child: pw.Text('${r['codigo']}. ${r['texto']}', style: const pw.TextStyle(fontSize: 9.5)),
              ),
          ],
        ],
      ];

  // ── VII ────────────────────────────────────────────────────────────────────

  static List<pw.Widget> _tareas(List<ClasePortafolio> clases) => [
        for (final c in clases)
          if (c.planes.any((p) => p.actividades.isNotEmpty)) ...[
            _claseTitulo(c),
            InformesPdf._tabla(
              ['Parcial', 'Actividad', 'Rubro', 'Fecha', 'Valor', 'Calificados'],
              [
                for (final p in c.planes)
                  for (final a in p.actividades)
                    [
                      p.parcial.titulo,
                      a.titulo,
                      p.rubros.where((r) => r.id == a.rubroId).firstOrNull?.nombre ?? '',
                      DateFormat('d/M/yyyy').format(a.fecha),
                      _n(a.puntos),
                      '${p.alumnos.where((al) => p.calificaciones[a.id]?[al.id] != null).length} de ${p.alumnos.length}',
                    ],
              ],
              anchos: const {0: pw.FlexColumnWidth(1.5), 1: pw.FlexColumnWidth(3.5), 2: pw.FlexColumnWidth(2.5), 3: pw.FlexColumnWidth(1.6), 4: pw.FlexColumnWidth(1), 5: pw.FlexColumnWidth(1.5)},
              letra: 8.5,
              centradas: const {3, 4, 5},
            ),
          ],
      ];

  static List<pw.Widget> _rubricas(List<ClasePortafolio> clases) => [
        for (final c in clases)
          if (c.planes.any((p) => p.rubros.isNotEmpty)) ...[
            _claseTitulo(c),
            InformesPdf._tabla(
              ['Parcial', 'Rubro', 'Puntos', 'Actividades'],
              [
                for (final p in c.planes)
                  for (final r in p.rubros)
                    [
                      p.parcial.titulo,
                      r.nombre,
                      _n(r.puntos),
                      p.actividades.where((a) => a.rubroId == r.id).map((a) => '${a.titulo} (${_n(a.puntos)})').join('; '),
                    ],
              ],
              anchos: const {0: pw.FlexColumnWidth(1.4), 1: pw.FlexColumnWidth(2.6), 2: pw.FlexColumnWidth(1), 3: pw.FlexColumnWidth(5)},
              letra: 8.5,
              centradas: const {2},
            ),
          ],
      ];

  // ── VIII y IX ──────────────────────────────────────────────────────────────

  static List<pw.Widget> _cuadroControl(List<ClasePortafolio> clases) => [
        for (final c in clases)
          for (final p in c.planes.where((p) => p.rubros.isNotEmpty && p.actividades.isNotEmpty)) ...[
            _claseTitulo(c),
            pw.Text(p.parcial.titulo + (p.cerrado ? '' : ' (en curso)'), style: const pw.TextStyle(fontSize: 9.5, color: InformesPdf._suave)),
            pw.SizedBox(height: 3),
            () {
              final nota = calcularParcial(p).porAlumno;
              double enRubro(String rubro, String alumno) => p.actividades
                  .where((a) => a.rubroId == rubro)
                  .fold(0.0, (s, a) => s + (p.calificaciones[a.id]?[alumno] ?? 0));
              return InformesPdf._tabla(
                ['Alumno', for (final r in p.rubros) '${r.nombre} (${_n(r.puntos)})', 'Total'],
                [
                  for (final a in p.alumnos)
                    [a.nombre, for (final r in p.rubros) _n(enRubro(r.id, a.id)), '${nota[a.id]?.nota ?? ''}'],
                ],
                anchos: {0: const pw.FlexColumnWidth(4), for (var i = 1; i <= p.rubros.length + 1; i++) i: const pw.FlexColumnWidth(1.3)},
                letra: 7.5,
                centradas: {for (var i = 1; i <= p.rubros.length + 1; i++) i},
              );
            }(),
          ],
      ];

  static List<pw.Widget> _notasSace(List<ClasePortafolio> clases) => [
        for (final c in clases) ...[
          _claseTitulo(c),
          () {
            final parciales = c.planes.where((p) => p.calificaciones.values.any((m) => m.isNotEmpty)).toList();
            final notas = [for (final p in parciales) calcularParcial(p).porAlumno];
            return InformesPdf._tabla(
              ['Alumno', for (final p in parciales) p.parcial.titulo, 'Faltas'],
              [
                for (final a in c.alumnos)
                  [
                    a.nombre,
                    for (final n in notas) '${n[a.id]?.nota ?? ''}',
                    '${notas.fold(0, (s, n) => s + (n[a.id]?.inasistencias ?? 0))}',
                  ],
              ],
              anchos: {0: const pw.FlexColumnWidth(4), for (var i = 1; i <= parciales.length + 1; i++) i: const pw.FlexColumnWidth(1.2)},
              letra: 8.5,
              centradas: {for (var i = 1; i <= parciales.length + 1; i++) i},
            );
          }(),
        ],
      ];

  static List<pw.Widget> _nivelacion(List<ClasePortafolio> clases) {
    final bloques = <pw.Widget>[];
    for (final c in clases) {
      final parciales = c.planes.where((p) => p.calificaciones.values.any((m) => m.isNotEmpty)).toList();
      final notas = [for (final p in parciales) calcularParcial(p).porAlumno];
      final bajos = [
        for (final a in c.alumnos)
          if ([for (final (i, n) in notas.indexed) if ((n[a.id]?.nota ?? 100) < 70) '${parciales[i].parcial.titulo}: ${n[a.id]!.nota}']
              case final List<String> l when l.isNotEmpty)
            [a.nombre, l.join(' · '), ''],
      ];
      if (bajos.isEmpty) continue;
      bloques
        ..add(_claseTitulo(c))
        ..add(InformesPdf._tabla(['Alumno', 'Parciales bajo 70', 'Acción de mejora'], bajos,
            anchos: const {0: pw.FlexColumnWidth(3.5), 1: pw.FlexColumnWidth(3), 2: pw.FlexColumnWidth(3.5)}, letra: 8.5));
    }
    return bloques.isEmpty
        ? [pw.Text('Ningún alumno está bajo 70 en los parciales calificados.', style: const pw.TextStyle(fontSize: 10))]
        : bloques;
  }
}

class _Seccion {
  const _Seccion(this.titulo, this.items);

  final String titulo;
  final List<_Item> items;
}

/// Una parte de la sección: con [contenido] la arma la app; sin él, la agrega el docente.
class _Item {
  const _Item(this.nombre, this.contenido);

  final String nombre;
  final List<pw.Widget> Function()? contenido;
}
