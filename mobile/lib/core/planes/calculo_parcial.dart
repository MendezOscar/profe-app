import 'modelos.dart';

/// Lo de un alumno en el parcial.
class NotaAlumno {
  const NotaAlumno({required this.obtenidos, required this.pendientes, required this.inasistencias});

  /// Suma de puntos obtenidos, sin redondear.
  final double obtenidos;

  /// Actividades que todavía no tienen nota para este alumno.
  final int pendientes;
  final int inasistencias;

  /// La que va a SACE: entera y con tope de 100.
  int get nota => obtenidos.round().clamp(0, 100);
}

class ResultadoParcial {
  const ResultadoParcial({
    required this.totalPlan,
    required this.asignado,
    required this.asignadoPorRubro,
    required this.porAlumno,
    required this.actividadesIncompletas,
  });

  /// Suma de los rubros del plan. Debería ser 100.
  final double totalPlan;

  /// Suma de los puntos de las actividades creadas hasta hoy.
  final double asignado;
  final Map<String, double> asignadoPorRubro;
  final Map<String, NotaAlumno> porAlumno;

  /// Actividades a las que les falta nota de algún alumno.
  final List<Actividad> actividadesIncompletas;

  /// Lo que habría que revisar antes de cerrar el parcial. Vacío = todo en orden.
  List<String> advertencias(PlanParcial plan) => [
        if (plan.rubros.isEmpty) 'El parcial no tiene plan de calificación.',
        if (plan.rubros.isNotEmpty && totalPlan != 100) 'El plan suma ${_n(totalPlan)} puntos, no 100.',
        if (plan.rubros.isNotEmpty && asignado < totalPlan)
          'Las actividades suman ${_n(asignado)} de ${_n(totalPlan)} puntos.',
        for (final r in plan.rubros)
          if ((asignadoPorRubro[r.id] ?? 0) > r.puntos)
            '${r.nombre}: las actividades suman ${_n(asignadoPorRubro[r.id]!)} y el rubro vale ${_n(r.puntos)}.',
        for (final a in actividadesIncompletas) '${a.titulo}: faltan notas.',
        if (plan.sesiones.isEmpty) 'No se ha pasado lista en este parcial.',
      ];
}

/// Números como los escribe el docente: 30 y no 30.0.
String _n(double v) => formatoPuntos(v);

String formatoPuntos(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

/// Nota del parcial por puntos: lo obtenido en cada actividad se suma tal cual.
/// Una actividad sin nota no resta, sólo queda pendiente.
ResultadoParcial calcularParcial(PlanParcial plan) {
  final porRubro = <String, double>{};
  for (final a in plan.actividades) {
    porRubro[a.rubroId] = (porRubro[a.rubroId] ?? 0) + a.puntos;
  }

  final ausencias = <String, int>{};
  for (final porSesion in plan.asistencias.values) {
    for (final MapEntry(key: alumnoId, value: estado) in porSesion.entries) {
      if (estado == EstadoAsistencia.ausente) ausencias[alumnoId] = (ausencias[alumnoId] ?? 0) + 1;
    }
  }

  final porAlumno = <String, NotaAlumno>{};
  for (final alumno in plan.alumnos) {
    var obtenidos = 0.0;
    var pendientes = 0;
    for (final a in plan.actividades) {
      final valor = plan.calificaciones[a.id]?[alumno.id];
      if (valor == null) {
        pendientes++;
      } else {
        obtenidos += valor;
      }
    }
    porAlumno[alumno.id] =
        NotaAlumno(obtenidos: obtenidos, pendientes: pendientes, inasistencias: ausencias[alumno.id] ?? 0);
  }

  return ResultadoParcial(
    totalPlan: plan.rubros.fold(0, (s, r) => s + r.puntos),
    asignado: plan.actividades.fold(0, (s, a) => s + a.puntos),
    asignadoPorRubro: porRubro,
    porAlumno: porAlumno,
    actividadesIncompletas: [
      for (final a in plan.actividades)
        if (plan.alumnos.any((al) => plan.calificaciones[a.id]?[al.id] == null)) a,
    ],
  );
}
