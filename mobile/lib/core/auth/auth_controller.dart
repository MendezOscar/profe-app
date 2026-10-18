import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_exception.dart';
import '../config.dart';
import '../local/local_db.dart';
import '../models/cobro.dart';
import '../models/session.dart';
import '../providers.dart';
import 'token_storage.dart';

/// En web, de quién son los datos guardados en este navegador: se borran cuando ya nadie
/// tiene sesión (cerró sesión, o cerró la pestaña sin "recordar"), para que el siguiente
/// que use la computadora no encuentre notas ni alumnos ajenos.
const _ultimoUsuarioWeb = 'profeapp.ultimo_usuario_web';

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
    // El plan gratuito de Render duerme la API sin uso y tarda cerca de un minuto en
    // despertar: con menos espera, el primer login del día fallaba como "sin conexión".
    connectTimeout: const Duration(seconds: 70),
    receiveTimeout: const Duration(seconds: 70),
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
      await _borrarDatosWeb();
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
    // Sesiones abiertas antes de esta versión: así también se borran al salir.
    await _borrarDatosWeb(salvo: stored.userId);
    state = AuthState(session: stored, isRestoring: false);
  }

  /// Despierta la API mientras el docente escribe; si falla no importa.
  void despertarServidor() => _dio.get('${AppConfig.apiBaseUrl}/health/live').ignore();

  /// [recordar] sólo cuenta en web: sin marcarlo, la sesión muere al cerrar la pestaña.
  Future<bool> login(String email, String password, {bool recordar = false}) {
    _storage.recordar = recordar;
    return _authenticate('/auth/login', {
      'email': email.trim(),
      'password': password,
      'deviceName': 'ProfeApp',
    });
  }

  /// Borra la base local que quedó en este navegador, salvo la de [salvo].
  Future<void> _borrarDatosWeb({String? salvo}) async {
    if (!kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final ultimo = prefs.getString(_ultimoUsuarioWeb);
    if (ultimo != null && ultimo != salvo) await LocalDb.borrar(ultimo);
    if (salvo == null) {
      await prefs.remove(_ultimoUsuarioWeb);
    } else {
      await prefs.setString(_ultimoUsuarioWeb, salvo);
    }
  }

  Future<bool> _authenticate(String path, Map<String, dynamic> body) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _dio.post(path, data: body);
      final session = Session.fromAuthResponse(response.data as Map<String, dynamic>);
      await _storage.write(session);
      await _borrarDatosWeb(salvo: session.userId);
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

      // El motivo del servidor (cuenta desactivada o suspendida) dice más que "expiró".
      final datos = error.response?.data;
      final motivo = datos is Map && datos['detail'] is String ? datos['detail'] as String : null;
      await _storage.clear();
      state = AuthState(isRestoring: false, error: motivo ?? 'Tu sesión expiró, vuelve a entrar.');
      return null;
    }
  }

  /// Tras cambiar la contraseña: se levanta la obligación de cambiar la temporal.
  Future<void> claveCambiada() async {
    final actual = state.session;
    if (actual == null || !actual.mustChangePassword) return;
    final session = Session.fromJson({...actual.toJson(), 'mustChangePassword': false});
    await _storage.write(session);
    state = state.copyWith(session: session);
  }

  /// El servidor avisó que el plan cambió (por ejemplo, quedó de sólo lectura): se guarda
  /// el estado nuevo para que los avisos y el candado de la app lo reflejen ya.
  Future<void> cobroActualizado(Map<String, dynamic> cobro) async {
    final actual = state.session;
    if (actual == null) return;
    final session = actual.conCobro(Cobro.fromJson(cobro));
    await _storage.write(session);
    state = state.copyWith(session: session);
  }

  Future<void> logout() async {
    final current = state.session;
    if (current != null) {
      try {
        // Con el access token, el servidor lo anula ya y no a los 15 minutos.
        await _dio.post('/auth/logout',
            data: {'refreshToken': current.refreshToken},
            options: Options(headers: {'Authorization': 'Bearer ${current.accessToken}'}));
      } catch (_) {
        // Cerrar sesión local es lo que importa.
      }
      // En web, la base se cierra antes de borrarla (en el teléfono se queda: es personal).
      if (kIsWeb) {
        try {
          await (await ref.read(localDbProvider)).close();
        } catch (_) {
          // Ya estaba cerrada.
        }
      }
    }
    await _storage.clear();
    state = const AuthState(isRestoring: false);
    if (kIsWeb && current != null) await LocalDb.borrar(current.userId);
    await _borrarDatosWeb();
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
