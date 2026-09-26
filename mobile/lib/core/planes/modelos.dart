/// Un parcial tal como lo trae el cuadro de SACE: el grupo `PARCIAL I` con sus columnas.
/// Al cerrarlo, la nota va a [notaClave] y las faltas a [inasistenciasClave].
class Parcial {
  const Parcial({required this.clave, required this.titulo, this.notaClave, this.inasistenciasClave});

  /// Clave normalizada del grupo; es la que usan rubros, actividades y sesiones.
  final String clave;
  final String titulo;
  final String? notaClave;
  final String? inasistenciasClave;
}

class RubroPlantilla {
  const RubroPlantilla(this.nombre, this.puntos);

  final String nombre;
  final double puntos;

  Map<String, Object> toJson() => {'nombre': nombre, 'puntos': puntos};

  factory RubroPlantilla.fromJson(Map<String, dynamic> j) =>
      RubroPlantilla(j['nombre'] as String, (j['puntos'] as num).toDouble());
}

/// Molde reutilizable de un plan. Aplicarlo copia los rubros a la clase: cambiar la
/// plantilla después no toca los planes ya aplicados.
class Plantilla {
  const Plantilla({required this.id, required this.nombre, required this.rubros, this.prearmada = false});

  final String id;
  final String nombre;
  final List<RubroPlantilla> rubros;

  /// Viene con la app: no se edita ni se sincroniza.
  final bool prearmada;

  double get total => rubros.fold(0, (s, r) => s + r.puntos);

  static const prearmadas = [
    Plantilla(id: 'pre:clasico', nombre: 'Acumulativo y examen', prearmada: true, rubros: [
      RubroPlantilla('Tareas', 30),
      RubroPlantilla('Trabajo en clase', 20),
      RubroPlantilla('Proyecto', 20),
      RubroPlantilla('Examen', 30),
    ]),
    Plantilla(id: 'pre:practico', nombre: 'Práctico', prearmada: true, rubros: [
      RubroPlantilla('Prácticas', 40),
      RubroPlantilla('Proyecto', 30),
      RubroPlantilla('Prueba', 30),
    ]),
    Plantilla(id: 'pre:examenes', nombre: 'Dos pruebas', prearmada: true, rubros: [
      RubroPlantilla('Tareas', 20),
      RubroPlantilla('Participación', 10),
      RubroPlantilla('Prueba corta', 30),
      RubroPlantilla('Examen', 40),
    ]),
  ];
}

class Rubro {
  const Rubro({required this.id, required this.nombre, required this.puntos, required this.orden});

  final String id;
  final String nombre;
  final double puntos;
  final int orden;
}

class Actividad {
  const Actividad({
    required this.id,
    required this.rubroId,
    required this.titulo,
    required this.fecha,
    required this.puntos,
    this.descripcion,
  });

  final String id;
  final String rubroId;
  final String titulo;
  final DateTime fecha;
  final double puntos;
  final String? descripcion;
}

/// Sin registro, el alumno está presente. Sólo las ausencias van a INASISTENCIAS.
enum EstadoAsistencia {
  presente(null, 'Presente'),
  ausente('A', 'Ausente'),
  tarde('T', 'Tarde'),
  justificada('J', 'Justificada');

  const EstadoAsistencia(this.codigo, this.etiqueta);
  final String? codigo;
  final String etiqueta;

  static EstadoAsistencia desde(String? codigo) =>
      values.firstWhere((e) => e.codigo == codigo, orElse: () => presente);

  /// El orden en que cambia al tocar al alumno al pasar lista.
  EstadoAsistencia get siguiente => values[(index + 1) % values.length];
}

class Sesion {
  const Sesion({required this.id, required this.fecha});

  final String id;
  final DateTime fecha;
}

class AlumnoPlan {
  const AlumnoPlan({required this.id, required this.nombre, required this.identidad});

  final String id;
  final String nombre;
  final String identidad;
}

/// Todo lo de una clase en un parcial: el plan, lo calificado y la asistencia.
class PlanParcial {
  const PlanParcial({
    required this.claseId,
    required this.parcial,
    required this.rubros,
    required this.actividades,
    required this.alumnos,
    required this.calificaciones,
    required this.sesiones,
    required this.asistencias,
    this.cerradoEn,
  });

  final String claseId;
  final Parcial parcial;
  final List<Rubro> rubros;
  final List<Actividad> actividades;
  final List<AlumnoPlan> alumnos;

  /// actividadId → alumnoId → puntos obtenidos.
  final Map<String, Map<String, double>> calificaciones;
  final List<Sesion> sesiones;

  /// sesionId → alumnoId → estado distinto de presente.
  final Map<String, Map<String, EstadoAsistencia>> asistencias;
  final DateTime? cerradoEn;

  bool get cerrado => cerradoEn != null;
}
