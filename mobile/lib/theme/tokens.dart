// Tokens de diseño de ProfeApp: los valores con nombre que usan todas las pantallas.
// Una pantalla nueva no inventa números ni colores: toma uno de aquí o del tema
// (Theme.of(context).colorScheme / textTheme / extension<ColoresEstado>()).
import 'package:flutter/material.dart';

/// Escala de espacios, de 4 en 4 (con 2 para ajustes finos junto al texto).
abstract final class Espacio {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;

  /// Margen bajo una lista para que el botón flotante no tape el último elemento.
  static const bajoBotonFlotante = 96.0;
}

/// Medidas que no son espacios.
abstract final class Medida {
  /// Mínimo de un área táctil (Material y WCAG 2.5.8 piden 44–48).
  static const tactil = 48.0;

  /// Ancho máximo de un texto corrido o un formulario: más ancho cansa la vista.
  static const lectura = 720.0;

  /// Ancho máximo del contenido en escritorio.
  static const contenido = 960.0;
}

/// Colores con significado, más allá de los de marca del ColorScheme. Todos cumplen
/// contraste AA (4.5:1) con su texto encima y sobre los fondos de la app.
@immutable
class ColoresEstado extends ThemeExtension<ColoresEstado> {
  const ColoresEstado({
    required this.exito,
    required this.enExito,
    required this.exitoSuave,
    required this.advertencia,
    required this.enAdvertencia,
    required this.riesgo,
    required this.riesgoSuave,
    required this.esqueleto,
  });

  /// Aprobado, al día, respaldado.
  final Color exito;
  final Color enExito;
  final Color exitoSuave;

  /// Llegó tarde, algo por revisar sin ser grave.
  final Color advertencia;
  final Color enAdvertencia;

  /// Bajo 70, en riesgo, urgente (el mismo rojo que colorScheme.error).
  final Color riesgo;
  final Color riesgoSuave;

  /// Bloques de la carga de esqueleto.
  final Color esqueleto;

  static ColoresEstado of(BuildContext context) => Theme.of(context).extension<ColoresEstado>()!;

  @override
  ColoresEstado copyWith({
    Color? exito,
    Color? enExito,
    Color? exitoSuave,
    Color? advertencia,
    Color? enAdvertencia,
    Color? riesgo,
    Color? riesgoSuave,
    Color? esqueleto,
  }) => ColoresEstado(
    exito: exito ?? this.exito,
    enExito: enExito ?? this.enExito,
    exitoSuave: exitoSuave ?? this.exitoSuave,
    advertencia: advertencia ?? this.advertencia,
    enAdvertencia: enAdvertencia ?? this.enAdvertencia,
    riesgo: riesgo ?? this.riesgo,
    riesgoSuave: riesgoSuave ?? this.riesgoSuave,
    esqueleto: esqueleto ?? this.esqueleto,
  );

  @override
  ColoresEstado lerp(ColoresEstado? other, double t) => other == null
      ? this
      : ColoresEstado(
          exito: Color.lerp(exito, other.exito, t)!,
          enExito: Color.lerp(enExito, other.enExito, t)!,
          exitoSuave: Color.lerp(exitoSuave, other.exitoSuave, t)!,
          advertencia: Color.lerp(advertencia, other.advertencia, t)!,
          enAdvertencia: Color.lerp(enAdvertencia, other.enAdvertencia, t)!,
          riesgo: Color.lerp(riesgo, other.riesgo, t)!,
          riesgoSuave: Color.lerp(riesgoSuave, other.riesgoSuave, t)!,
          esqueleto: Color.lerp(esqueleto, other.esqueleto, t)!,
        );
}
