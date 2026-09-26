import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_exception.dart';
import '../config.dart';
import '../models/session.dart';
import 'token_storage.dart';

class AuthState {
  const AuthState({this.session, this.isLoading = false, this.error, this.isRestoring = true});

  final Session? session;
  final bool isLoading;
  final String? error;
  final bool isRestoring;

  bool get isAuthenticated => session != null;

  AuthState copyWith({Session? session, bool? isLoading, String? error, bool? isRestoring, bool clearSession = false}) =>
      AuthState(
        session: clearSession ? null : (session ?? this.session),
        isLoading: isLoading ?? this.isLoading,
        error: error,
        isRestoring: isRestoring ?? this.isRestoring,
      );
}

/// Dueño de la sesión: login, refresh y logout. Todo lo demás la consume.
class AuthController extends Notifier<AuthState> {
  late final TokenStorage _storage = TokenStorage();
  late final Dio _dio = Dio(BaseOptions(
    baseUrl: AppConfig.apiUrl,
    connectTimeout: const Duration(seconds: 15),
    validateStatus: (status) => status != null && status < 400,
  ));

  @override
  AuthState build() {
    Future.microtask(restore);
    return const AuthState();
  }

  Future<void> restore() async {
    final stored = await _storage.read();
    if (stored == null) {
      state = const AuthState(isRestoring: false);
      return;
    }
    if (stored.isExpired) {
      final refreshed = await refresh(stored);
      // Sin red no se descarta la sesión: queda la vencida y el próximo pedido reintenta.
      // Si el servidor la rechazó, refresh ya limpió el disco y dejó el aviso.
      if (refreshed == null && state.error != null) {
        state = state.copyWith(isRestoring: false);
        return;
      }
      state = AuthState(session: refreshed ?? stored, isRestoring: false);
      return;
    }
    state = AuthState(session: stored, isRestoring: false);
  }

  Future<bool> login(String email, String password) => _authenticate('/auth/login', {
        'email': email.trim(),
        'password': password,
        'deviceName': 'ProfeApp',
      });

  Future<bool> _authenticate(String path, Map<String, dynamic> body) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _dio.post(path, data: body);
      final session = Session.fromAuthResponse(response.data as Map<String, dynamic>);
      await _storage.write(session);
      state = AuthState(session: session, isRestoring: false);
      return true;
    } on DioException catch (error) {
      final failure = ApiException.fromDio(error);
      state = AuthState(isLoading: false, error: failure.message, isRestoring: false);
      return false;
    }
  }

  Future<Session?>? _refreshInFlight;

  /// Rota el refresh token. La rotación es estricta del lado del servidor: usar dos veces
  /// el mismo token lo invalida, así que acá se garantiza una sola rotación a la vez.
  Future<Session?> refresh(Session expired) {
    // Alguien más ya rotó mientras este llamador esperaba: el token que trae está
    // quemado, pero la sesión está viva. Pedir otra vez la mataría.
    final current = state.session;
    if (current != null && current.refreshToken != expired.refreshToken) {
      return Future.value(current);
    }
    return _refreshInFlight ??= _rotate(expired).whenComplete(() => _refreshInFlight = null);
  }

  Future<Session?> _rotate(Session expired) async {
    try {
      final response = await _dio.post('/auth/refresh', data: {'refreshToken': expired.refreshToken});
      final session = Session.fromAuthResponse(response.data as Map<String, dynamic>);
      await _storage.write(session);
      state = AuthState(session: session, isRestoring: false);
      return session;
    } on DioException catch (error) {
      // Sólo el rechazo del servidor cierra la sesión. Un timeout o una zona sin señal
      // no son motivo para hacer entrar de nuevo a un docente que está en el aula sin señal.
      final status = error.response?.statusCode;
      if (status != 401 && status != 403) return null;

      await _storage.clear();
      state = const AuthState(isRestoring: false, error: 'Tu sesión expiró, vuelve a entrar.');
      return null;
    }
  }

  Future<void> logout() async {
    final current = state.session;
    if (current != null) {
      try {
        await _dio.post('/auth/logout', data: {'refreshToken': current.refreshToken});
      } catch (_) {
        // Cerrar sesión local es lo que importa.
      }
    }
    await _storage.clear();
    state = const AuthState(isRestoring: false);
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
