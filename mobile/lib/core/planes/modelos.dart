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

  /// Tablas progresivas de evaluación y ponderación del Acuerdo 0158-SE-2025 (obligatorio
  /// desde el año escolar 2025 en centros gubernamentales y no gubernamentales).
  static const oficiales = [
    Plantilla(id: 'pre:0158-b1', nombre: 'Oficial · I ciclo (1.° a 3.°)', prearmada: true, rubros: [
      RubroPlantilla('Actividades de aula', 45),
      RubroPlantilla('Actividades extra aula', 10),
      RubroPlantilla('Valores y actitudes', 10),
      RubroPlantilla('Expresiones artísticas, deportivas y humanísticas', 5),
      RubroPlantilla('Exámenes escritos/prácticos', 30),
    ]),
    Plantilla(id: 'pre:0158-b2', nombre: 'Oficial · II ciclo (4.° a 6.°)', prearmada: true, rubros: [
      RubroPlantilla('Actividades de aula', 35),
      RubroPlantilla('Actividades extra aula', 10),
      RubroPlantilla('Valores y actitudes', 10),
      RubroPlantilla('Expresiones artísticas, deportivas y humanísticas', 5),
      RubroPlantilla('Exámenes escritos/prácticos', 40),
    ]),
    Plantilla(id: 'pre:0158-b3', nombre: 'Oficial · III ciclo (7.° a 9.°)', prearmada: true, rubros: [
      RubroPlantilla('Actividades de aula', 25),
      RubroPlantilla('Actividades extra aula', 10),
      RubroPlantilla('Valores y actitudes', 10),
      RubroPlantilla('Expresiones artísticas, deportivas y humanísticas', 5),
      RubroPlantilla('Exámenes escritos/prácticos', 50),
    ]),
    Plantilla(id: 'pre:0158-b3t', nombre: 'Oficial · Talleres del III ciclo técnico', prearmada: true, rubros: [
      RubroPlantilla('Actividades de taller/laboratorio', 30),
      RubroPlantilla('Actividades extra aula', 10),
      RubroPlantilla('Valores y actitudes', 10),
      RubroPlantilla('Examen escrito/práctico', 50),
    ]),
    Plantilla(id: 'pre:0158-m', nombre: 'Oficial · Media (BCH y fundamento del BTP)', prearmada: true, rubros: [
      RubroPlantilla('Actividades de aula', 35),
      RubroPlantilla('Actividades extra aula', 10),
      RubroPlantilla('Valores y actitudes', 5),
      RubroPlantilla('Examen escrito/práctico', 50),
    ]),
    Plantilla(id: 'pre:0158-mt', nombre: 'Oficial · BTP, formación específica (taller)', prearmada: true, rubros: [
      RubroPlantilla('Actividades de taller/laboratorio', 60),
      RubroPlantilla('Actividades extra aula', 10),
      RubroPlantilla('Valores y actitudes', 10),
      RubroPlantilla('Examen escrito/práctico', 20),
    ]),
  ];

  /// La tabla oficial del grado del cuadro («TERCER GRADO SECCIÓN 1» → I ciclo). En Media,
  /// la general: la de taller es sólo para la formación específica del BTP.
  static Plantilla? oficialPara(String gradoSeccion) => switch (gradoDe(gradoSeccion)) {
        null => null,
        <= 3 => oficiales[0],
        <= 6 => oficiales[1],
        <= 9 => oficiales[2],
        _ => oficiales[4],
      };

  static const prearmadas = [
    ...oficiales,
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

/// Equipo de trabajo de una clase: se califica una vez y la nota pasa a cada integrante.
class Equipo {
  const Equipo({required this.id, required this.nombre, required this.miembros});

  final String id;
  final String nombre;

  /// Ids de alumno.
  final List<String> miembros;
}

enum TipoObservacion {
  positiva('Positiva'),
  mejora('A mejorar'),
  nota('Nota');

  const TipoObservacion(this.etiqueta);

  final String etiqueta;

  static TipoObservacion desde(String? nombre) => values.firstWhere((t) => t.name == nombre, orElse: () => nota);
}

/// Nota con fecha sobre un alumno: conducta, participación o un acuerdo con el padre.
class Observacion {
  const Observacion({
    required this.id,
    required this.alumnoId,
    required this.fecha,
    required this.tipo,
    required this.texto,
  });

  final String id;
  final String alumnoId;
  final DateTime fecha;
  final TipoObservacion tipo;
  final String texto;
}

/// Una actividad en el calendario del docente, con la clase a la que pertenece.
class ActividadCalendario {
  const ActividadCalendario({
    required this.id,
    required this.claseId,
    required this.parcial,
    required this.titulo,
    required this.fecha,
    required this.puntos,
    required this.asignatura,
    required this.gradoSeccion,
    required this.alumnos,
    required this.calificados,
  });

  final String id;
  final String claseId;
  final String parcial;
  final String titulo;
  final DateTime fecha;
  final double puntos;
  final String asignatura;
  final String gradoSeccion;
  final int alumnos;
  final int calificados;

  bool get calificada => alumnos > 0 && calificados >= alumnos;
}

/// Un día en que se da la clase, con su hora (texto 'HH:mm', 24 h).
class DiaClase {
  const DiaClase({required this.dia, required this.inicio, required this.fin});

  /// 1 lunes … 7 domingo, como [DateTime.weekday].
  final int dia;
  final String inicio;
  final String fin;

  Map<String, Object> toJson() => {'dia': dia, 'inicio': inicio, 'fin': fin};

  static DiaClase fromJson(Map<String, dynamic> j) =>
      DiaClase(dia: j['dia'] as int, inicio: j['inicio'] as String? ?? '', fin: j['fin'] as String? ?? '');
}

/// Cuándo y dónde da el docente una asignatura. Es sólo para él: ordena su día y dice qué
/// días toca pasar lista. Sin días, la app sigue adivinándolos por sus listas.
class Horario {
  const Horario({this.dias = const [], this.aula = '', this.edificio = ''});

  final List<DiaClase> dias;
  final String aula;
  final String edificio;

  bool get vacio => dias.isEmpty && aula.isEmpty && edificio.isEmpty;

  DiaClase? de(DateTime fecha) => dias.where((d) => d.dia == fecha.weekday).firstOrNull;

  /// «Aula 12 · Edificio B», o vacío.
  String get lugar => [
        if (aula.isNotEmpty) 'Aula $aula',
        if (edificio.isNotEmpty) 'Edificio $edificio',
      ].join(' · ');

  Map<String, Object> toJson() => {'dias': [for (final d in dias) d.toJson()], 'aula': aula, 'edificio': edificio};

  static Horario fromJson(Map<String, dynamic> j) => Horario(
        dias: [for (final d in (j['dias'] as List? ?? const [])) DiaClase.fromJson(d as Map<String, dynamic>)]
          ..sort((a, b) => a.dia.compareTo(b.dia)),
        aula: j['aula'] as String? ?? '',
        edificio: j['edificio'] as String? ?? '',
      );
}

/// El número de grado de un encabezado de SACE: «ONCEAVO GRADO SECCIÓN 12» → 11.
int? gradoDe(String gradoSeccion) {
  final g = gradoSeccion.toUpperCase().replaceAll('É', 'E');
  const nombres = [
    ('DUODECIMO', 12), ('DOCEAVO', 12), ('UNDECIMO', 11), ('ONCEAVO', 11), ('DECIMO', 10),
    ('NOVENO', 9), ('OCTAVO', 8), ('SEPTIMO', 7), ('SEXTO', 6), ('QUINTO', 5),
    ('CUARTO', 4), ('TERCER', 3), ('SEGUNDO', 2), ('PRIMER', 1),
  ];
  for (final (nombre, n) in nombres) {
    if (g.contains(nombre)) return n;
  }
  return int.tryParse(RegExp(r'(\d+)\s*(°|º|GRADO)').firstMatch(g)?.group(1) ?? '');
}
