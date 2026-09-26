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

  // ── Plan de calificación ─────────────────────────────────────────────────
  // Cada fila viaja como un registro {tipo, claseClave, clave, datos} y se resuelve por
  // separado: gana el cambio más nuevo. Las notas y la asistencia se cruzan por la clave
  // del alumno, como los valores del cuadro.

  /// Orden para aplicar: primero lo que otros registros necesitan que exista.
  static const _tipos = ['plantilla', 'rubro', 'actividad', 'sesion', 'parcial', 'calificacion', 'asistencia'];

  /// Filas del plan sin subir, cada una con lo necesario para marcarla subida después.
  Future<List<RegistroPendiente>> registrosPendientes() async {
    final db = await _db;
    final pendientes = <RegistroPendiente>[];
    void agregar(String tabla, Map<String, Object?> llave, Map<String, Object?> fila, String tipo, String claseClave,
        String clave, Map<String, Object?> datos, bool eliminado) {
      final cuando = fila['actualizado_en'] as String;
      pendientes.add((
        tabla: tabla,
        llave: llave,
        actualizadoEn: cuando,
        json: {
          'tipo': tipo,
          'claseClave': claseClave,
          'clave': clave,
          'datos': jsonEncode(datos),
          'eliminado': eliminado,
          'actualizadoEn': _utc(cuando),
        },
      ));
    }

    for (final r in await db.query('plantillas', where: 'sucia = 1')) {
      agregar('plantillas', {'id': r['id']}, r, 'plantilla', '', r['id'] as String,
          {'nombre': r['nombre'], 'rubros': jsonDecode(r['rubros_json'] as String)}, r['eliminado'] == 1);
    }
    for (final r in await db.rawQuery(
        'SELECT x.*, c.clave AS clase_clave FROM rubros x JOIN clases c ON c.id = x.clase_id WHERE x.sucia = 1')) {
      agregar('rubros', {'id': r['id']}, r, 'rubro', r['clase_clave'] as String, r['id'] as String,
          {'parcial': r['parcial'], 'nombre': r['nombre'], 'puntos': r['puntos'], 'orden': r['orden']}, r['eliminado'] == 1);
    }
    for (final r in await db.rawQuery(
        'SELECT x.*, c.clave AS clase_clave FROM actividades x JOIN clases c ON c.id = x.clase_id WHERE x.sucia = 1')) {
      agregar('actividades', {'id': r['id']}, r, 'actividad', r['clase_clave'] as String, r['id'] as String, {
        'parcial': r['parcial'],
        'rubroId': r['rubro_id'],
        'titulo': r['titulo'],
        'fecha': r['fecha'],
        'puntos': r['puntos'],
        'descripcion': r['descripcion'],
      }, r['eliminado'] == 1);
    }
    for (final r in await db.rawQuery(
        'SELECT x.*, c.clave AS clase_clave FROM sesiones x JOIN clases c ON c.id = x.clase_id WHERE x.sucia = 1')) {
      agregar('sesiones', {'id': r['id']}, r, 'sesion', r['clase_clave'] as String, r['id'] as String,
          {'parcial': r['parcial'], 'fecha': r['fecha']}, r['eliminado'] == 1);
    }
    for (final r in await db.rawQuery(
        'SELECT x.*, c.clave AS clase_clave FROM parciales x JOIN clases c ON c.id = x.clase_id WHERE x.sucia = 1')) {
      agregar('parciales', {'clase_id': r['clase_id'], 'parcial': r['parcial']}, r, 'parcial', r['clase_clave'] as String,
          r['parcial'] as String, {'cerradoEn': r['cerrado_en']}, false);
    }
    for (final r in await db.rawQuery('''
        SELECT x.*, a.clave AS alumno_clave, c.clave AS clase_clave FROM calificaciones x
        JOIN alumnos a ON a.id = x.alumno_id JOIN clases c ON c.id = a.clase_id WHERE x.sucia = 1''')) {
      agregar('calificaciones', {'actividad_id': r['actividad_id'], 'alumno_id': r['alumno_id']}, r, 'calificacion',
          r['clase_clave'] as String, '${r['actividad_id']}|${r['alumno_clave']}', {'valor': r['valor']}, r['valor'] == null);
    }
    for (final r in await db.rawQuery('''
        SELECT x.*, a.clave AS alumno_clave, c.clave AS clase_clave FROM asistencias x
        JOIN alumnos a ON a.id = x.alumno_id JOIN clases c ON c.id = a.clase_id WHERE x.sucia = 1''')) {
      agregar('asistencias', {'sesion_id': r['sesion_id'], 'alumno_id': r['alumno_id']}, r, 'asistencia',
          r['clase_clave'] as String, '${r['sesion_id']}|${r['alumno_clave']}', {'estado': r['estado']}, r['estado'] == null);
    }
    return pendientes;
  }

  /// Tras subirlos. Si la fila cambió mientras tanto (otro actualizado_en), queda sucia.
  Future<void> marcarRegistrosSubidos(Iterable<RegistroPendiente> subidos) async {
    final db = await _db;
    await db.transaction((tx) async {
      for (final r in subidos) {
        final where = [...r.llave.keys.map((k) => '$k = ?'), 'actualizado_en = ?'].join(' AND ');
        await tx.update(r.tabla, {'sucia': 0}, where: where, whereArgs: [...r.llave.values, r.actualizadoEn]);
      }
    });
  }

  /// Mezcla los registros bajados. Lo que no tiene dónde ir (clase o alumno que este
  /// teléfono no tiene) se ignora.
  Future<void> aplicarRegistros(List<Map<String, dynamic>> registros) async {
    if (registros.isEmpty) return;
    final ordenados = [...registros]
      ..sort((a, b) => _tipos.indexOf(a['tipo'] as String).compareTo(_tipos.indexOf(b['tipo'] as String)));
    final db = await _db;
    await db.transaction((tx) async {
      final clases = <String, String?>{};
      Future<String?> claseId(String clave) async {
        if (clases.containsKey(clave)) return clases[clave];
        final fila = await tx.query('clases', columns: ['id'], where: 'clave = ?', whereArgs: [clave]);
        return clases[clave] = fila.firstOrNull?['id'] as String?;
      }

      Future<String?> alumnoId(String claseId, String clave) async => (await tx.query('alumnos',
              columns: ['id'], where: 'clase_id = ? AND clave = ?', whereArgs: [claseId, clave]))
          .firstOrNull?['id'] as String?;

      for (final r in ordenados) {
        final tipo = r['tipo'] as String;
        final clave = r['clave'] as String;
        final cuando = DateTime.parse(r['actualizadoEn'] as String).toUtc().toIso8601String();
        final eliminado = r['eliminado'] == true ? 1 : 0;
        final datos =
            r['datos'] == null ? const <String, dynamic>{} : jsonDecode(r['datos'] as String) as Map<String, dynamic>;
        final sync = {'actualizado_en': cuando, 'sucia': 0};

        if (tipo == 'plantilla') {
          await _mezclar(tx, 'plantillas', {'id': clave}, cuando, {
            'nombre': datos['nombre'] ?? '',
            'rubros_json': jsonEncode(datos['rubros'] ?? const []),
            'eliminado': eliminado,
            ...sync,
          });
          continue;
        }

        final clase = await claseId(r['claseClave'] as String);
        if (clase == null) continue;
        switch (tipo) {
          case 'rubro':
            await _mezclar(tx, 'rubros', {'id': clave}, cuando, {
              'clase_id': clase,
              'parcial': datos['parcial'],
              'nombre': datos['nombre'],
              'puntos': datos['puntos'],
              'orden': datos['orden'],
              'eliminado': eliminado,
              ...sync,
            });
          case 'actividad':
            await _mezclar(tx, 'actividades', {'id': clave}, cuando, {
              'clase_id': clase,
              'parcial': datos['parcial'],
              'rubro_id': datos['rubroId'],
              'titulo': datos['titulo'],
              'fecha': datos['fecha'],
              'puntos': datos['puntos'],
              'descripcion': datos['descripcion'],
              'eliminado': eliminado,
              ...sync,
            });
          case 'sesion':
            await _mezclar(tx, 'sesiones', {'id': clave}, cuando, {
              'clase_id': clase,
              'parcial': datos['parcial'],
              'fecha': datos['fecha'],
              'eliminado': eliminado,
              ...sync,
            });
          case 'parcial':
            await _mezclar(tx, 'parciales', {'clase_id': clase, 'parcial': clave}, cuando,
                {'cerrado_en': datos['cerradoEn'], ...sync});
          case 'calificacion' || 'asistencia':
            final corte = clave.indexOf('|');
            if (corte < 0) continue;
            final padre = clave.substring(0, corte);
            final alumno = await alumnoId(clase, clave.substring(corte + 1));
            if (alumno == null) continue;
            final (tabla, columnaPadre, tablaPadre, valor) = tipo == 'calificacion'
                ? ('calificaciones', 'actividad_id', 'actividades', {'valor': datos['valor']})
                : ('asistencias', 'sesion_id', 'sesiones', {'estado': datos['estado']});
            // Sin la actividad o la lista a la que pertenece no se puede guardar (llave foránea).
            if ((await tx.query(tablaPadre, columns: ['id'], where: 'id = ?', whereArgs: [padre])).isEmpty) continue;
            await _mezclar(tx, tabla, {columnaPadre: padre, 'alumno_id': alumno}, cuando, {...valor, ...sync});
        }
      }
    });
  }

  /// Gana el más nuevo. Actualiza en su lugar para no borrar en cascada lo que cuelga de la fila.
  static Future<void> _mezclar(
      Transaction tx, String tabla, Map<String, Object?> llave, String cuando, Map<String, Object?> fila) async {
    final where = llave.keys.map((k) => '$k = ?').join(' AND ');
    final actual = await tx.query(tabla, columns: ['actualizado_en'], where: where, whereArgs: llave.values.toList());
    if (actual.isEmpty) {
      await tx.insert(tabla, {...llave, ...fila});
    } else if (DateTime.parse(cuando).isAfter(DateTime.parse(actual.first['actualizado_en'] as String))) {
      await tx.update(tabla, fila, where: where, whereArgs: llave.values.toList());
    }
  }
}

/// Una fila del plan lista para subir y cómo reconocerla al marcarla subida.
typedef RegistroPendiente = ({
  String tabla,
  Map<String, Object?> llave,
  String actualizadoEn,
  Map<String, dynamic> json,
});
