import 'package:flutter/foundation.dart';

/// Configuración del entorno. En producción se inyecta con --dart-define.
class AppConfig {
  static const String _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// El emulador de Android ve la máquina host en 10.0.2.2, no en localhost.
  static String get apiBaseUrl {
    if (_configuredBaseUrl.isNotEmpty) return _configuredBaseUrl;
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? 'http://10.0.2.2:5081'
        : 'http://localhost:5081';
  }

  static String get apiUrl => '$apiBaseUrl/api/v1';
}
