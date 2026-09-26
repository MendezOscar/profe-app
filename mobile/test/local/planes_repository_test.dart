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
