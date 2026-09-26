import 'package:flutter_test/flutter_test.dart';
import 'package:profeapp/core/models/session.dart';

void main() {
  test('La sesión sobrevive a guardarse y leerse del almacenamiento', () {
    final session = Session.fromAuthResponse({
      'tokens': {
        'accessToken': 'a',
        'refreshToken': 'r',
        'accessTokenExpiresAt': '2030-01-01T00:00:00Z',
      },
      'user': {
        'userId': 'u1',
        'email': 'docente@demo.hn',
        'fullName': 'Docente Demo',
        'role': 'Docente',
        'mustChangePassword': false,
      },
    });

    final restored = Session.fromJson(session.toJson());

    expect(restored.email, 'docente@demo.hn');
    expect(restored.refreshToken, 'r');
    expect(restored.isExpired, isFalse);
  });
}
