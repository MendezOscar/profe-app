// ProfeApp — tema de marca (brand/flutter/lib/theme/profeapp_theme.dart).
// Única diferencia con el kit: Archivo va incluida en assets/fonts en lugar de
// google_fonts, que la descarga al abrir la app y sin señal caería a otra fuente.
import 'package:flutter/material.dart';

import 'tokens.dart';

export 'tokens.dart';

class ProfeColors {
  static const azul = Color(0xFF2B59C3);
  static const azulHover = Color(0xFF234AA6);
  static const azulOscuro = Color(0xFF1E3F8C);
  static const azulClaro = Color(0xFFE8EEFA);
  static const marino = Color(0xFF14213D);
  static const textoSuave = Color(0xFF4A5670);
  static const fondo = Color(0xFFF5F7FB);
  static const superficie2 = Color(0xFFEAEFF8);
  static const blanco = Color(0xFFFFFFFF);

  // Fuera del kit de marca: grises azulados para bordes suaves y superficies, en lugar de
  // los violetas que Material 3 pone por defecto. Contrastes en tokens.dart.
  static const bordeSuave = Color(0xFFC9D2E3);
  static const superficie3 = Color(0xFFE1E8F4);
  static const superficie4 = Color(0xFFD8E0EF);
  static const rojo = Color(0xFFB3261E);
  static const rojoSuave = Color(0xFFFBE9E7);
  static const verde = Color(0xFF1E7B4A);
  static const verdeSuave = Color(0xFFE3F4EA);
  static const amarillo = Color(0xFFFFE08A);
}

/// Colores del modo oscuro, fuera del kit de marca: fondo marino profundo, el azul de la
/// marca aclarado para que contraste sobre él y textos claros. Mismos papeles que en claro.
class ProfeColorsOscuro {
  static const fondo = Color(0xFF0E1525);
  static const superficie = Color(0xFF151E33);
  static const superficie2 = Color(0xFF1B2640);
  static const superficie3 = Color(0xFF23304F);
  static const superficie4 = Color(0xFF2B3A5D);
  static const texto = Color(0xFFE6EBF5);
  static const textoSuave = Color(0xFFAEB8CC);
  static const borde = Color(0xFF8794B0);
  static const bordeSuave = Color(0xFF33415F);
  static const azul = Color(0xFF8DB0FF);
  static const enAzul = Color(0xFF0B1E4D);
  static const azulContenedor = Color(0xFF1E3F8C);
  static const enAzulContenedor = Color(0xFFDCE6FF);
  static const rojo = Color(0xFFFFB4AB);
  static const enRojo = Color(0xFF690005);
  static const rojoSuave = Color(0xFF5C1A15);
  static const enRojoSuave = Color(0xFFFFDAD6);
  static const verde = Color(0xFF7BD8A4);
  static const enVerde = Color(0xFF00391C);
  static const verdeSuave = Color(0xFF143A27);
}

/// El tema de la app. Sigue el modo del teléfono: [oscuro] lo decide MaterialApp con
/// darkTheme, no el docente.
ThemeData profeTheme({bool oscuro = false}) {
  const claro = ColorScheme.light(
    primary: ProfeColors.azul,
    onPrimary: ProfeColors.blanco,
    primaryContainer: ProfeColors.azulClaro,
    onPrimaryContainer: ProfeColors.azulOscuro,
    secondary: ProfeColors.marino,
    onSecondary: ProfeColors.blanco,
    surface: ProfeColors.blanco,
    onSurface: ProfeColors.marino,
    onSurfaceVariant: ProfeColors.textoSuave,
    outline: ProfeColors.marino,
    outlineVariant: ProfeColors.bordeSuave,
    surfaceContainerLowest: ProfeColors.blanco,
    surfaceContainerLow: ProfeColors.fondo,
    surfaceContainer: ProfeColors.superficie2,
    surfaceContainerHigh: ProfeColors.superficie3,
    surfaceContainerHighest: ProfeColors.superficie4,
    error: ProfeColors.rojo,
    errorContainer: ProfeColors.rojoSuave,
    onErrorContainer: ProfeColors.rojo,
  );
  const noche = ColorScheme.dark(
    primary: ProfeColorsOscuro.azul,
    onPrimary: ProfeColorsOscuro.enAzul,
    primaryContainer: ProfeColorsOscuro.azulContenedor,
    onPrimaryContainer: ProfeColorsOscuro.enAzulContenedor,
    secondary: ProfeColorsOscuro.texto,
    onSecondary: ProfeColors.marino,
    secondaryContainer: ProfeColorsOscuro.superficie4,
    onSecondaryContainer: ProfeColorsOscuro.texto,
    surface: ProfeColorsOscuro.superficie,
    onSurface: ProfeColorsOscuro.texto,
    onSurfaceVariant: ProfeColorsOscuro.textoSuave,
    outline: ProfeColorsOscuro.borde,
    outlineVariant: ProfeColorsOscuro.bordeSuave,
    surfaceContainerLowest: ProfeColorsOscuro.fondo,
    surfaceContainerLow: ProfeColorsOscuro.superficie,
    surfaceContainer: ProfeColorsOscuro.superficie2,
    surfaceContainerHigh: ProfeColorsOscuro.superficie3,
    surfaceContainerHighest: ProfeColorsOscuro.superficie4,
    error: ProfeColorsOscuro.rojo,
    onError: ProfeColorsOscuro.enRojo,
    errorContainer: ProfeColorsOscuro.rojoSuave,
    onErrorContainer: ProfeColorsOscuro.enRojoSuave,
  );
  final scheme = oscuro ? noche : claro;
  final fondo = oscuro ? ProfeColorsOscuro.fondo : ProfeColors.fondo;
  final tinta = scheme.onSurface;
  final borde = BorderSide(color: scheme.outline, width: 2);
  const square = RoundedRectangleBorder(borderRadius: BorderRadius.zero);
  final text = (oscuro ? ThemeData.dark() : ThemeData.light()).textTheme.apply(
    fontFamily: 'Archivo', bodyColor: tinta, displayColor: tinta);
  return ThemeData(
    useMaterial3: true,
    brightness: scheme.brightness,
    fontFamily: 'Archivo',
    colorScheme: scheme,
    scaffoldBackgroundColor: fondo,
    textTheme: text.copyWith(
      headlineLarge: text.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      labelSmall: text.labelSmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 1.1),
      // Interlineado amplio para leer listas largas de nombres en el teléfono.
      bodyLarge: text.bodyLarge?.copyWith(height: 1.45),
      bodyMedium: text.bodyMedium?.copyWith(height: 1.4),
      bodySmall: text.bodySmall?.copyWith(height: 1.35, color: scheme.onSurfaceVariant),
    ),
    extensions: [
      oscuro
          ? const ColoresEstado(
              exito: ProfeColorsOscuro.verde,
              enExito: ProfeColorsOscuro.enVerde,
              exitoSuave: ProfeColorsOscuro.verdeSuave,
              advertencia: ProfeColors.amarillo,
              enAdvertencia: ProfeColors.marino,
              riesgo: ProfeColorsOscuro.rojo,
              riesgoSuave: ProfeColorsOscuro.rojoSuave,
              esqueleto: ProfeColorsOscuro.superficie3,
            )
          : const ColoresEstado(
              exito: ProfeColors.verde,
              enExito: ProfeColors.blanco,
              exitoSuave: ProfeColors.verdeSuave,
              advertencia: ProfeColors.amarillo,
              enAdvertencia: ProfeColors.marino,
              riesgo: ProfeColors.rojo,
              riesgoSuave: ProfeColors.rojoSuave,
              esqueleto: ProfeColors.superficie3,
            ),
    ],
    appBarTheme: AppBarTheme(
      backgroundColor: fondo, foregroundColor: tinta,
      elevation: 0, scrolledUnderElevation: 0, centerTitle: false,
      shape: Border(bottom: borde)),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      shape: square, alignment: Alignment.centerLeft, minimumSize: const Size(64, 48),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      textStyle: const TextStyle(fontWeight: FontWeight.w800))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      shape: square, foregroundColor: tinta, minimumSize: const Size(64, 48), side: borde)),
    cardTheme: CardThemeData(shape: square, elevation: 0, color: scheme.surfaceContainer, margin: EdgeInsets.zero),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: scheme.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: borde),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: borde),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: scheme.primary, width: 2))),
    chipTheme: const ChipThemeData(shape: square, side: BorderSide.none),
    dividerTheme: DividerThemeData(color: oscuro ? scheme.outlineVariant : scheme.outline, thickness: 2),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface, indicatorColor: scheme.primaryContainer,
      indicatorShape: square),
  );
}

/// El logo que se lee sobre el fondo del tema: el azul en claro, el blanco en oscuro.
String logoMarca(BuildContext context) => Theme.of(context).brightness == Brightness.dark
    ? 'assets/brand/logo-blanco.png'
    : 'assets/brand/logo-azul.png';
