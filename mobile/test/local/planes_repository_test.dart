import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:profeapp/core/local/clases_repository.dart';
import 'package:profeapp/core/local/local_db.dart';
import 'package:profeapp/core/planes/modelos.dart';
import 'package:profeapp/core/planes/planes_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../sace/xlsx_de_prueba.dart';

void main() {
  sqfliteFfiInit();

  late Database db;
  late ClasesRepository clases;
  late PlanesRepository planes;

  setUp(() async {
    db = await LocalDb.openAt(databaseFactoryFfi, inMemoryDatabasePath);
    clases = ClasesRepository(Future.value(db));
    planes = PlanesRepository(Future.value(db), clases);
  });

  tearDown(() => db.close());

  test('Los parciales salen de los grupos del cuadro, sin RECUPERACIÓN', () async {
    final claseId = (await clases.importar(cuadroMedia(), 'cuadro.xlsx')).claseId;

    final parciales = await planes.parciales(claseId);

    expect(parciales.map((p) => p.clave), ['PARCIAL I', 'PARCIAL II']);
    expect(parciales.first.notaClave, 'PARCIAL I|NOTA TOTAL');
    expect(parciales.first.inasistenciasClave, 'PARCIAL I|INASISTENCIAS');
  });

  test('Aplicar una plantilla no pisa un plan en marcha', () async {
    final claseId = (await clases.importar(cuadroMedia(), 'cuadro.xlsx')).claseId;
    final rubros = Plantilla.prearmadas.first.rubros;

    expect(await planes.aplicarPlantilla(claseId, ['PARCIAL I'], rubros), 1);
    expect(await planes.aplicarPlantilla(claseId, ['PARCIAL I', 'PARCIAL II'], rubros), 1);
    expect(await planes.copiarPlan(claseId, desde: 'PARCIAL I', hacia: 'PARCIAL II'), isFalse);

    final parcial = (await planes.parciales(claseId)).first;
    final plan = await planes.plan(claseId, parcial);
    expect(plan.rubros.map((r) => r.nombre), rubros.map((r) => r.nombre));
  });

  test('Cerrar el parcial deja nota e inasistencias en el cuadro para exportar', () async {
    final claseId = (await clases.importar(cuadroMedia(), 'cuadro.xlsx')).claseId;
    final parcial = (await planes.parciales(claseId)).first;
    final rubroId = await planes.guardarRubro(claseId, parcial.clave, nombre: 'Examen', puntos: 100);
    final examen = await planes.guardarActividad(claseId, parcial.clave,
        rubroId: rubroId, titulo: 'Examen', fecha: DateTime(2026, 3, 1), puntos: 100);

    var plan = await planes.plan(claseId, parcial);
    final alumno = plan.alumnos.first;
    await planes.calificar(examen, alumno.id, 86.5);
    final sesion = await planes.sesion(claseId, parcial.clave, DateTime(2026, 2, 2));
    await planes.marcarAsistencia(sesion, alumno.id, EstadoAsistencia.ausente);

    plan = await planes.plan(claseId, parcial);
    await planes.cerrar(plan);

    final cuadro = await clases.detalle(claseId);
    expect(cuadro.valores[alumno.id]?['PARCIAL I|NOTA TOTAL'], 87);
    expect(cuadro.valores[alumno.id]?['PARCIAL I|INASISTENCIAS'], 1);
    expect((await planes.plan(claseId, parcial)).cerrado, isTrue);
  });

  test('Editar una actividad conserva sus notas; borrarla las saca del cálculo', () async {
    final claseId = (await clases.importar(cuadroMedia(), 'cuadro.xlsx')).claseId;
    final parcial = (await planes.parciales(claseId)).first;
    final rubroId = await planes.guardarRubro(claseId, parcial.clave, nombre: 'Tareas', puntos: 40);
    final tarea = await planes.guardarActividad(claseId, parcial.clave,
        rubroId: rubroId, titulo: 'Tarea', fecha: DateTime(2026, 2, 1), puntos: 10);
    final alumno = (await planes.plan(claseId, parcial)).alumnos.first;
    await planes.calificar(tarea, alumno.id, 9);

    await planes.guardarActividad(claseId, parcial.clave,
        id: tarea, rubroId: rubroId, titulo: 'Tarea 1', fecha: DateTime(2026, 2, 1), puntos: 10);
    var plan = await planes.plan(claseId, parcial);
    expect(plan.actividades.single.titulo, 'Tarea 1');
    expect(plan.calificaciones[tarea]?[alumno.id], 9);
    expect(await planes.eliminarRubro(rubroId), isFalse, reason: 'tiene actividades');

    await planes.eliminarActividad(tarea);
    plan = await planes.plan(claseId, parcial);
    expect(plan.actividades, isEmpty);
    expect(plan.calificaciones, isEmpty);

    await planes.restaurarActividad(tarea);
    expect((await planes.plan(claseId, parcial)).calificaciones[tarea]?[alumno.id], 9);
  });

  test('Una actividad se puede crear en otras secciones que tengan el mismo rubro', () async {
    final a = (await clases.importar(cuadroMedia(seccion: 1), 'a.xlsx')).claseId;
    final b = (await clases.importar(cuadroMedia(seccion: 2), 'b.xlsx')).claseId;
    final c = (await clases.importar(cuadroMedia(seccion: 3), 'c.xlsx')).claseId;
    await planes.guardarRubro(a, 'PARCIAL I', nombre: 'Tareas', puntos: 40);
    final tareasB = await planes.guardarRubro(b, 'PARCIAL I', nombre: ' tareas ', puntos: 30);
    await planes.guardarRubro(c, 'PARCIAL I', nombre: 'Exámenes', puntos: 40);
    await planes.guardarRubro(c, 'PARCIAL II', nombre: 'Tareas', puntos: 40);

    expect(await planes.rubrosIguales(a, 'PARCIAL I', 'Tareas'), {b: tareasB},
        reason: 'sin mayúsculas ni espacios de más; ni otro rubro ni otro parcial');
  });

  test('El calendario junta las actividades de todas las clases y cuenta lo calificado', () async {
    final a = (await clases.importar(cuadroMedia(seccion: 1), 'a.xlsx')).claseId;
    final b = (await clases.importar(cuadroMedia(seccion: 2), 'b.xlsx')).claseId;
    final ra = await planes.guardarRubro(a, 'PARCIAL I', nombre: 'Tareas', puntos: 40);
    final rb = await planes.guardarRubro(b, 'PARCIAL I', nombre: 'Tareas', puntos: 40);
    final t1 = await planes.guardarActividad(a, 'PARCIAL I', rubroId: ra, titulo: 'Tarea 1', fecha: DateTime(2026, 3, 3), puntos: 10);
    await planes.guardarActividad(b, 'PARCIAL I', rubroId: rb, titulo: 'Tarea 1', fecha: DateTime(2026, 3, 5), puntos: 10);
    await planes.guardarActividad(b, 'PARCIAL I', rubroId: rb, titulo: 'Fuera', fecha: DateTime(2026, 3, 12), puntos: 10);
    final alumnos = (await clases.detalle(a)).alumnos;
    for (final al in alumnos) {
      await planes.calificar(t1, al.id, 8);
    }

    final semana = await planes.calendario(DateTime(2026, 3, 2), DateTime(2026, 3, 8));

    expect(semana.map((x) => x.titulo), ['Tarea 1', 'Tarea 1']);
    expect(semana.first.calificada, isTrue);
    expect(semana.last.calificados, 0);
  });

  test('Una base v5 sube a v6 con equipos y observaciones', () async {
    final ruta = '${Directory.systemTemp.createTempSync('v5').path}/v5.db';
    final v5 = await databaseFactoryFfi.openDatabase(ruta, options: OpenDatabaseOptions(version: 5, onCreate: (db, _) async {
      await db.execute('CREATE TABLE clases (id TEXT PRIMARY KEY)');
      await db.execute('CREATE TABLE alumnos (id TEXT PRIMARY KEY)');
    }));
    await v5.close();

    final v6 = await LocalDb.openAt(databaseFactoryFfi, ruta);
    final tablas = (await v6.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'")).map((t) => t['name']);
    await v6.close();

    expect(tablas, containsAll(['equipos', 'observaciones']));
  });

  test('Una base v2 sube a v3 con las tablas del plan', () async {
    final path = '${(await databaseFactoryFfi.getDatabasesPath())}/v2_${DateTime.now().microsecondsSinceEpoch}.db';
    final vieja = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) => db.execute('CREATE TABLE clases (id TEXT PRIMARY KEY)'),
        ));
    await vieja.close();

    final nueva = await LocalDb.openAt(databaseFactoryFfi, path);
    final tablas = (await nueva.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'")).map((r) => r['name']);
    await nueva.close();
    await databaseFactoryFfi.deleteDatabase(path);

    expect(tablas, containsAll(['plantillas', 'rubros', 'actividades', 'calificaciones', 'sesiones', 'asistencias', 'parciales']));
  });
}
