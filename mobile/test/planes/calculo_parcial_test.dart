import 'package:flutter_test/flutter_test.dart';
import 'package:profeapp/core/planes/calculo_parcial.dart';
import 'package:profeapp/core/planes/modelos.dart';

const _parcial = Parcial(clave: 'PARCIAL I', titulo: 'PARCIAL I', notaClave: 'PARCIAL I|NOTA TOTAL');
const _ana = AlumnoPlan(id: 'ana', nombre: 'Ana', identidad: '1');
const _luis = AlumnoPlan(id: 'luis', nombre: 'Luis', identidad: '2');

PlanParcial _plan({
  List<Rubro> rubros = const [Rubro(id: 't', nombre: 'Tareas', puntos: 40, orden: 0), Rubro(id: 'e', nombre: 'Examen', puntos: 60, orden: 1)],
  List<Actividad>? actividades,
  Map<String, Map<String, double>> calificaciones = const {},
  List<Sesion> sesiones = const [],
  Map<String, Map<String, EstadoAsistencia>> asistencias = const {},
}) =>
    PlanParcial(
      claseId: 'c',
      parcial: _parcial,
      rubros: rubros,
      actividades: actividades ??
          [
            Actividad(id: 't1', rubroId: 't', titulo: 'Tarea 1', fecha: DateTime(2026, 2, 1), puntos: 20),
            Actividad(id: 't2', rubroId: 't', titulo: 'Tarea 2', fecha: DateTime(2026, 2, 8), puntos: 20),
            Actividad(id: 'ex', rubroId: 'e', titulo: 'Examen', fecha: DateTime(2026, 3, 1), puntos: 60),
          ],
      alumnos: const [_ana, _luis],
      calificaciones: calificaciones,
      sesiones: sesiones,
      asistencias: asistencias,
    );

void main() {
  test('La nota es la suma de puntos, redondeada y con tope de 100', () {
    final r = calcularParcial(_plan(calificaciones: {
      't1': {'ana': 18.5, 'luis': 20},
      't2': {'ana': 20, 'luis': 20},
      'ex': {'ana': 30, 'luis': 65},
    }));

    expect(r.porAlumno['ana']!.obtenidos, 68.5);
    expect(r.porAlumno['ana']!.nota, 69, reason: '68.5 redondea hacia arriba');
    expect(r.porAlumno['luis']!.nota, 100, reason: 'tope de 100');
    expect(r.actividadesIncompletas, isEmpty);
  });

  test('Lo pendiente no resta pero se cuenta y se advierte', () {
    final plan = _plan(calificaciones: {
      't1': {'ana': 20, 'luis': 10},
    });
    final r = calcularParcial(plan);

    expect(r.porAlumno['ana']!.nota, 20);
    expect(r.porAlumno['ana']!.pendientes, 2);
    expect(r.actividadesIncompletas.map((a) => a.id), ['t2', 'ex']);
    expect(r.advertencias(plan), contains('Tarea 2: faltan notas.'));
  });

  test('Sólo las ausencias cuentan como inasistencias', () {
    final r = calcularParcial(_plan(
      sesiones: [Sesion(id: 's1', fecha: DateTime(2026, 2, 2)), Sesion(id: 's2', fecha: DateTime(2026, 2, 3))],
      asistencias: {
        's1': {'ana': EstadoAsistencia.ausente, 'luis': EstadoAsistencia.tarde},
        's2': {'ana': EstadoAsistencia.ausente, 'luis': EstadoAsistencia.justificada},
      },
    ));

    expect(r.porAlumno['ana']!.inasistencias, 2);
    expect(r.porAlumno['luis']!.inasistencias, 0);
  });

  test('Advierte cuando el plan no suma 100 o un rubro se pasa', () {
    final plan = _plan(
      rubros: const [Rubro(id: 't', nombre: 'Tareas', puntos: 30, orden: 0), Rubro(id: 'e', nombre: 'Examen', puntos: 60, orden: 1)],
    );
    final avisos = calcularParcial(plan).advertencias(plan);

    expect(avisos, contains('El plan suma 90 puntos, no 100.'));
    expect(avisos, contains('Tareas: las actividades suman 40 y el rubro vale 30.'));
    expect(avisos, contains('No se ha pasado lista en este parcial.'));
  });
}
