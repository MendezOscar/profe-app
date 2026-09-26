import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:profeapp/core/sace/cuadro_sace.dart';
import 'package:profeapp/core/sace/hoja.dart';

import 'xlsx_de_prueba.dart';

void main() {
  group('Cuadro de media (2 parciales, nivelación)', () {
    final cuadro = CuadroSace.fromBytes(cuadroMedia());

    test('lee el encabezado de la clase', () {
      expect(cuadro.codigoCentro, '080100642M02');
      expect(cuadro.centro, 'ESPANA JESUS MILLA SELVA');
      expect(cuadro.modalidad, 'BACHILLERATO TÉCNICO PROFESIONAL EN CONTADURÍA Y FINANZAS');
      expect(cuadro.gradoSeccion, 'ONCEAVO GRADO SECCIÓN 12');
      expect(cuadro.jornada, 'JORNADA VESPERTINA');
      expect(cuadro.asignatura, 'LENGUA Y LITERATURA');
    });

    test('descubre las columnas que trae la plantilla, con su tipo', () {
      expect(
        cuadro.columnas.map((c) => '${c.grupo} / ${c.nombre} / ${c.tipo.name} / ${c.col}'),
        [
          'PARCIAL I / INASISTENCIAS / inasistencias / 3',
          'PARCIAL I / NOTA TOTAL / nota / 4',
          'PARCIAL I / NIVELACIÓN / nivelacion / 5',
          'PARCIAL II / INASISTENCIAS / inasistencias / 6',
          'PARCIAL II / NOTA TOTAL / nota / 7',
          'RECUPERACIÓN / RECUPERACIÓN / nota / 8',
        ],
      );
    });

    test('lee los alumnos hasta el fin del documento, con lo que ya traían lleno', () {
      expect(cuadro.alumnos.map((a) => a.identidad), ['0801200101758', '0000000164448', '0815199800344']);
      expect(cuadro.alumnos.first.fila, 7);

      final emely = cuadro.alumnos[1];
      expect(emely.valores['PARCIAL I|NIVELACION'], 10);
      expect(emely.valores['RECUPERACION|RECUPERACION'], 51);

      // Alumna sin notas: sólo trae las inasistencias en cero.
      expect(cuadro.alumnos[2].valores, {'PARCIAL I|INASISTENCIAS': 0, 'PARCIAL II|INASISTENCIAS': 0});
    });

    test('la misma clase con una columna nueva conserva su identidad', () {
      final conNivelacion = CuadroSace.fromBytes(cuadroMedia(conNivelacionParcial2: true));
      expect(conNivelacion.claveClase, cuadro.claveClase);
      expect(conNivelacion.columnas.map((c) => c.clave), contains('PARCIAL II|NIVELACION'));
      expect(conNivelacion.columnas.last.col, 9);
    });
  });

  test('Cuadro de básica: 4 parciales sin nivelación y la identidad que Excel volvió número', () {
    final cuadro = CuadroSace.fromBytes(xlsxDePrueba({
      'A2': 'MODALIDAD: NO APLICA',
      'A3': 'TERCER GRADO SECCIÓN 1',
      'A4': 'JORNADA MATUTINA',
      'A5': 'CIENCIAS NATURALES',
      'A6': 'DOCUMENTO', 'B6': 'IDENTIDAD', 'C6': 'NOMBRE',
      'D6': 'PARCIAL I', 'F6': 'PARCIAL II', 'H6': 'PARCIAL III', 'J6': 'PARCIAL IV', 'L6': 'RECUPERACIÓN',
      'D7': 'INASISTENCIAS', 'E7': 'NOTA TOTAL', 'F7': 'INASISTENCIAS', 'G7': 'NOTA TOTAL',
      'H7': 'INASISTENCIAS', 'I7': 'NOTA TOTAL', 'J7': 'INASISTENCIAS', 'K7': 'NOTA TOTAL',
      'A8': 'HND', 'B8': 502201300192, 'C8': 'AMY BELEN CASTELLANOS ROMERO', 'D8': 0, 'E8': 98,
      'A9': 'HND', 'B9': '0502201304451', 'C9': 'ANGIE ALESSANDRA ORELLANA ALVARADO', 'D9': 1, 'E9': 78,
    }, combinadas: ['A6:A7', 'B6:B7', 'C6:C7', 'D6:E6', 'F6:G6', 'H6:I6', 'J6:K6']));

    expect(cuadro.modalidad, 'NO APLICA');
    expect(cuadro.columnas, hasLength(9));
    expect(cuadro.columnas.last.clave, 'RECUPERACION|RECUPERACION');
    expect(cuadro.alumnos.first.identidad, '0502201300192');
    expect(cuadro.alumnos.first.valores['PARCIAL I|NOTA TOTAL'], 98);
  });

  group('Cuadro en .xls (el formato en que lo entrega SACE)', () {
    final cuadro = CuadroSace.fromBytes(File('test/fixtures/cuadro_basica.xls').readAsBytesSync());

    test('lee encabezado, columnas y el nombre de hoja que parece id de SACE', () {
      expect(cuadro.hoja, '12345678~1~1123');
      expect(cuadro.codigoCentro, '050100235M02');
      expect(cuadro.asignatura, 'QUÍMICA');
      expect(cuadro.gradoSeccion, 'DÉCIMO GRADO SECCIÓN 2');
      expect(cuadro.columnas, hasLength(9));
      expect(cuadro.columnas.last.clave, 'RECUPERACION|RECUPERACION');
    });

    test('lee alumnos con tildes y eñes, y las notas ya capturadas', () {
      expect(cuadro.alumnos.map((a) => a.nombre), ['ANA PRUEBA UNO', 'BETO PRUEBA DOS', 'CARLA PEÑA TRES']);
      expect(cuadro.alumnos[2].identidad, '0000000164448');
      expect(cuadro.alumnos[0].valores['PARCIAL I|NOTA TOTAL'], 81);
      expect(cuadro.alumnos[1].valores['PARCIAL I|INASISTENCIAS'], 1);
      // 72.5 se redondea: SACE sólo acepta enteros.
      expect(cuadro.alumnos[1].valores['PARCIAL I|NOTA TOTAL'], 73);
      expect(cuadro.alumnos[0].valores.containsKey('PARCIAL III|NOTA TOTAL'), isFalse);
    });
  });

  // Cuadro real descargado de SACE. No se sube al repo (trae datos de alumnos): la prueba
  // corre sólo en la máquina donde esté el archivo.
  final real = Directory('..').listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.xls'));
  test('Cuadro real de SACE (local)', () {
    for (final archivo in real) {
      final cuadro = CuadroSace.fromBytes(archivo.readAsBytesSync());
      expect(cuadro.columnas, isNotEmpty, reason: archivo.path);
      expect(cuadro.alumnos, isNotEmpty, reason: archivo.path);
      expect(cuadro.alumnos.every((a) => RegExp(r'^\d{13}$').hasMatch(a.identidad)), isTrue, reason: archivo.path);
    }
  }, skip: real.isEmpty ? 'No hay cuadros reales en la raíz del proyecto' : false);

  test('Un archivo dañado se rechaza con un mensaje para el docente', () {
    expect(
      () => CuadroSace.fromBytes(Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0, 0, 0, 0, 0])),
      throwsA(isA<FormatoNoSoportado>()),
    );
  });

  test('Un Excel que no es un cuadro de SACE se rechaza', () {
    expect(
      () => CuadroSace.fromBytes(xlsxDePrueba({'A1': 'Lista de compras', 'A2': 'Leche'})),
      throwsA(isA<FormatoNoSoportado>()),
    );
  });
}
