import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

import '../models/session.dart';

/// Guarda la sesión cifrada en móvil; en web cae a shared_preferences.
class TokenStorage {
  static const _key = 'profeapp.session';
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<Session?> read() async {
    final raw = kIsWeb
        ? (await SharedPreferences.getInstance()).getString(_key)
        : await _readSecure();
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
      await (await SharedPreferences.getInstance()).setString(_key, raw);
    } else {
      await _secure.write(key: _key, value: raw);
    }
  }

  Future<void> clear() async {
    if (kIsWeb) {
      await (await SharedPreferences.getInstance()).remove(_key);
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
