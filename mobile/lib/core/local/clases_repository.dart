import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/clase.dart';
import '../sace/cuadro_sace.dart';

/// Clases, alumnos y notas en la base del teléfono. Todo funciona sin red.
class ClasesRepository {
  ClasesRepository(this._db);

  final Future<Database> _db;
  static const _uuid = Uuid();

  /// Importa un cuadro descargado de SACE. Si la clase ya existe (el mismo cuadro bajado
  /// de nuevo), se actualiza la plantilla y se conserva lo capturado: lo del teléfono manda
  /// y lo que traiga el archivo sólo llena lo que estaba vacío.
  Future<ResultadoImportacion> importar(Uint8List bytes, String nombreArchivo) async {
    final cuadro = CuadroSace.fromBytes(bytes);
    final db = await _db;
    final now = DateTime.now().toIso8601String();

    return db.transaction((tx) async {
      final existente = await tx.query('clases', columns: ['id'], where: 'clave = ?', whereArgs: [cuadro.claveClase]);
      final nueva = existente.isEmpty;
      final claseId = nueva ? _uuid.v4() : existente.first['id'] as String;

      final datos = {
        'clave': cuadro.claveClase,
        'codigo_centro': cuadro.codigoCentro,
        'centro': cuadro.centro,
        'modalidad': cuadro.modalidad,
        'grado_seccion': cuadro.gradoSeccion,
        'jornada': cuadro.jornada,
        'asignatura': cuadro.asignatura,
        'hoja': cuadro.hoja,
        'archivo_nombre': nombreArchivo,
        'archivo': bytes,
        'actualizada_en': now,
      };
      if (nueva) {
        await tx.insert('clases', {'id': claseId, 'importada_en': now, ...datos});
      } else {
        await tx.update('clases', datos, where: 'id = ?', whereArgs: [claseId]);
      }

      final clavesAnteriores = (await tx.query('columnas', columns: ['clave'], where: 'clase_id = ?', whereArgs: [claseId]))
          .map((r) => r['clave'] as String)
          .toSet();
      await tx.delete('columnas', where: 'clase_id = ?', whereArgs: [claseId]);
      for (final (orden, columna) in cuadro.columnas.indexed) {
        await tx.insert('columnas', {
          'id': _uuid.v4(),
          'clase_id': claseId,
          'clave': columna.clave,
          'grupo': columna.grupo,
          'nombre': columna.nombre,
          'tipo': columna.tipo.name,
          'col': columna.col,
          'orden': orden,
        });
      }

      final alumnosPrevios = {
        for (final r in await tx.query('alumnos', columns: ['id', 'clave'], where: 'clase_id = ?', whereArgs: [claseId]))
          r['clave'] as String: r['id'] as String,
      };
      await tx.update('alumnos', {'activo': 0}, where: 'clase_id = ?', whereArgs: [claseId]);

      for (final (orden, alumno) in cuadro.alumnos.indexed) {
        final clave = alumno.identidad.isNotEmpty ? alumno.identidad : 'nombre:${normalizar(alumno.nombre)}';
        final fila = {
          'identidad': alumno.identidad,
          'documento': alumno.documento,
          'nombre': alumno.nombre,
          'fila': alumno.fila,
          'orden': orden,
          'activo': 1,
        };
        var alumnoId = alumnosPrevios[clave];
        if (alumnoId == null) {
          alumnoId = _uuid.v4();
          await tx.insert('alumnos', {'id': alumnoId, 'clase_id': claseId, 'clave': clave, ...fila});
        } else {
          await tx.update('alumnos', fila, where: 'id = ?', whereArgs: [alumnoId]);
        }

        for (final MapEntry(key: columnaClave, value: valor) in alumno.valores.entries) {
          await tx.insert(
            'valores',
            {'alumno_id': alumnoId, 'columna_clave': columnaClave, 'valor': valor, 'actualizado_en': now},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }

      return ResultadoImportacion(
        claseId: claseId,
        nueva: nueva,
        alumnos: cuadro.alumnos.length,
        columnasNuevas: nueva
            ? const []
            : [
                for (final c in cuadro.columnas)
                  if (!clavesAnteriores.contains(c.clave)) Columna(clave: c.clave, grupo: c.grupo, nombre: c.nombre, tipo: c.tipo).titulo,
              ],
      );
    });
  }

  Future<List<ClaseResumen>> listar() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT c.*, (SELECT COUNT(*) FROM alumnos a WHERE a.clase_id = c.id AND a.activo = 1) AS total_alumnos
      FROM clases c
      ORDER BY c.asignatura, c.grado_seccion''');
    return rows.map(_resumen).toList();
  }

  Future<ClaseDetalle> detalle(String claseId) async {
    final db = await _db;
    final clase = (await db.rawQuery('''
      SELECT c.*, (SELECT COUNT(*) FROM alumnos a WHERE a.clase_id = c.id AND a.activo = 1) AS total_alumnos
      FROM clases c WHERE c.id = ?''', [claseId])).first;

    final columnas = await db.query('columnas', where: 'clase_id = ?', whereArgs: [claseId], orderBy: 'orden');
    final alumnos =
        await db.query('alumnos', where: 'clase_id = ? AND activo = 1', whereArgs: [claseId], orderBy: 'orden');
    final valores = await db.rawQuery('''
      SELECT v.alumno_id, v.columna_clave, v.valor FROM valores v
      JOIN alumnos a ON a.id = v.alumno_id
      WHERE a.clase_id = ?''', [claseId]);

    final porAlumno = <String, Map<String, int>>{};
    for (final v in valores) {
      (porAlumno[v['alumno_id'] as String] ??= {})[v['columna_clave'] as String] = v['valor'] as int;
    }

    return ClaseDetalle(
      resumen: _resumen(clase),
      modalidad: clase['modalidad'] as String? ?? '',
      columnas: [
        for (final c in columnas)
          Columna(
            clave: c['clave'] as String,
            grupo: c['grupo'] as String,
            nombre: c['nombre'] as String,
            tipo: TipoColumna.values.byName(c['tipo'] as String),
          ),
      ],
      alumnos: [
        for (final a in alumnos)
          Alumno(id: a['id'] as String, identidad: a['identidad'] as String, nombre: a['nombre'] as String),
      ],
      valores: porAlumno,
    );
  }

  /// Null borra el valor: la celda vuelve a quedar vacía en el cuadro.
  Future<void> guardarValor(String alumnoId, String columnaClave, int? valor) async {
    final db = await _db;
    if (valor == null) {
      await db.delete('valores', where: 'alumno_id = ? AND columna_clave = ?', whereArgs: [alumnoId, columnaClave]);
      return;
    }
    await db.insert(
      'valores',
      {'alumno_id': alumnoId, 'columna_clave': columnaClave, 'valor': valor, 'actualizado_en': DateTime.now().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> eliminar(String claseId) async {
    final db = await _db;
    await db.delete('clases', where: 'id = ?', whereArgs: [claseId]);
  }

  ClaseResumen _resumen(Map<String, Object?> r) => ClaseResumen(
        id: r['id'] as String,
        asignatura: r['asignatura'] as String? ?? 'Clase sin nombre',
        gradoSeccion: r['grado_seccion'] as String? ?? '',
        jornada: r['jornada'] as String? ?? '',
        centro: r['centro'] as String? ?? '',
        alumnos: r['total_alumnos'] as int? ?? 0,
        actualizadaEn: DateTime.parse(r['actualizada_en'] as String),
      );
}
