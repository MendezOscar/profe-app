import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:profeapp/core/local/clases_repository.dart';
import 'package:profeapp/core/local/local_db.dart';
import 'package:profeapp/core/local/sync_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../sace/xlsx_de_prueba.dart';

/// Dos teléfonos del mismo docente. El JSON del push tiene la misma forma que lo que
/// devuelve el pull, así que se lo pasa de uno a otro como si viniera del servidor.
void main() {
  sqfliteFfiInit();

  late Database dbA, dbB;
  late ClasesRepository clasesA, clasesB;
  late SyncRepository syncA, syncB;

  setUp(() async {
    // Archivos distintos: ':memory:' devolvería la misma base en las dos aperturas.
    final carpeta = Directory.systemTemp.createTempSync('profeapp_sync');
    dbA = await LocalDb.openAt(databaseFactoryFfi, p.join(carpeta.path, 'a.db'));
    dbB = await LocalDb.openAt(databaseFactoryFfi, p.join(carpeta.path, 'b.db'));
    clasesA = ClasesRepository(Future.value(dbA));
    clasesB = ClasesRepository(Future.value(dbB));
    syncA = SyncRepository(Future.value(dbA));
    syncB = SyncRepository(Future.value(dbB));
  });

  tearDown(() async {
    await dbA.close();
    await dbB.close();
  });

  test('Lo capturado en un teléfono llega al otro con su plantilla', () async {
    final importada = await clasesA.importar(cuadroMedia(), 'QUIMICA.xls');
    final adriana = (await clasesA.detalle(importada.claseId)).alumnos.first;
    await clasesA.guardarValor(adriana.id, 'PARCIAL II|NOTA TOTAL', 95);

    final pendiente = (await syncA.pendientes()).single;
    expect(pendiente.plantilla, isTrue);
    expect(pendiente.json['archivoBase64'], isNotNull);

    await syncB.aplicar(pendiente.json);
    final enB = await clasesB.listar();
    expect(enB, hasLength(1));
    final clase = await clasesB.detalle(enB.single.id);
    expect(clase.valores[clase.alumnos.first.id]?['PARCIAL II|NOTA TOTAL'], 95);
    expect(await syncB.pendientes(), isEmpty, reason: 'lo bajado no se vuelve a subir');
  });

  test('Después del push la clase queda al día y el archivo no se reenvía', () async {
    final importada = await clasesA.importar(cuadroMedia(), 'QUIMICA.xls');
    final primero = (await syncA.pendientes()).single;
    await syncA.marcarSubida(primero.id, primero.version);
    expect(await syncA.pendientes(), isEmpty);

    final alumno = (await clasesA.detalle(importada.claseId)).alumnos.first;
    await clasesA.guardarValor(alumno.id, 'PARCIAL I|NOTA TOTAL', 60);
    final segundo = (await syncA.pendientes()).single;
    expect(segundo.json['archivoBase64'], isNull);
  });

  test('Si hubo cambios durante el push, la clase sigue pendiente', () async {
    final importada = await clasesA.importar(cuadroMedia(), 'QUIMICA.xls');
    final enviado = (await syncA.pendientes()).single;
    final alumno = (await clasesA.detalle(importada.claseId)).alumnos.first;
    await clasesA.guardarValor(alumno.id, 'PARCIAL I|NOTA TOTAL', 61); // mientras se subía

    await syncA.marcarSubida(enviado.id, enviado.version);

    expect(await syncA.pendientes(), hasLength(1));
  });

  test('Una captura remota más vieja no pisa la local', () async {
    final importada = await clasesA.importar(cuadroMedia(), 'QUIMICA.xls');
    final viejo = (await syncA.pendientes()).single.json;
    final alumno = (await clasesA.detalle(importada.claseId)).alumnos.first;
    await clasesA.guardarValor(alumno.id, 'PARCIAL I|NOTA TOTAL', 99);

    // El valor que traía el archivo (72) llega del servidor con una hora anterior.
    await syncA.aplicar(viejo);

    final clase = await clasesA.detalle(importada.claseId);
    expect(clase.valores[alumno.id]?['PARCIAL I|NOTA TOTAL'], 99);
  });

  test('Borrar la clase avisa al servidor y recién ahí se elimina del teléfono', () async {
    final importada = await clasesA.importar(cuadroMedia(), 'QUIMICA.xls');
    await clasesA.eliminar(importada.claseId);
    expect(await clasesA.listar(), isEmpty);

    final pendiente = (await syncA.pendientes()).single;
    expect(pendiente.json['eliminada'], isTrue);
    await syncA.marcarSubida(pendiente.id, pendiente.version);

    expect(await dbA.query('clases'), isEmpty);
  });
}
