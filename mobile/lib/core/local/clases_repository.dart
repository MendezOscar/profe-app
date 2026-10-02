import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/clase.dart';
import '../sace/cuadro_sace.dart';

/// El plan del docente cubre [tope] asignaturas y ya las tiene todas.
class TopeAsignaturas implements Exception {
  TopeAsignaturas(this.tope);
  final int tope;

  @override
  String toString() => 'Tu plan cubre $tope secciones (asignatura por sección) y ya las tienes todas. '
      'Para agregar otra, primero elimina una o pasa a un plan mayor.';
}

/// Clases, alumnos y notas en la base del teléfono. Todo funciona sin red.
class ClasesRepository {
  ClasesRepository(this._db);

  final Future<Database> _db;
  static const _uuid = Uuid();

  /// Importa un cuadro descargado de SACE. Si la clase ya existe (el mismo cuadro bajado
  /// de nuevo), se actualiza la plantilla y se conserva lo capturado: lo del teléfono manda
  /// y lo que traiga el archivo sólo llena lo que estaba vacío.
  ///
  /// Con [tope] (el del plan del docente), una asignatura nueva o revivida que lo pase no
  /// se importa: lanza [TopeAsignaturas]. Actualizar las que ya tiene siempre se puede.
  Future<ResultadoImportacion> importar(Uint8List bytes, String nombreArchivo, {int? tope}) async {
    final cuadro = CuadroSace.fromBytes(bytes);
    final db = await _db;
    final now = ahoraUtc();

    return db.transaction((tx) async {
      final existente =
          await tx.query('clases', columns: ['id', 'eliminada'], where: 'clave = ?', whereArgs: [cuadro.claveClase]);
      final nueva = existente.isEmpty;
      final claseId = nueva ? _uuid.v4() : existente.first['id'] as String;
      if (tope != null && (nueva || existente.first['eliminada'] == 1)) {
        final activas = Sqflite.firstIntValue(await tx.rawQuery('SELECT count(*) FROM clases WHERE eliminada = 0')) ?? 0;
        if (activas >= tope) throw TopeAsignaturas(tope);
      }

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
        // Reimportar una clase borrada la revive.
        'eliminada': 0,
        'plantilla_sucia': 1,
      };
      if (nueva) {
        await tx.insert('clases', {'id': claseId, 'importada_en': now, ...datos});
      } else {
        await tx.update('clases', datos, where: 'id = ?', whereArgs: [claseId]);
      }
      await marcarSucia(tx, claseId);

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
      WHERE c.eliminada = 0
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
      WHERE a.clase_id = ? AND v.valor IS NOT NULL''', [claseId]);

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

  /// Null borra el valor: la celda vuelve a quedar vacía en el cuadro. El borrado se
  /// guarda como fila con valor NULL para poder avisarle al servidor.
  /// Varias celdas de una misma clase en una sola transacción (el cierre de un parcial).
  Future<void> guardarValores(String claseId, List<(String alumnoId, String columnaClave, int? valor)> celdas) async {
    final db = await _db;
    final ahora = ahoraUtc();
    await db.transaction((tx) async {
      final batch = tx.batch();
      for (final (alumnoId, columnaClave, valor) in celdas) {
        batch.insert(
          'valores',
          {'alumno_id': alumnoId, 'columna_clave': columnaClave, 'valor': valor, 'actualizado_en': ahora, 'sucia': 1},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      await marcarSucia(tx, claseId);
    });
  }

  Future<void> guardarValor(String alumnoId, String columnaClave, int? valor) async {
    final db = await _db;
    await db.transaction((tx) async {
      await tx.insert(
        'valores',
        {'alumno_id': alumnoId, 'columna_clave': columnaClave, 'valor': valor, 'actualizado_en': ahoraUtc(), 'sucia': 1},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final clase = await tx.query('alumnos', columns: ['clase_id'], where: 'id = ?', whereArgs: [alumnoId]);
      await marcarSucia(tx, clase.first['clase_id'] as String);
    });
  }

  /// Todas las celdas editables de los alumnos vigentes, con lo capturado o vacías: así
  /// una nota que el docente borró en el teléfono también queda borrada en el cuadro.
  Future<CuadroParaExportar> paraExportar(String claseId) async {
    final db = await _db;
    final clase = (await db.query('clases',
            columns: ['archivo', 'archivo_nombre', 'hoja'], where: 'id = ?', whereArgs: [claseId]))
        .first;
    final columnas = await db.query('columnas', where: 'clase_id = ?', whereArgs: [claseId], orderBy: 'orden');
    final alumnos = await db.query('alumnos',
        columns: ['id', 'fila'], where: 'clase_id = ? AND activo = 1', whereArgs: [claseId], orderBy: 'orden');
    final detalle = await this.detalle(claseId);

    final celdas = <({int fila, int col, int? valor})>[
      for (final a in alumnos)
        for (final c in columnas)
          (
            fila: a['fila'] as int,
            col: c['col'] as int,
            valor: detalle.valores[a['id']]?[c['clave']],
          ),
    ];

    // RECUPERACIÓN no cuenta: sólo la llevan los que reprueban.
    final faltantes = <String>[
      for (final c in detalle.columnas
          .where((c) => c.tipo == TipoColumna.nota && !normalizar(c.nombre).contains('RECUPERACION')))
        if (detalle.alumnos.where((a) => detalle.valores[a.id]?[c.clave] != null).length case final hechos
            when hechos > 0 && hechos < detalle.alumnos.length)
          '${c.titulo}: faltan ${detalle.alumnos.length - hechos}',
    ];

    return CuadroParaExportar(
      archivo: clase['archivo'] as Uint8List,
      nombreArchivo: clase['archivo_nombre'] as String,
      hoja: clase['hoja'] as String,
      celdas: celdas,
      faltantes: faltantes,
    );
  }

  /// Queda marcada hasta que el servidor se entere; ahí se borra de verdad.
  Future<void> eliminar(String claseId) async {
    final db = await _db;
    await db.transaction((tx) async {
      await tx.update('clases', {'eliminada': 1}, where: 'id = ?', whereArgs: [claseId]);
      await marcarSucia(tx, claseId);
    });
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

/// Pendiente de subir. La versión deja saber, al terminar un push, si hubo cambios
/// mientras tanto: en ese caso la clase sigue sucia.
Future<void> marcarSucia(DatabaseExecutor db, String claseId) =>
    db.rawUpdate('UPDATE clases SET sucia = 1, version = version + 1 WHERE id = ?', [claseId]);

/// Las horas se guardan en UTC: se comparan entre dispositivos para decidir qué captura gana.
String ahoraUtc() => DateTime.now().toUtc().toIso8601String();
