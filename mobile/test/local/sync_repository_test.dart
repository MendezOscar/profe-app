import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:profeapp/core/local/clases_repository.dart';
import 'package:profeapp/core/local/local_db.dart';
import 'package:profeapp/core/local/sync_repository.dart';
import 'package:profeapp/core/planes/modelos.dart';
import 'package:profeapp/core/planes/planes_repository.dart';
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

  test('Tras el primer push sólo viajan las celdas que cambiaron, sin la plantilla', () async {
    final importada = await clasesA.importar(cuadroMedia(), 'QUIMICA.xls');
    final primero = (await syncA.pendientes()).single;
    expect(primero.json['conPlantilla'], isTrue);
    expect(primero.celdas, isNotEmpty, reason: 'lo que traía el cuadro');
    await syncA.marcarSubida(primero.id, primero.version, primero.celdas);

    final alumno = (await clasesA.detalle(importada.claseId)).alumnos.first;
    await clasesA.guardarValor(alumno.id, 'PARCIAL I|NOTA TOTAL', 60);
    final segundo = (await syncA.pendientes()).single;

    expect(segundo.json['conPlantilla'], isFalse);
    expect(segundo.json['alumnos'], isEmpty);
    expect(segundo.json['valores'], hasLength(1));
    expect((segundo.json['valores'] as List).single['valor'], 60);
  });

  test('Una clase que llega sin plantilla actualiza las celdas sin tocar alumnos ni columnas', () async {
    final importada = await clasesA.importar(cuadroMedia(), 'QUIMICA.xls');
    final completa = (await syncA.pendientes()).single;
    await syncB.aplicar({...completa.json, 'archivoBase64': completa.json['archivoBase64']});
    final alumno = (await clasesA.detalle(importada.claseId)).alumnos.first;
    await syncA.marcarSubida(completa.id, completa.version, completa.celdas);
    await clasesA.guardarValor(alumno.id, 'PARCIAL II|NOTA TOTAL', 99);

    final parcial = (await syncA.pendientes()).single.json;
    expect(await syncB.necesitaArchivo(parcial), isFalse);
    await syncB.aplicar(parcial);

    final claseB = (await clasesB.listar()).single;
    final detalleB = await clasesB.detalle(claseB.id);
    expect(detalleB.alumnos, hasLength(3));
    expect(detalleB.valores[detalleB.alumnos.first.id]?['PARCIAL II|NOTA TOTAL'], 99);
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

  test('El plan, las notas y la asistencia pasan de un teléfono al otro', () async {
    final planesA = PlanesRepository(Future.value(dbA), clasesA);
    final planesB = PlanesRepository(Future.value(dbB), clasesB);
    final claseA = (await clasesA.importar(cuadroMedia(), 'cuadro.xlsx')).claseId;
    final claseB = (await clasesB.importar(cuadroMedia(), 'cuadro.xlsx')).claseId;
    final parcialA = (await planesA.parciales(claseA)).first;

    final rubro = await planesA.guardarRubro(claseA, parcialA.clave, nombre: 'Examen', puntos: 100);
    final examen = await planesA.guardarActividad(claseA, parcialA.clave,
        rubroId: rubro, titulo: 'Examen', fecha: DateTime(2026, 3, 1), puntos: 100);
    final alumnoA = (await planesA.plan(claseA, parcialA)).alumnos.first;
    await planesA.calificar(examen, alumnoA.id, 88);
    final sesion = await planesA.sesion(claseA, parcialA.clave, DateTime(2026, 2, 2));
    await planesA.marcarAsistencia(sesion, alumnoA.id, EstadoAsistencia.ausente);
    await planesA.guardarPlantilla(nombre: 'Mi plan', rubros: const [RubroPlantilla('Todo', 100)]);

    final pendientes = await syncA.registrosPendientes();
    expect(pendientes.map((r) => r.json['tipo']).toSet(),
        {'plantilla', 'rubro', 'actividad', 'calificacion', 'sesion', 'asistencia'});

    // Al revés a propósito: la nota llega antes que su actividad.
    await syncB.aplicarRegistros([for (final r in pendientes.reversed) r.json]);
    await syncA.marcarRegistrosSubidos(pendientes);

    final planB = await planesB.plan(claseB, (await planesB.parciales(claseB)).first);
    final alumnoB = planB.alumnos.first;
    expect(planB.rubros.single.nombre, 'Examen');
    expect(planB.calificaciones[examen]?[alumnoB.id], 88);
    expect(planB.asistencias[sesion]?[alumnoB.id], EstadoAsistencia.ausente);
    expect((await planesB.plantillas()).first.nombre, 'Mi plan');
    expect(await syncA.registrosPendientes(), isEmpty);
    expect(await syncB.registrosPendientes(), isEmpty, reason: 'lo bajado no se vuelve a subir');
  });

  test('Por registro gana el cambio más nuevo', () async {
    final planesA = PlanesRepository(Future.value(dbA), clasesA);
    final planesB = PlanesRepository(Future.value(dbB), clasesB);
    final claseA = (await clasesA.importar(cuadroMedia(), 'cuadro.xlsx')).claseId;
    final claseB = (await clasesB.importar(cuadroMedia(), 'cuadro.xlsx')).claseId;
    final parcial = (await planesA.parciales(claseA)).first.clave;

    final rubro = await planesA.guardarRubro(claseA, parcial, nombre: 'Tareas', puntos: 40);
    final viejo = (await syncA.registrosPendientes()).single.json;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await planesB.guardarRubro(claseB, parcial, id: rubro, nombre: 'Tareas y trabajos', puntos: 50);

    await syncB.aplicarRegistros([viejo]);

    final rubroB = (await dbB.query('rubros', where: 'id = ?', whereArgs: [rubro])).single;
    expect(rubroB['nombre'], 'Tareas y trabajos');
    expect(rubroB['sucia'], 1, reason: 'el cambio local sigue pendiente de subir');
  });
}
