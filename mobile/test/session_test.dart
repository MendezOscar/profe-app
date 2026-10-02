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
        'cobro': {
          'estado': 'soloLectura',
          'mensaje': 'ProfeApp quedó de solo lectura.',
          'pagadoHasta': '2026-01-31',
          'diasGracia': 5,
          'nivel': 'basico',
          'topeAsignaturas': 3,
        },
      },
    });

    final restored = Session.fromJson(session.toJson());

    expect(restored.email, 'docente@demo.hn');
    expect(restored.refreshToken, 'r');
    expect(restored.isExpired, isFalse);
    expect(restored.cobro?.soloLectura, isTrue);
    expect(restored.cobro?.pagadoHasta, DateTime(2026, 1, 31));
    expect(restored.cobro?.topeAsignaturas, 3);
  });
}
