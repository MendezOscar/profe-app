import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../config.dart';
import '../models/session.dart';
import 'api_exception.dart';

/// Cliente HTTP con refresh automático de token e idempotencia por cabecera.
class ApiClient {
  ApiClient({Session? session, Future<Session?> Function(Session expired)? onRefresh})
      : _session = session,
        _onRefresh = onRefresh {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiUrl,
      // Holgado por si la API está despertando (plan gratuito de Render).
      connectTimeout: const Duration(seconds: 70),
      receiveTimeout: const Duration(seconds: 70),
      contentType: Headers.jsonContentType,
      // Los errores los traducimos nosotros a ApiException.
      validateStatus: (status) => status != null && status < 400,
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _validToken();
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
      },
      onError: (error, handler) async {
        // Un 401 con sesión vigente suele ser un token recién expirado: reintentamos una vez.
        if (error.response?.statusCode == 401 && _session != null && !_retried) {
          _retried = true;
          final refreshed = await _refresh();
          if (refreshed != null) {
            final options = error.requestOptions;
            options.headers['Authorization'] = 'Bearer ${refreshed.accessToken}';
            try {
              final response = await _dio.fetch(options);
              _retried = false;
              return handler.resolve(response);
            } catch (_) {
              // cae al error original
            }
          }
        }
        _retried = false;
        handler.next(error);
      },
    ));
  }

  late final Dio _dio;
  Session? _session;
  final Future<Session?> Function(Session expired)? _onRefresh;
  bool _retried = false;
  Future<Session?>? _refreshInFlight;

  Dio get raw => _dio;
  Session? get session => _session;

  Future<String?> _validToken() async {
    final current = _session;
    if (current == null) return null;
    if (!current.isExpired) return current.accessToken;
    final refreshed = await _refresh();
    return refreshed?.accessToken;
  }

  /// Un solo refresh en vuelo: varias pantallas cargando a la vez no deben rotar el token N veces.
  Future<Session?> _refresh() {
    final current = _session;
    if (current == null || _onRefresh == null) return Future.value(null);
    return _refreshInFlight ??= _onRefresh(current).then((refreshed) {
      // Sin esto el cliente sigue guardando la sesión vencida y vuelve a rotar con un
      // token ya quemado, que el servidor rechaza y cierra la sesión de verdad.
      if (refreshed != null) _session = refreshed;
      return refreshed;
    }).whenComplete(() => _refreshInFlight = null);
  }

  Future<T> get<T>(String path, {Map<String, dynamic>? query, T Function(dynamic)? parse}) =>
      _send(() => _dio.get(path, queryParameters: _clean(query)), parse);

  Future<T> post<T>(String path, {Object? body, Map<String, dynamic>? query, String? clientRequestId, T Function(dynamic)? parse}) =>
      _send(
          () => _dio.post(path,
              data: body,
              queryParameters: _clean(query),
              options: clientRequestId == null
                  ? null
                  : Options(headers: {'X-Client-Request-Id': clientRequestId})),
          parse);

  Future<T> put<T>(String path, {Object? body, T Function(dynamic)? parse}) =>
      _send(() => _dio.put(path, data: body), parse);

  Future<void> delete(String path) => _send<void>(() => _dio.delete(path), null);

  /// Para respuestas que son un archivo, como el cuadro exportado. Si falla, el cuerpo
  /// también llega como bytes: se decodifica el problem details para mostrar su mensaje.
  Future<Uint8List> postBytes(String path, {Object? body}) async {
    try {
      final response =
          await _dio.post<List<int>>(path, data: body, options: Options(responseType: ResponseType.bytes));
      return Uint8List.fromList(response.data ?? const []);
    } on DioException catch (error) {
      final data = error.response?.data;
      if (data is List<int>) {
        try {
          final json = jsonDecode(utf8.decode(data));
          if (json is Map<String, dynamic>) {
            throw ApiException(
              json['detail'] as String? ?? json['title'] as String? ?? 'Error inesperado.',
              code: json['code'] as String?,
              statusCode: error.response?.statusCode,
            );
          }
        } on FormatException {
          // No era JSON: cae al mensaje genérico.
        }
      }
      throw ApiException.fromDio(error);
    }
  }

  Future<T> _send<T>(Future<Response> Function() request, T Function(dynamic)? parse) async {
    try {
      final response = await request();
      if (parse == null) return null as T;
      // Un 200 sin cuerpo llega como cadena vacia, no como null: sin esto el parse
      // recibe "" y revienta con un TypeError.
      final data = response.data;
      return parse(data == '' ? null : data);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Los nulos en query rompen la ruta: se descartan antes de enviar.
  Map<String, dynamic>? _clean(Map<String, dynamic>? query) {
    if (query == null) return null;
    final cleaned = <String, dynamic>{};
    query.forEach((key, value) {
      if (value != null) cleaned[key] = value;
    });
    return cleaned.isEmpty ? null : cleaned;
  }
}
