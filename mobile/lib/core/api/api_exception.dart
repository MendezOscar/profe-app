import 'package:dio/dio.dart';

/// Error de negocio o de red, ya traducido a algo que se puede mostrar al usuario.
class ApiException implements Exception {
  ApiException(this.message, {this.code, this.statusCode, this.isNetworkError = false});

  final String message;
  final String? code;
  final int? statusCode;
  final bool isNetworkError;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isConflict => statusCode == 409;
  bool get isNotFound => statusCode == 404;

  /// True cuando reintentar más tarde tiene sentido (la cola offline se apoya en esto).
  bool get isRetryable => isNetworkError || (statusCode != null && statusCode! >= 500);

  factory ApiException.fromDio(DioException error) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return ApiException('Sin conexión con el servidor.', isNetworkError: true);
    }

    final response = error.response;
    final data = response?.data;
    if (data is Map<String, dynamic>) {
      final detail = data['detail'] as String? ?? data['title'] as String?;
      return ApiException(
        detail ?? 'Error inesperado.',
        code: data['code'] as String?,
        statusCode: response?.statusCode,
      );
    }
    return ApiException(
      response?.statusCode == 401 ? 'Sesión expirada.' : 'Error inesperado (${response?.statusCode ?? '-'}).',
      statusCode: response?.statusCode,
    );
  }

  @override
  String toString() => message;
}
