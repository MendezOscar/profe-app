import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/session.dart';
import '../providers.dart';
import '../router.dart';

/// Notificaciones al teléfono de la familia (comunicados del centro, faltas en la lista del
/// día). Solo en Android e iOS y solo para cuentas de padre o madre: al docente no se le
/// pide permiso porque no recibe avisos de este tipo.
class Push {
  Push._();

  static var _iniciado = false;
  static final _local = FlutterLocalNotificationsPlugin();
  static const _canal = AndroidNotificationDetails(
    'familia',
    'Avisos del centro',
    channelDescription: 'Comunicados y faltas de tus hijos',
    importance: Importance.high,
    priority: Priority.high,
  );

  static bool get disponible =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

  /// En main(): sin la configuración de Firebase la app sigue igual, solo sin avisos.
  static Future<void> iniciar() async {
    if (!disponible || _iniciado) return;
    try {
      await Firebase.initializeApp();
      _iniciado = true;
    } catch (e) {
      debugPrint('Push sin Firebase: $e');
    }
  }

  static bool get listo => _iniciado;
}

/// Registra el teléfono del padre en el servidor al iniciar sesión y abre la pantalla que
/// indique el aviso al tocarlo. Se monta una vez en la raíz de la app.
final pushProvider = Provider<void>((ref) {
  if (!Push.listo) return;
  final mensajes = FirebaseMessaging.instance;
  StreamSubscription<String>? refresco;
  StreamSubscription<RemoteMessage>? enPrimerPlano;
  StreamSubscription<RemoteMessage>? alAbrir;

  Future<void> registrar(String token) async {
    try {
      await ref.read(apiClientProvider).post<void>('/dispositivos', body: {
        'token': token,
        'plataforma': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      });
    } catch (e) {
      debugPrint('No se registró el dispositivo: $e');
    }
  }

  void abrir(RemoteMessage m) {
    final ruta = m.data['ruta'];
    if (ruta is String && ruta.startsWith('/')) ref.read(routerProvider).go(ruta);
  }

  Future<void> activar() async {
    final permiso = await mensajes.requestPermission();
    if (permiso.authorizationStatus == AuthorizationStatus.denied) return;
    // En iOS el aviso se ve también con la app abierta; en Android se muestra a mano.
    await mensajes.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
    if (defaultTargetPlatform == TargetPlatform.android) {
      await Push._local.initialize(
          settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      enPrimerPlano ??= FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n == null) return;
        Push._local.show(
          id: m.hashCode,
          title: n.title,
          body: n.body,
          notificationDetails: const NotificationDetails(android: Push._canal),
        );
      });
    }
    alAbrir ??= FirebaseMessaging.onMessageOpenedApp.listen(abrir);
    if (await mensajes.getInitialMessage() case final inicial?) abrir(inicial);

    // En iOS el token de FCM necesita antes el de APNs; puede tardar un momento.
    if (defaultTargetPlatform == TargetPlatform.iOS && await mensajes.getAPNSToken() == null) {
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    // getToken/onTokenRefresh siguen siendo lo que el SDK de servidor (FirebaseAdmin para
    // .NET) sabe usar; la API nueva (register/onRegistered) entrega otro identificador.
    // ignore: deprecated_member_use
    final token = await mensajes.getToken();
    if (token != null) await registrar(token);
    // ignore: deprecated_member_use
    refresco ??= mensajes.onTokenRefresh.listen(registrar);
  }

  Future<void> desactivar() async {
    await refresco?.cancel();
    refresco = null;
    // Sin token, el servidor deja de mandarle avisos a este teléfono y lo olvida.
    try {
      // ignore: deprecated_member_use
      await mensajes.deleteToken();
    } catch (_) {}
  }

  ref.listen<Session?>(sessionProvider, (antes, ahora) {
    final eraPadre = antes?.role == 'Padre';
    final esPadre = ahora?.role == 'Padre' && ahora?.mustChangePassword == false;
    if (esPadre && (antes?.userId != ahora?.userId || !eraPadre)) unawaited(activar());
    if (eraPadre && ahora == null) unawaited(desactivar());
  }, fireImmediately: true);

  ref.onDispose(() {
    refresco?.cancel();
    enPrimerPlano?.cancel();
    alAbrir?.cancel();
  });
});
