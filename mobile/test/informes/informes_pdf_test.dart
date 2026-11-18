import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:profeapp/core/informes/informes_pdf.dart';
import 'package:profeapp/core/models/clase.dart';
import 'package:profeapp/core/planes/modelos.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('es'));

  final clase = ClaseResumen(
    id: 'c1',
    asignatura: 'Química',
    gradoSeccion: 'Décimo grado sección 1',
    jornada: 'Matutina',
    centro: 'Instituto de prueba',
    alumnos: 2,
    actualizadaEn: DateTime(2026, 3, 1),
  );
  const alumnos = [
    AlumnoPlan(id: 'a1', nombre: 'Adriana Ortiz Peña', identidad: '0801200100001'),
    AlumnoPlan(id: 'a2', nombre: 'Carlos Medina', identidad: '0801200100002'),
  ];
  final plan = PlanParcial(
    claseId: 'c1',
    parcial: const Parcial(clave: 'PARCIAL I', titulo: 'PARCIAL I'),
    rubros: const [Rubro(id: 'r1', nombre: 'Tareas', puntos: 40, orden: 0)],
    actividades: [Actividad(id: 't1', rubroId: 'r1', titulo: 'Tarea 1', fecha: DateTime(2026, 3, 3), puntos: 10)],
    alumnos: alumnos,
    calificaciones: const {'t1': {'a1': 9.5}},
    sesiones: [Sesion(id: 's1', fecha: DateTime(2026, 3, 3))],
    asistencias: const {'s1': {'a2': EstadoAsistencia.ausente}},
  );

  bool esPdf(List<int> bytes) => String.fromCharCodes(bytes.take(5)) == '%PDF-';

  test('El informe del alumno, el libro de notas y la asistencia salen como PDF', () async {
    final informe = await InformesPdf.informeAlumno(
      clase: clase,
      docente: 'Profe Uno',
      alumno: alumnos.first,
      planes: [plan],
      detalle: plan,
      observaciones: [
        Observacion(id: 'o1', alumnoId: 'a1', fecha: DateTime(2026, 3, 4), tipo: TipoObservacion.positiva, texto: 'Participó con entusiasmo'),
      ],
    );
    final libro = await InformesPdf.libroDeNotas(clase: clase, docente: 'Profe Uno', plan: plan);
    final asistencia = await InformesPdf.listaAsistencia(clase: clase, docente: 'Profe Uno', plan: plan);

    expect(esPdf(informe), isTrue);
    expect(esPdf(libro), isTrue);
    expect(esPdf(asistencia), isTrue);
  });

  test('Las boletas de la sección y la constancia de estudio salen como PDF', () async {
    final consolidado = {
      'centro': 'Instituto de prueba',
      'seccion': '7.º grado A',
      'jornada': 'matutina',
      'anio': 2027,
      'notaMinima': 70,
      'asignaturas': [
        {'nombre': 'Matemáticas', 'docente': 'Profe', 'parciales': ['PARCIAL I', 'PARCIAL II']},
        {'nombre': 'Español', 'docente': 'Profe', 'parciales': ['PARCIAL I']},
      ],
      'alumnos': [
        {
          'alumnoId': 'a1',
          'identidad': '0801201400001',
          'nombre': 'Ana López',
          'resultado': 'recuperacion',
          'notas': [
            {'parciales': [60, 70], 'final': 65, 'recuperacion': null, 'inasistencias': 2, 'estado': 'recuperacion'},
            null,
          ],
        },
        {'alumnoId': 'a2', 'identidad': '0801201400002', 'nombre': 'Beto', 'resultado': 'sin_notas', 'notas': [null, null]},
      ],
    };
    final todas = await InformesPdf.boletas(consolidado);
    final una = await InformesPdf.boletas(consolidado, alumnos: {'a1'});
    expect(String.fromCharCodes(todas.take(5)), '%PDF-');
    expect(todas.length, greaterThan(una.length), reason: 'una página por alumno');

    final constancia = await InformesPdf.constanciaEstudio(
        centro: 'Instituto de prueba', alumno: 'Ana López', identidad: '0801201400001', seccion: '7.º grado A', anio: 2027);
    expect(String.fromCharCodes(constancia.take(5)), '%PDF-');
  });
}
