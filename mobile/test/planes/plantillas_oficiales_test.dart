import 'package:flutter_test/flutter_test.dart';
import 'package:profeapp/core/planes/modelos.dart';

void main() {
  test('Lee el grado del encabezado de SACE', () {
    expect(gradoDe('TERCER GRADO SECCIÓN 1'), 3);
    expect(gradoDe('SÉPTIMO GRADO SECCIÓN A'), 7);
    expect(gradoDe('DÉCIMO GRADO SECCIÓN 2'), 10);
    expect(gradoDe('ONCEAVO GRADO SECCIÓN 12'), 11);
    expect(gradoDe('UNDÉCIMO GRADO'), 11);
    expect(gradoDe('DUODÉCIMO GRADO SECCIÓN 1'), 12);
    expect(gradoDe('5° GRADO'), 5);
    expect(gradoDe(''), isNull);
  });

  test('Recomienda la tabla del Acuerdo 0158 de cada ciclo, y todas suman 100', () {
    expect(Plantilla.oficialPara('PRIMER GRADO SECCIÓN 1')?.id, 'pre:0158-b1');
    expect(Plantilla.oficialPara('SEXTO GRADO SECCIÓN 1')?.id, 'pre:0158-b2');
    expect(Plantilla.oficialPara('NOVENO GRADO SECCIÓN 1')?.id, 'pre:0158-b3');
    expect(Plantilla.oficialPara('DÉCIMO GRADO SECCIÓN 2')?.id, 'pre:0158-m');
    expect(Plantilla.oficialPara('SECCIÓN ÚNICA'), isNull);
    for (final p in Plantilla.oficiales) {
      expect(p.total, 100, reason: p.nombre);
    }
  });
}
