import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_datos;
import 'package:timezone/timezone.dart' as tz;

import 'avisos.dart';

/// Recordatorio de pendientes a las 5 p. m., programado en el teléfono: no pasa por el
/// servidor ni necesita internet. Cada vez que la app recalcula los avisos se reprograma
/// con lo que haya pendiente; sin pendientes, se cancela. En la web no existe.
class Recordatorio {
  Recordatorio._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _id = 1;
  static const _hora = 17;
  static var _listo = false;

  static bool get disponible => !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

  static Future<void> _iniciar() async {
    if (_listo) return;
    tz_datos.initializeTimeZones();
    // SACE es de Honduras: la hora del centro educativo es la de Tegucigalpa.
    tz.setLocalLocation(tz.getLocation('America/Tegucigalpa'));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // El permiso se pide cuando el docente activa el recordatorio, no al abrir la app.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _listo = true;
  }

  /// Pide permiso para notificar. Devuelve si quedó concedido.
  static Future<bool> pedirPermiso() async {
    if (!disponible) return false;
    await _iniciar();
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final concedido = await ios?.requestPermissions(alert: true, badge: true, sound: true) ??
        await android?.requestNotificationsPermission();
    return concedido ?? false;
  }

  static Future<void> cancelar() async {
    if (!disponible) return;
    await _iniciar();
    await _plugin.cancel(id: _id);
  }

  /// El próximo recordatorio con lo pendiente ahora (hoy a las 5, o mañana si ya pasó).
  static Future<void> programar(List<Aviso> avisos) async {
    if (!disponible) return;
    await _iniciar();
    await _plugin.cancel(id: _id);
    if (avisos.isEmpty) return;

    final ahora = tz.TZDateTime.now(tz.local);
    var cuando = tz.TZDateTime(tz.local, ahora.year, ahora.month, ahora.day, _hora);
    if (!cuando.isAfter(ahora)) cuando = cuando.add(const Duration(days: 1));

    final n = avisos.length;
    await _plugin.zonedSchedule(
      id: _id,
      scheduledDate: cuando,
      title: n == 1 ? 'Tienes 1 pendiente en ProfeApp' : 'Tienes $n pendientes en ProfeApp',
      body: [for (final a in avisos.take(2)) a.titulo, if (n > 2) 'y ${n - 2} más'].join(' · '),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'pendientes',
          'Pendientes',
          channelDescription: 'Recordatorio diario de lo que falta calificar, pasar lista o exportar.',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      // Sin alarmas exactas: no hace falta el permiso especial y unos minutos de más no importan.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}
