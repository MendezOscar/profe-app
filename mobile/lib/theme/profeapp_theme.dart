// ProfeApp — tema de marca (brand/flutter/lib/theme/profeapp_theme.dart).
// Única diferencia con el kit: Archivo va incluida en assets/fonts en lugar de
// google_fonts, que la descarga al abrir la app y sin señal caería a otra fuente.
import 'package:flutter/material.dart';

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
}

ThemeData profeTheme() {
  const scheme = ColorScheme.light(
    primary: ProfeColors.azul,
    onPrimary: ProfeColors.blanco,
    primaryContainer: ProfeColors.azulClaro,
    onPrimaryContainer: ProfeColors.azulOscuro,
    secondary: ProfeColors.marino,
    onSecondary: ProfeColors.blanco,
    surface: ProfeColors.blanco,
    onSurface: ProfeColors.marino,
    outline: ProfeColors.marino,
    error: Color(0xFFB3261E),
  );
  const square = RoundedRectangleBorder(borderRadius: BorderRadius.zero);
  final text = ThemeData.light().textTheme.apply(
    fontFamily: 'Archivo', bodyColor: ProfeColors.marino, displayColor: ProfeColors.marino);
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Archivo',
    colorScheme: scheme,
    scaffoldBackgroundColor: ProfeColors.fondo,
    textTheme: text.copyWith(
      headlineLarge: text.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      labelSmall: text.labelSmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 1.1),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: ProfeColors.fondo, foregroundColor: ProfeColors.marino,
      elevation: 0, scrolledUnderElevation: 0, centerTitle: false,
      shape: Border(bottom: BorderSide(color: ProfeColors.marino, width: 2))),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      shape: square, alignment: Alignment.centerLeft, minimumSize: const Size(64, 48),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      textStyle: const TextStyle(fontWeight: FontWeight.w800))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      shape: square, foregroundColor: ProfeColors.marino, minimumSize: const Size(64, 48),
      side: const BorderSide(color: ProfeColors.marino, width: 2))),
    cardTheme: const CardThemeData(shape: square, elevation: 0, color: ProfeColors.superficie2, margin: EdgeInsets.zero),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true, fillColor: ProfeColors.blanco,
      border: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: ProfeColors.marino, width: 2)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: ProfeColors.marino, width: 2)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: ProfeColors.azul, width: 2))),
    chipTheme: const ChipThemeData(shape: square, side: BorderSide.none),
    dividerTheme: const DividerThemeData(color: ProfeColors.marino, thickness: 2),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: ProfeColors.blanco, indicatorColor: ProfeColors.azulClaro,
      indicatorShape: square),
  );
}
