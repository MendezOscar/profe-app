import 'package:flutter_test/flutter_test.dart';
import 'package:profeapp/core/local/clases_repository.dart';
import 'package:profeapp/core/local/local_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../sace/xlsx_de_prueba.dart';

void main() {
  sqfliteFfiInit();

  late Database db;
  late ClasesRepository repo;

  setUp(() async {
    db = await LocalDb.openAt(databaseFactoryFfi, inMemoryDatabasePath);
    repo = ClasesRepository(Future.value(db));
  });

  tearDown(() => db.close());

  test('Importar crea la clase con sus alumnos y lo que el cuadro ya traía', () async {
    final resultado = await repo.importar(cuadroMedia(), 'cuadro.xlsx');
    final clase = await repo.detalle(resultado.claseId);

    expect(resultado.nueva, isTrue);
    expect(clase.resumen.asignatura, 'LENGUA Y LITERATURA');
    expect(clase.alumnos, hasLength(3));
    expect(clase.columnas, hasLength(6));
    expect(clase.valores[clase.alumnos[1].id]?['PARCIAL I|NIVELACION'], 10);
  });

  test('Reimportar la plantilla con una columna nueva conserva lo capturado en el teléfono', () async {
    final primera = await repo.importar(cuadroMedia(), 'cuadro.xlsx');
    var clase = await repo.detalle(primera.claseId);
    final adriana = clase.alumnos.first;
    final jheimy = clase.alumnos.last;

    // El docente corrige una nota que venía en el archivo y llena una que venía vacía.
    await repo.guardarValor(adriana.id, 'PARCIAL II|NOTA TOTAL', 85);
    await repo.guardarValor(jheimy.id, 'PARCIAL I|NOTA TOTAL', 77);

    final segunda = await repo.importar(cuadroMedia(conNivelacionParcial2: true), 'cuadro-v2.xlsx');
    clase = await repo.detalle(segunda.claseId);

    expect(segunda.claseId, primera.claseId);
    expect(segunda.nueva, isFalse);
    expect(segunda.columnasNuevas, ['PARCIAL II · NIVELACIÓN']);
    expect(clase.columnas, hasLength(7));
    expect(clase.valores[adriana.id]?['PARCIAL II|NOTA TOTAL'], 85, reason: 'lo del teléfono manda');
    expect(clase.valores[jheimy.id]?['PARCIAL I|NOTA TOTAL'], 77);
    expect(await repo.listar(), hasLength(1));
  });

  test('Borrar un valor deja la celda vacía', () async {
    final resultado = await repo.importar(cuadroMedia(), 'cuadro.xlsx');
    final alumno = (await repo.detalle(resultado.claseId)).alumnos.first;

    await repo.guardarValor(alumno.id, 'PARCIAL I|NOTA TOTAL', null);

    final clase = await repo.detalle(resultado.claseId);
    expect(clase.valores[alumno.id]?.containsKey('PARCIAL I|NOTA TOTAL'), isFalse);
  });
}
