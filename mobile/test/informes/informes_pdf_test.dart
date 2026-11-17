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
}
