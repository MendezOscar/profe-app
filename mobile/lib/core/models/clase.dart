import '../sace/cuadro_sace.dart';

class ClaseResumen {
  const ClaseResumen({
    required this.id,
    required this.asignatura,
    required this.gradoSeccion,
    required this.jornada,
    required this.centro,
    required this.alumnos,
    required this.actualizadaEn,
  });

  final String id;
  final String asignatura;
  final String gradoSeccion;
  final String jornada;
  final String centro;
  final int alumnos;
  final DateTime actualizadaEn;
}

class Columna {
  const Columna({required this.clave, required this.grupo, required this.nombre, required this.tipo});

  final String clave;
  final String grupo;
  final String nombre;
  final TipoColumna tipo;

  /// `PARCIAL I · NOTA TOTAL`, o sólo `RECUPERACIÓN` cuando no hay subencabezado.
  String get titulo => grupo == nombre ? nombre : '$grupo · $nombre';
}

class Alumno {
  const Alumno({required this.id, required this.identidad, required this.nombre});

  final String id;
  final String identidad;
  final String nombre;
}

class ClaseDetalle {
  const ClaseDetalle({
    required this.resumen,
    required this.modalidad,
    required this.columnas,
    required this.alumnos,
    required this.valores,
  });

  final ClaseResumen resumen;
  final String modalidad;
  final List<Columna> columnas;
  final List<Alumno> alumnos;

  /// alumnoId → clave de columna → valor.
  final Map<String, Map<String, int>> valores;

}

class ResultadoImportacion {
  const ResultadoImportacion({
    required this.claseId,
    required this.nueva,
    required this.alumnos,
    required this.columnasNuevas,
  });

  final String claseId;
  final bool nueva;
  final int alumnos;
  final List<String> columnasNuevas;
}
