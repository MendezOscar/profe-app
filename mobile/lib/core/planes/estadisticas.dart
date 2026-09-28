import 'calculo_parcial.dart';
import 'modelos.dart';

/// Nota mínima para aprobar un parcial en Honduras.
const notaMinima = 70;

/// Cómo va un alumno en un parcial. Con el parcial en curso no se compara contra 100 sino
/// contra lo que ya se calificó: 22 de 30 calificados es 73 %, no 22.
class RendimientoAlumno {
  const RendimientoAlumno({
    required this.alumno,
    required this.obtenidos,
    required this.calificados,
    required this.nota,
    required this.inasistencias,
    required this.noEntregadas,
  });

  final AlumnoPlan alumno;
  final double obtenidos;

  /// Puntos de las actividades que ya tienen nota para este alumno.
  final double calificados;

  /// Parcial cerrado: la nota que va a SACE. En curso: el porcentaje de lo calificado.
  final int? nota;
  final int inasistencias;

  /// Actividades con 0 (no entregó).
  final int noEntregadas;

  bool get enRiesgo => nota != null && nota! < notaMinima;
}

class RendimientoRubro {
  const RendimientoRubro({required this.rubro, required this.porcentaje});

  final Rubro rubro;

  /// De 0 a 100; null si todavía no hay nada calificado en el rubro.
  final double? porcentaje;
}

class EntregasActividad {
  const EntregasActividad({required this.actividad, required this.noEntregadas, required this.sinNota});

  final Actividad actividad;
  final int noEntregadas;
  final int sinNota;
}

class Estadisticas {
  Estadisticas({
    required this.alumnos,
    required this.rubros,
    required this.entregas,
    required this.sesiones,
    required this.asistencia,
    required this.diasConMasFaltas,
  });

  final List<RendimientoAlumno> alumnos;
  final List<RendimientoRubro> rubros;
  final List<EntregasActividad> entregas;
  final int sesiones;

  /// Porcentaje de presencia del grupo (tarde y justificada cuentan como presentes); null sin listas.
  final double? asistencia;
  final List<({DateTime fecha, int ausentes})> diasConMasFaltas;

  // Se calculan una vez: el tablero y los avisos las leen varias veces por asignatura.
  late final List<RendimientoAlumno> conNota = [for (final a in alumnos) if (a.nota != null) a];

  late final double? promedio = conNota.isEmpty ? null : conNota.fold<int>(0, (s, a) => s + a.nota!) / conNota.length;
  int get aprobados => conNota.where((a) => !a.enRiesgo).length;
  int get reprobados => conNota.where((a) => a.enRiesgo).length;

  /// Alumnos bajo la nota mínima o con muchas faltas, los más urgentes primero.
  late final List<RendimientoAlumno> enRiesgo = [for (final a in alumnos) if (a.enRiesgo || muchasFaltas(a)) a]
    ..sort((a, b) => (a.nota ?? 100).compareTo(b.nota ?? 100));

  /// Tres faltas o más y al menos el 15 % de las clases del parcial.
  bool muchasFaltas(RendimientoAlumno a) => a.inasistencias >= 3 && a.inasistencias >= sesiones * 0.15;

  /// Cuántos alumnos caen en cada tramo: <60, 60–69, 70–79, 80–89, 90–100.
  List<({String etiqueta, int alumnos})> get distribucion {
    const tramos = [('<60', 0, 59), ('60–69', 60, 69), ('70–79', 70, 79), ('80–89', 80, 89), ('90–100', 90, 100)];
    return [
      for (final (etiqueta, desde, hasta) in tramos)
        (etiqueta: etiqueta, alumnos: conNota.where((a) => a.nota! >= desde && a.nota! <= hasta).length),
    ];
  }
}

Estadisticas calcularEstadisticas(PlanParcial plan) {
  final resultado = calcularParcial(plan);

  final alumnos = [
    for (final alumno in plan.alumnos)
      () {
        var calificados = 0.0;
        var obtenidos = 0.0;
        var ceros = 0;
        for (final a in plan.actividades) {
          final v = plan.calificaciones[a.id]?[alumno.id];
          if (v == null) continue;
          calificados += a.puntos;
          obtenidos += v.clamp(0, a.puntos).toDouble();
          if (v == 0) ceros++;
        }
        final nota = plan.cerrado
            ? resultado.porAlumno[alumno.id]!.nota
            : calificados == 0
                ? null
                : (obtenidos / calificados * 100).round();
        return RendimientoAlumno(
          alumno: alumno,
          obtenidos: obtenidos,
          calificados: calificados,
          nota: nota,
          inasistencias: resultado.porAlumno[alumno.id]!.inasistencias,
          noEntregadas: ceros,
        );
      }(),
  ];

  final rubros = [
    for (final r in plan.rubros)
      () {
        var posibles = 0.0;
        var logrados = 0.0;
        for (final a in plan.actividades.where((a) => a.rubroId == r.id)) {
          for (final v in (plan.calificaciones[a.id] ?? const <String, double>{}).values) {
            posibles += a.puntos;
            logrados += v.clamp(0, a.puntos).toDouble();
          }
        }
        return RendimientoRubro(rubro: r, porcentaje: posibles == 0 ? null : logrados / posibles * 100);
      }(),
  ];

  final entregas = [
    for (final a in plan.actividades)
      EntregasActividad(
        actividad: a,
        noEntregadas: plan.alumnos.where((al) => plan.calificaciones[a.id]?[al.id] == 0).length,
        sinNota: plan.alumnos.where((al) => plan.calificaciones[a.id]?[al.id] == null).length,
      ),
  ];

  final faltasPorDia = [
    for (final s in plan.sesiones)
      (
        fecha: s.fecha,
        ausentes: (plan.asistencias[s.id] ?? const {}).values.where((e) => e == EstadoAsistencia.ausente).length,
      ),
  ]..sort((a, b) => b.ausentes.compareTo(a.ausentes));
  final ausencias = faltasPorDia.fold(0, (s, d) => s + d.ausentes);
  final posibles = plan.sesiones.length * plan.alumnos.length;

  return Estadisticas(
    alumnos: alumnos,
    rubros: rubros,
    entregas: entregas,
    sesiones: plan.sesiones.length,
    asistencia: posibles == 0 ? null : (1 - ausencias / posibles) * 100,
    diasConMasFaltas: [for (final d in faltasPorDia.take(3)) if (d.ausentes > 0) d],
  );
}

/// Un parcial en la evolución de la clase.
class PuntoEvolucion {
  const PuntoEvolucion({required this.parcial, required this.promedio, required this.porAlumno, required this.cerrado});

  final Parcial parcial;
  final double? promedio;
  final Map<String, int?> porAlumno;
  final bool cerrado;
}

/// Cómo cambió el grupo y cada alumno de parcial a parcial. Los parciales sin nada
/// calificado quedan fuera.
List<PuntoEvolucion> evolucion(List<PlanParcial> planes) => [
      for (final plan in planes)
        if (calcularEstadisticas(plan) case final e when e.conNota.isNotEmpty)
          PuntoEvolucion(
            parcial: plan.parcial,
            promedio: e.promedio,
            porAlumno: {for (final a in e.alumnos) a.alumno.id: a.nota},
            cerrado: plan.cerrado,
          ),
    ];
