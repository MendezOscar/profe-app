/// En qué anda el plan de la cuenta, tal como lo calcula el servidor. Lo trae cada inicio
/// y renovación de sesión, así que sin red queda el último conocido.
enum EstadoCobro { alDia, porVencer, gracia, soloLectura }

class Cobro {
  const Cobro({
    required this.estado,
    required this.mensaje,
    this.planNombre,
    this.monto = 0,
    this.pagadoHasta,
    this.diasGracia = 0,
    this.bloqueaEn,
    this.diasRestantes,
    this.comoPagar,
    this.nivel,
    this.topeAsignaturas,
  });

  final EstadoCobro estado;
  final String mensaje;
  final String? planNombre;
  final double monto;
  final DateTime? pagadoHasta;
  final int diasGracia;
  final DateTime? bloqueaEn;
  final int? diasRestantes;
  final String? comoPagar;

  /// basico, docente o plus; null sin tope (o docente de un centro).
  final String? nivel;
  final int? topeAsignaturas;

  bool get soloLectura => estado == EstadoCobro.soloLectura;

  /// Hay algo que avisar: por vencer, en gracia o ya de sólo lectura.
  bool get pideAtencion => estado != EstadoCobro.alDia;

  static DateTime? _fecha(Object? v) => v == null ? null : DateTime.parse(v as String);

  factory Cobro.fromJson(Map<String, dynamic> json) => Cobro(
        estado: EstadoCobro.values.asNameMap()[json['estado']] ?? EstadoCobro.alDia,
        mensaje: json['mensaje'] as String? ?? '',
        planNombre: json['planNombre'] as String?,
        monto: (json['monto'] as num?)?.toDouble() ?? 0,
        pagadoHasta: _fecha(json['pagadoHasta']),
        diasGracia: json['diasGracia'] as int? ?? 0,
        bloqueaEn: _fecha(json['bloqueaEn']),
        diasRestantes: json['diasRestantes'] as int?,
        comoPagar: json['comoPagar'] as String?,
        nivel: json['nivel'] as String?,
        topeAsignaturas: json['topeAsignaturas'] as int?,
      );

  static String? _iso(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        'estado': estado.name,
        'mensaje': mensaje,
        'planNombre': planNombre,
        'monto': monto,
        'pagadoHasta': _iso(pagadoHasta),
        'diasGracia': diasGracia,
        'bloqueaEn': _iso(bloqueaEn),
        'diasRestantes': diasRestantes,
        'comoPagar': comoPagar,
        'nivel': nivel,
        'topeAsignaturas': topeAsignaturas,
      };
}

/// Los planes del docente, con el tope de asignaturas de cada uno (igual que el servidor).
const nivelesDocente = {
  'basico': ('Básico', 3),
  'docente': ('Docente', 8),
  'plus': ('Plus', null),
};
