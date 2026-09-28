import 'package:flutter_test/flutter_test.dart';
import 'package:profeapp/core/avisos/avisos.dart';
import 'package:profeapp/core/models/clase.dart';
import 'package:profeapp/core/planes/calculo_parcial.dart';
import 'package:profeapp/core/planes/estadisticas.dart';
import 'package:profeapp/core/planes/modelos.dart';
import 'package:profeapp/core/providers.dart';

const _parcial = Parcial(clave: 'PARCIAL IV', titulo: 'PARCIAL IV', notaClave: 'PARCIAL IV|NOTA TOTAL');
const _ana = AlumnoPlan(id: 'ana', nombre: 'Ana', identidad: '1');
const _luis = AlumnoPlan(id: 'luis', nombre: 'Luis', identidad: '2');
final _hoy = DateTime(2026, 9, 28); // lunes

PlanParcial _plan({
  double examen = 60,
  Map<String, Map<String, double>> calificaciones = const {},
  List<Sesion> sesiones = const [],
  Map<String, Map<String, EstadoAsistencia>> asistencias = const {},
  DateTime? cerradoEn,
}) =>
    PlanParcial(
      claseId: 'c',
      parcial: _parcial,
      rubros: [const Rubro(id: 't', nombre: 'Tareas', puntos: 40, orden: 0), Rubro(id: 'e', nombre: 'Examen', puntos: examen, orden: 1)],
      actividades: [
        Actividad(id: 't1', rubroId: 't', titulo: 'Tarea 1', fecha: DateTime(2026, 9, 1), puntos: 20),
        Actividad(id: 't2', rubroId: 't', titulo: 'Tarea 2', fecha: DateTime(2026, 9, 15), puntos: 20),
        Actividad(id: 'ex', rubroId: 'e', titulo: 'Examen', fecha: DateTime(2026, 10, 2), puntos: 60),
      ],
      alumnos: const [_ana, _luis],
      calificaciones: calificaciones,
      sesiones: sesiones,
      asistencias: asistencias,
      cerradoEn: cerradoEn,
    );

List<Aviso> _avisos(PlanParcial plan, {DateTime? ultimaSync, Map<String, DateTime> exportados = const {},
        Map<String, ({String parcial, DateTime cerradoEn})> cierres = const {}}) =>
    calcularAvisos(
      avances: [
        AvanceClase(
          clase: ClaseResumen(
              id: 'c', asignatura: 'QUÍMICA', gradoSeccion: '', jornada: '', centro: '', alumnos: 2, actualizadaEn: _hoy),
          plan: plan,
          resultado: calcularParcial(plan),
        ),
      ],
      cierres: cierres,
      exportados: exportados,
      ultimaSync: ultimaSync,
      ahora: _hoy.add(const Duration(hours: 10)),
    );

void main() {
  test('En curso la nota es el porcentaje de lo calificado y marca a quien va bajo 70', () {
    final e = calcularEstadisticas(_plan(calificaciones: {
      't1': {'ana': 18, 'luis': 10},
      't2': {'ana': 20, 'luis': 0},
    }));

    expect(e.alumnos.firstWhere((a) => a.alumno.id == 'ana').nota, 95);
    final luis = e.alumnos.firstWhere((a) => a.alumno.id == 'luis');
    expect(luis.nota, 25);
    expect(luis.noEntregadas, 1);
    expect(e.enRiesgo.map((a) => a.alumno.id), ['luis']);
    expect(e.promedio, 60);
    expect(e.distribucion.first.alumnos, 1, reason: 'Luis en <60');
    expect(e.rubros.first.porcentaje, 60, reason: '48 de 80 en tareas');
    expect(e.rubros.last.porcentaje, isNull, reason: 'el examen aún no se califica');
  });

  test('La asistencia cuenta sólo ausencias y detecta muchas faltas', () {
    final sesiones = [for (var i = 0; i < 10; i++) Sesion(id: 's$i', fecha: DateTime(2026, 9, 1 + i))];
    final e = calcularEstadisticas(_plan(sesiones: sesiones, asistencias: {
      for (var i = 0; i < 3; i++) 's$i': {'luis': EstadoAsistencia.ausente, 'ana': EstadoAsistencia.tarde},
    }));

    expect(e.asistencia, 85, reason: '3 ausencias en 20 posibles');
    expect(e.enRiesgo.map((a) => a.alumno.id), ['luis']);
  });

  test('La evolución deja fuera los parciales sin nada calificado', () {
    final cerrado = _plan(cerradoEn: DateTime(2026, 8, 24), calificaciones: {
      't1': {'ana': 20, 'luis': 15},
      't2': {'ana': 20, 'luis': 15},
      'ex': {'ana': 50, 'luis': 40},
    });
    final puntos = evolucion([cerrado, _plan()]);

    expect(puntos, hasLength(1));
    expect(puntos.single.porAlumno, {'ana': 90, 'luis': 70});
  });

  test('Avisa de lo vencido sin calificar, la rúbrica que no suma 100 y la lista de hoy', () {
    final lunesYJueves = [
      for (final d in [7, 10, 14, 17, 21, 24]) Sesion(id: 's$d', fecha: DateTime(2026, 9, d)),
    ];
    final avisos = _avisos(_plan(
      examen: 50,
      sesiones: lunesYJueves,
      calificaciones: {
        't1': {'ana': 20, 'luis': 20},
        't2': {'ana': 20},
      },
    ));
    final tipos = avisos.map((a) => a.tipo).toList();

    expect(avisos.firstWhere((a) => a.tipo == TipoAviso.calificar).titulo, 'Te falta calificar «Tarea 2»');
    expect(tipos, contains(TipoAviso.rubrica));
    expect(tipos, contains(TipoAviso.lista), reason: 'hoy es lunes y suele dar clase los lunes');
    expect(tipos, contains(TipoAviso.cierre), reason: 'la última actividad es en 4 días y falta calificar');
    expect(avisos.where((a) => a.tipo == TipoAviso.calificar), hasLength(1), reason: 'el examen todavía no llega');
  });

  test('Recuerda exportar tras cerrar un parcial y avisa sin respaldo de más de un día', () {
    final cierre = (parcial: 'PARCIAL III', cerradoEn: DateTime(2026, 8, 24));
    final sinExportar = _avisos(_plan(), cierres: {'c': cierre}, ultimaSync: _hoy.subtract(const Duration(days: 3)));

    expect(sinExportar.firstWhere((a) => a.tipo == TipoAviso.exportar).detalle, contains('Parcial III'));
    expect(sinExportar.map((a) => a.tipo), contains(TipoAviso.respaldo));

    final exportado = _avisos(_plan(), cierres: {'c': cierre}, exportados: {'c': DateTime(2026, 8, 25)}, ultimaSync: _hoy);
    expect(exportado.map((a) => a.tipo), isNot(contains(TipoAviso.exportar)));
    expect(exportado.map((a) => a.tipo), isNot(contains(TipoAviso.respaldo)));
  });
}
