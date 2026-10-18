import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

import '../models/session.dart';
import 'almacen_pestana.dart' if (dart.library.js_interop) 'almacen_pestana_web.dart';

/// Guarda la sesión cifrada en móvil. En web, por defecto sólo mientras la pestaña esté
/// abierta (sessionStorage): el panel suele usarse en computadoras compartidas. Con
/// [recordar], en el almacenamiento del navegador, que sobrevive al cerrarlo.
class TokenStorage {
  static const _key = 'profeapp.session';

  /// Dónde va la sesión en web; lo fija el login y lo recuerda la lectura.
  bool recordar = false;
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<Session?> read() async {
    String? raw;
    if (kIsWeb) {
      raw = leerDePestana(_key);
      recordar = raw == null;
      raw ??= (await SharedPreferences.getInstance()).getString(_key);
    } else {
      raw = await _readSecure();
    }
    if (raw == null) return null;
    try {
      return Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await clear();
      return null;
    }
  }

  Future<void> write(Session session) async {
    final raw = jsonEncode(session.toJson());
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      if (recordar) {
        await prefs.setString(_key, raw);
        borrarDePestana(_key);
      } else {
        guardarEnPestana(_key, raw);
        await prefs.remove(_key);
      }
    } else {
      await _secure.write(key: _key, value: raw);
    }
  }

  Future<void> clear() async {
    if (kIsWeb) {
      await (await SharedPreferences.getInstance()).remove(_key);
      borrarDePestana(_key);
    } else {
      await _secure.delete(key: _key);
    }
  }

  Future<String?> _readSecure() async {
    try {
      return await _secure.read(key: _key);
    } catch (_) {
      // Keystore corrupto tras reinstalar: preferimos pedir login de nuevo.
      return null;
    }
  }
}
