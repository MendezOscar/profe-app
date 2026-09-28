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

  /// Clases con cambios sin subir, en el formato que espera `POST /sync/push`. Sólo va lo
  /// que cambió: la plantilla (columnas, alumnos, archivo) si se reimportó, y las celdas
  /// sucias. [PendienteClase.celdas] sirve para marcarlas subidas después.
  Future<List<PendienteClase>> pendientes() async {
    final db = await _db;
    final clases = await db.query('clases', where: 'sucia = 1');
    final pendientes = <PendienteClase>[];
    for (final c in clases) {
      final celdas = <({String alumnoId, String columnaClave, String actualizadoEn})>[];
      pendientes.add((
        id: c['id'] as String,
        version: c['version'] as int,
        plantilla: c['plantilla_sucia'] == 1,
        json: await _aJson(db, c, celdas),
        celdas: celdas,
      ));
    }
    return pendientes;
  }

  Future<Map<String, dynamic>> _aJson(
      Database db, Map<String, Object?> c, List<({String alumnoId, String columnaClave, String actualizadoEn})> celdas) async {
    final id = c['id'] as String;
    final eliminada = c['eliminada'] == 1;
    final conPlantilla = c['plantilla_sucia'] == 1 && !eliminada;
    final columnas = conPlantilla ? await db.query('columnas', where: 'clase_id = ?', whereArgs: [id]) : const <Map<String, Object?>>[];
    final alumnos = conPlantilla ? await db.query('alumnos', where: 'clase_id = ?', whereArgs: [id]) : const <Map<String, Object?>>[];
    final valores = eliminada
        ? const <Map<String, Object?>>[]
        : await db.rawQuery('''
            SELECT v.alumno_id, a.clave AS alumno_clave, v.columna_clave, v.valor, v.actualizado_en
            FROM valores v JOIN alumnos a ON a.id = v.alumno_id
            WHERE a.clase_id = ? AND v.sucia = 1''', [id]);
    for (final v in valores) {
      celdas.add((
        alumnoId: v['alumno_id'] as String,
        columnaClave: v['columna_clave'] as String,
        actualizadoEn: v['actualizado_en'] as String,
      ));
    }

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
      'conPlantilla': conPlantilla,
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
  Future<void> marcarSubida(String claseId, int version,
      [List<({String alumnoId, String columnaClave, String actualizadoEn})> celdas = const []]) async {
    final db = await _db;
    await db.transaction((tx) async {
      // Cada celda por su cuenta: si se volvió a editar mientras subía, queda sucia.
      final batch = tx.batch();
      for (final c in celdas) {
        batch.update('valores', {'sucia': 0},
            where: 'alumno_id = ? AND columna_clave = ? AND actualizado_en = ?',
            whereArgs: [c.alumnoId, c.columnaClave, c.actualizadoEn]);
      }
      await batch.commit(noResult: true);

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

  /// Si para mezclar esta clase hace falta su archivo (el pull no lo trae): clase nueva en
  /// este dispositivo, o una plantilla más nueva que la de aquí.
  Future<bool> necesitaArchivo(Map<String, dynamic> remota) async {
    if (remota['eliminada'] == true || remota['conPlantilla'] != true || remota['archivoBase64'] != null) return false;
    final db = await _db;
    final local = (await db.query('clases',
            columns: ['actualizada_en', 'plantilla_sucia'], where: 'clave = ?', whereArgs: [remota['clave']]))
        .firstOrNull;
    if (local == null) return true;
    return local['plantilla_sucia'] == 0 &&
        DateTime.parse(remota['plantillaActualizadaEn'] as String)
            .isAfter(DateTime.parse(local['actualizada_en'] as String));
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
      final conPlantilla = remota['conPlantilla'] as bool? ?? true;
      final plantillaRemota = DateTime.parse(remota['plantillaActualizadaEn'] as String);
      String claseId;

      if (local == null) {
        // Sin archivo no se puede exportar: se espera a tenerlo.
        if (archivo == null || !conPlantilla) return;
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
        if (archivo != null && conPlantilla && local['plantilla_sucia'] == 0 && plantillaRemota.isAfter(plantillaLocal)) {
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
          {
            'alumno_id': alumnoId,
            'columna_clave': v['columnaClave'],
            'valor': v['valor'],
            'actualizado_en': cuando.toIso8601String(),
            'sucia': 0,
          },
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
  ///
  /// Por lotes: las llaves y horas que ya existen se leen con unas pocas consultas IN, y
  /// todo se escribe en un solo batch. Fila por fila, un primer pull de miles de notas
  /// dejaba el teléfono ocupado varios minutos.
  Future<void> aplicarRegistros(List<Map<String, dynamic>> registros) async {
    if (registros.isEmpty) return;
    final ordenados = [...registros]
      ..sort((a, b) => _tipos.indexOf(a['tipo'] as String).compareTo(_tipos.indexOf(b['tipo'] as String)));
    final db = await _db;
    await db.transaction((tx) async {
      final claseClaves = {for (final r in ordenados) r['claseClave'] as String}..remove('');
      final clases = <String, String>{
        for (final c in await _en(tx, 'clases', ['id', 'clave'], 'clave', claseClaves)) c['clave'] as String: c['id'] as String,
      };
      final alumnos = <String, String>{
        for (final a in await _en(tx, 'alumnos', ['id', 'clase_id', 'clave'], 'clase_id', clases.values.toSet()))
          '${a['clase_id']}|${a['clave']}': a['id'] as String,
      };

      // Llave local de cada registro y su tabla; lo que no se puede ubicar queda fuera.
      final filas = <({String tabla, Map<String, Object?> llave, String cuando, Map<String, Object?> fila})>[];
      for (final r in ordenados) {
        final tipo = r['tipo'] as String;
        final clave = r['clave'] as String;
        final cuando = DateTime.parse(r['actualizadoEn'] as String).toUtc().toIso8601String();
        final eliminado = r['eliminado'] == true ? 1 : 0;
        final datos =
            r['datos'] == null ? const <String, dynamic>{} : jsonDecode(r['datos'] as String) as Map<String, dynamic>;
        final sync = {'actualizado_en': cuando, 'sucia': 0};
        void agregar(String tabla, Map<String, Object?> llave, Map<String, Object?> fila) =>
            filas.add((tabla: tabla, llave: llave, cuando: cuando, fila: {...fila, ...sync}));

        if (tipo == 'plantilla') {
          agregar('plantillas', {'id': clave}, {
            'nombre': datos['nombre'] ?? '',
            'rubros_json': jsonEncode(datos['rubros'] ?? const []),
            'eliminado': eliminado,
          });
          continue;
        }
        final clase = clases[r['claseClave']];
        if (clase == null) continue;
        switch (tipo) {
          case 'rubro':
            agregar('rubros', {'id': clave}, {
              'clase_id': clase,
              'parcial': datos['parcial'],
              'nombre': datos['nombre'],
              'puntos': datos['puntos'],
              'orden': datos['orden'],
              'eliminado': eliminado,
            });
          case 'actividad':
            agregar('actividades', {'id': clave}, {
              'clase_id': clase,
              'parcial': datos['parcial'],
              'rubro_id': datos['rubroId'],
              'titulo': datos['titulo'],
              'fecha': datos['fecha'],
              'puntos': datos['puntos'],
              'descripcion': datos['descripcion'],
              'eliminado': eliminado,
            });
          case 'sesion':
            agregar('sesiones', {'id': clave}, {
              'clase_id': clase,
              'parcial': datos['parcial'],
              'fecha': datos['fecha'],
              'eliminado': eliminado,
            });
          case 'parcial':
            agregar('parciales', {'clase_id': clase, 'parcial': clave}, {'cerrado_en': datos['cerradoEn']});
          case 'calificacion' || 'asistencia':
            final corte = clave.indexOf('|');
            if (corte < 0) continue;
            final alumno = alumnos['$clase|${clave.substring(corte + 1)}'];
            if (alumno == null) continue;
            final padre = clave.substring(0, corte);
            if (tipo == 'calificacion') {
              agregar('calificaciones', {'actividad_id': padre, 'alumno_id': alumno}, {'valor': datos['valor']});
            } else {
              agregar('asistencias', {'sesion_id': padre, 'alumno_id': alumno}, {'estado': datos['estado']});
            }
        }
      }

      // Horas locales de lo que ya existe, por tabla, con una consulta IN por tanda.
      final actuales = <String, String>{};
      String llaveDe(String tabla, Map<String, Object?> llave) => '$tabla|${llave.values.join('|')}';
      final porTabla = <String, List<Map<String, Object?>>>{};
      for (final f in filas) {
        (porTabla[f.tabla] ??= []).add(f.llave);
      }
      for (final MapEntry(key: tabla, value: llaves) in porTabla.entries) {
        final primera = llaves.first.keys.first;
        final columnas = [...llaves.first.keys, 'actualizado_en'];
        for (final fila in await _en(tx, tabla, columnas, primera, {for (final l in llaves) l[primera]})) {
          actuales[llaveDe(tabla, {for (final k in llaves.first.keys) k: fila[k]})] = fila['actualizado_en'] as String;
        }
      }
      // Actividades y listas que existen (o llegan en este lote): una nota sin su actividad
      // violaría la llave foránea.
      final padres = <String>{
        for (final f in filas)
          if (f.tabla == 'actividades' || f.tabla == 'sesiones') f.llave['id'] as String,
        ...{
          for (final r in await _en(tx, 'actividades', ['id'], 'id',
              {for (final f in filas) if (f.tabla == 'calificaciones') f.llave['actividad_id']}))
            r['id'] as String,
        },
        ...{
          for (final r in await _en(tx, 'sesiones', ['id'], 'id',
              {for (final f in filas) if (f.tabla == 'asistencias') f.llave['sesion_id']}))
            r['id'] as String,
        },
      };

      final batch = tx.batch();
      for (final f in filas) {
        final padre = f.llave['actividad_id'] ?? f.llave['sesion_id'];
        if (padre != null && !padres.contains(padre)) continue;
        final llave = llaveDe(f.tabla, f.llave);
        final actual = actuales[llave];
        final where = f.llave.keys.map((k) => '$k = ?').join(' AND ');
        if (actual == null) {
          batch.insert(f.tabla, {...f.llave, ...f.fila});
        } else if (DateTime.parse(f.cuando).isAfter(DateTime.parse(actual))) {
          // Actualizar en su lugar: reemplazar borraría en cascada lo que cuelga de la fila.
          batch.update(f.tabla, f.fila, where: where, whereArgs: f.llave.values.toList());
        } else {
          continue;
        }
        // Un mismo registro repetido en el lote: la segunda vez ya es una actualización.
        actuales[llave] = f.cuando;
      }
      await batch.commit(noResult: true);
    });
  }

  /// Filas de [tabla] cuyo [columna] está en [valores], en tandas (SQLite limita los parámetros).
  static Future<List<Map<String, Object?>>> _en(
      DatabaseExecutor db, String tabla, List<String> columnas, String columna, Set<Object?> valores) async {
    final lista = valores.whereType<Object>().toList();
    final filas = <Map<String, Object?>>[];
    for (var i = 0; i < lista.length; i += 500) {
      final tanda = lista.skip(i).take(500).toList();
      filas.addAll(await db.query(tabla,
          columns: columnas, where: '$columna IN (${List.filled(tanda.length, '?').join(', ')})', whereArgs: tanda));
    }
    return filas;
  }
}

/// Una fila del plan lista para subir y cómo reconocerla al marcarla subida.
typedef RegistroPendiente = ({
  String tabla,
  Map<String, Object?> llave,
  String actualizadoEn,
  Map<String, dynamic> json,
});

/// Una clase lista para subir, con las celdas que van, para marcarlas subidas después.
typedef PendienteClase = ({
  String id,
  int version,
  bool plantilla,
  Map<String, dynamic> json,
  List<({String alumnoId, String columnaClave, String actualizadoEn})> celdas,
});
