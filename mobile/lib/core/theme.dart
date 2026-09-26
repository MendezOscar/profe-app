import 'package:flutter/material.dart';

/// Colores de marca provisionales hasta tener el set definitivo.
class Brand {
  /// Azul pizarra: color primario.
  static const primary = Color(0xFF1E4E8C);
  static const deep = Color(0xFF0E2340);
  static const soft = Color(0xFFB9CDEB);
  static const paper = Color(0xFFF4F3EF);
  static const ink = Color(0xFF15181C);
  static const muted = Color(0xFF6A717A);
  static const line = Color(0xFFE0DFDA);
}

/// Un solo tema para web y móvil.
class AppTheme {
  static ThemeData light() => _base(
        ColorScheme.fromSeed(seedColor: Brand.primary).copyWith(
          primary: Brand.primary,
          onPrimary: Brand.paper,
          surface: Brand.paper,
          onSurface: Brand.ink,
          outline: Brand.muted,
          outlineVariant: Brand.line,
        ),
      );

  static ThemeData dark() => _base(
        ColorScheme.fromSeed(seedColor: Brand.primary, brightness: Brightness.dark).copyWith(
          primary: Brand.soft,
          onPrimary: Brand.deep,
          surface: Brand.deep,
          onSurface: Brand.paper,
        ),
      );

  static ThemeData _base(ColorScheme scheme) => ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: scheme.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: scheme.surface,
          surfaceTintColor: scheme.surfaceTint,
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 2,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
}
