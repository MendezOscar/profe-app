import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'clases_repository.dart';

/// Lado local de la sincronización. Todo viaja por claves naturales (clase, identidad del
/// alumno, encabezado de columna): los id de cada teléfono nunca salen de él.
class SyncRepository {
  SyncRepository(this._db);

  final Future<Database> _db;
  static const _uuid = Uuid();
  static const _cursor = 'pull_hasta';

  /// Clases con cambios sin subir, en el formato que espera `POST /sync/push`.
  Future<List<({String id, int version, bool plantilla, Map<String, dynamic> json})>> pendientes() async {
    final db = await _db;
    final clases = await db.query('clases', where: 'sucia = 1');
    return [
      for (final c in clases)
        (
          id: c['id'] as String,
          version: c['version'] as int,
          plantilla: c['plantilla_sucia'] == 1,
          json: await _aJson(db, c),
        ),
    ];
  }

  Future<Map<String, dynamic>> _aJson(Database db, Map<String, Object?> c) async {
    final id = c['id'] as String;
    final eliminada = c['eliminada'] == 1;
    final columnas = eliminada ? const <Map<String, Object?>>[] : await db.query('columnas', where: 'clase_id = ?', whereArgs: [id]);
    final alumnos = eliminada ? const <Map<String, Object?>>[] : await db.query('alumnos', where: 'clase_id = ?', whereArgs: [id]);
    final valores = eliminada
        ? const <Map<String, Object?>>[]
        : await db.rawQuery('''
            SELECT a.clave AS alumno_clave, v.columna_clave, v.valor, v.actualizado_en
            FROM valores v JOIN alumnos a ON a.id = v.alumno_id
            WHERE a.clase_id = ?''', [id]);

    return {
      'clave': c['clave'],
      'codigoCentro': c['codigo_centro'],
      'centro': c['centro'],
      'modalidad': c['modalidad'],
      'gradoSeccion': c['grado_seccion'],
      'jornada': c['jornada'],
      'asignatura': c['asignatura'],
      'hoja': c['hoja'],
      'archivoNombre': c['archivo_nombre'],
      // El archivo sólo va si la plantilla cambió desde el último push: es lo que más pesa.
      'archivoBase64': c['plantilla_sucia'] == 1 && !eliminada ? base64Encode(c['archivo'] as Uint8List) : null,
      'plantillaActualizadaEn': _utc(c['actualizada_en']),
      'eliminada': eliminada,
      'columnas': [
        for (final col in columnas)
          {
            'clave': col['clave'],
            'grupo': col['grupo'],
            'nombre': col['nombre'],
            'tipo': col['tipo'],
            'col': col['col'],
            'orden': col['orden'],
          },
      ],
      'alumnos': [
        for (final a in alumnos)
          {
            'clave': a['clave'],
            'identidad': a['identidad'],
            'documento': a['documento'],
            'nombre': a['nombre'],
            'fila': a['fila'],
            'orden': a['orden'],
            'activo': a['activo'] == 1,
          },
      ],
      'valores': [
        for (final v in valores)
          {
            'alumnoClave': v['alumno_clave'],
            'columnaClave': v['columna_clave'],
            'valor': v['valor'],
            'actualizadoEn': _utc(v['actualizado_en']),
          },
      ],
    };
  }

  /// Tras un push exitoso. Si la clase cambió mientras se subía (otra versión), queda
  /// sucia para el próximo intento. Una clase borrada ya avisada se elimina de verdad.
  Future<void> marcarSubida(String claseId, int version) async {
    final db = await _db;
    await db.transaction((tx) async {
      final actual = await tx.query('clases', columns: ['version', 'eliminada'], where: 'id = ?', whereArgs: [claseId]);
      if (actual.isEmpty || actual.first['version'] != version) return;
      if (actual.first['eliminada'] == 1) {
        await tx.delete('clases', where: 'id = ?', whereArgs: [claseId]);
      } else {
        await tx.update('clases', {'sucia': 0, 'plantilla_sucia': 0}, where: 'id = ?', whereArgs: [claseId]);
      }
    });
  }

  Future<void> forzarPlantilla(String claseId) async {
    final db = await _db;
    await db.update('clases', {'plantilla_sucia': 1}, where: 'id = ?', whereArgs: [claseId]);
  }

  Future<String?> cursor() async {
    final db = await _db;
    final fila = await db.query('sync_estado', where: 'clave = ?', whereArgs: [_cursor]);
    return fila.isEmpty ? null : fila.first['valor'] as String;
  }

  Future<void> guardarCursor(String hasta) async {
    final db = await _db;
    await db.insert('sync_estado', {'clave': _cursor, 'valor': hasta}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Mezcla una clase bajada del servidor. Nunca pisa lo pendiente de subir de este
  /// teléfono en la plantilla, y por celda gana la captura más nueva.
  Future<void> aplicar(Map<String, dynamic> remota) async {
    final db = await _db;
    await db.transaction((tx) async {
      final clave = remota['clave'] as String;
      final existente = await tx.query('clases', where: 'clave = ?', whereArgs: [clave]);
      final local = existente.firstOrNull;

      if (remota['eliminada'] == true) {
        // Si acá hay cambios sin subir, se respetan: el push decidirá.
        if (local != null && local['sucia'] == 0) await tx.delete('clases', where: 'id = ?', whereArgs: [local['id']]);
        return;
      }

      final archivo = remota['archivoBase64'] as String?;
      final plantillaRemota = DateTime.parse(remota['plantillaActualizadaEn'] as String);
      String claseId;

      if (local == null) {
        if (archivo == null) return; // Sin archivo no se puede exportar: se espera a tenerlo.
        claseId = _uuid.v4();
        await tx.insert('clases', {
          'id': claseId,
          'clave': clave,
          ..._meta(remota, archivo),
          'importada_en': ahoraUtc(),
          'sucia': 0,
          'plantilla_sucia': 0,
        });
        await _reemplazarPlantilla(tx, claseId, remota);
      } else {
        claseId = local['id'] as String;
        final plantillaLocal = DateTime.parse(local['actualizada_en'] as String);
        if (archivo != null && local['plantilla_sucia'] == 0 && plantillaRemota.isAfter(plantillaLocal)) {
          await tx.update('clases', _meta(remota, archivo), where: 'id = ?', whereArgs: [claseId]);
          await _reemplazarPlantilla(tx, claseId, remota);
        }
      }

      final alumnos = {
        for (final a in await tx.query('alumnos', columns: ['id', 'clave'], where: 'clase_id = ?', whereArgs: [claseId]))
          a['clave'] as String: a['id'] as String,
      };
      for (final v in (remota['valores'] as List).cast<Map<String, dynamic>>()) {
        final alumnoId = alumnos[v['alumnoClave']];
        if (alumnoId == null) continue;
        final cuando = DateTime.parse(v['actualizadoEn'] as String).toUtc();
        final actual = await tx.query('valores',
            columns: ['actualizado_en'],
            where: 'alumno_id = ? AND columna_clave = ?',
            whereArgs: [alumnoId, v['columnaClave']]);
        if (actual.isNotEmpty && !cuando.isAfter(DateTime.parse(actual.first['actualizado_en'] as String))) continue;
        await tx.insert(
          'valores',
          {'alumno_id': alumnoId, 'columna_clave': v['columnaClave'], 'valor': v['valor'], 'actualizado_en': cuando.toIso8601String()},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Map<String, Object?> _meta(Map<String, dynamic> r, String archivo) => {
        'codigo_centro': r['codigoCentro'],
        'centro': r['centro'],
        'modalidad': r['modalidad'],
        'grado_seccion': r['gradoSeccion'],
        'jornada': r['jornada'],
        'asignatura': r['asignatura'],
        'hoja': r['hoja'],
        'archivo_nombre': r['archivoNombre'],
        'archivo': base64Decode(archivo),
        'actualizada_en': DateTime.parse(r['plantillaActualizadaEn'] as String).toUtc().toIso8601String(),
        'eliminada': 0,
      };

  Future<void> _reemplazarPlantilla(Transaction tx, String claseId, Map<String, dynamic> r) async {
    await tx.delete('columnas', where: 'clase_id = ?', whereArgs: [claseId]);
    for (final c in (r['columnas'] as List).cast<Map<String, dynamic>>()) {
      await tx.insert('columnas', {
        'id': _uuid.v4(),
        'clase_id': claseId,
        'clave': c['clave'],
        'grupo': c['grupo'],
        'nombre': c['nombre'],
        'tipo': c['tipo'],
        'col': c['col'],
        'orden': c['orden'],
      });
    }

    final previos = {
      for (final a in await tx.query('alumnos', columns: ['id', 'clave'], where: 'clase_id = ?', whereArgs: [claseId]))
        a['clave'] as String: a['id'] as String,
    };
    for (final a in (r['alumnos'] as List).cast<Map<String, dynamic>>()) {
      final fila = {
        'identidad': a['identidad'],
        'documento': a['documento'],
        'nombre': a['nombre'],
        'fila': a['fila'],
        'orden': a['orden'],
        'activo': a['activo'] == true ? 1 : 0,
      };
      final id = previos[a['clave']];
      if (id == null) {
        await tx.insert('alumnos', {'id': _uuid.v4(), 'clase_id': claseId, 'clave': a['clave'], ...fila});
      } else {
        await tx.update('alumnos', fila, where: 'id = ?', whereArgs: [id]);
      }
    }
  }

  static String _utc(Object? iso) => DateTime.parse(iso as String).toUtc().toIso8601String();
}
