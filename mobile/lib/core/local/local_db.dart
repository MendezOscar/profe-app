import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Base local del teléfono: es la fuente de verdad del docente, funcione o no el internet.
/// Una base por usuario, para que dos docentes que comparten teléfono no se mezclen.
class LocalDb {
  static Future<Database> open(String userId) async {
    final factory = kIsWeb ? databaseFactoryFfiWeb : databaseFactory;
    final name = 'profeapp_$userId.db';
    final path = kIsWeb ? name : p.join(await factory.getDatabasesPath(), name);
    return openAt(factory, path);
  }

  @visibleForTesting
  static Future<Database> openAt(DatabaseFactory factory, String path) {
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => _create(db),
      ),
    );
  }

  static Future<void> _create(Database db) async {
    final batch = db.batch();
    // Una clase = un archivo de SACE. Se guarda el archivo original entero: al exportar
    // se rellena ese mismo archivo, sin regenerarlo.
    batch.execute('''
      CREATE TABLE clases (
        id TEXT PRIMARY KEY,
        clave TEXT NOT NULL UNIQUE,
        codigo_centro TEXT,
        centro TEXT,
        modalidad TEXT,
        grado_seccion TEXT,
        jornada TEXT,
        asignatura TEXT,
        hoja TEXT NOT NULL,
        archivo_nombre TEXT NOT NULL,
        archivo BLOB NOT NULL,
        importada_en TEXT NOT NULL,
        actualizada_en TEXT NOT NULL
      )''');
    // Se reemplazan en cada importación: son el mapa de la plantilla vigente.
    batch.execute('''
      CREATE TABLE columnas (
        id TEXT PRIMARY KEY,
        clase_id TEXT NOT NULL REFERENCES clases(id) ON DELETE CASCADE,
        clave TEXT NOT NULL,
        grupo TEXT NOT NULL,
        nombre TEXT NOT NULL,
        tipo TEXT NOT NULL,
        col INTEGER NOT NULL,
        orden INTEGER NOT NULL,
        UNIQUE (clase_id, clave)
      )''');
    // activo = 0 cuando el alumno ya no viene en la última plantilla (retiro, traslado):
    // se oculta pero no se pierde lo capturado.
    batch.execute('''
      CREATE TABLE alumnos (
        id TEXT PRIMARY KEY,
        clase_id TEXT NOT NULL REFERENCES clases(id) ON DELETE CASCADE,
        clave TEXT NOT NULL,
        identidad TEXT NOT NULL,
        documento TEXT NOT NULL,
        nombre TEXT NOT NULL,
        fila INTEGER NOT NULL,
        orden INTEGER NOT NULL,
        activo INTEGER NOT NULL DEFAULT 1,
        UNIQUE (clase_id, clave)
      )''');
    // Por clave de columna y no por id: sobrevive a que la plantilla se reimporte.
    batch.execute('''
      CREATE TABLE valores (
        alumno_id TEXT NOT NULL REFERENCES alumnos(id) ON DELETE CASCADE,
        columna_clave TEXT NOT NULL,
        valor INTEGER NOT NULL,
        actualizado_en TEXT NOT NULL,
        PRIMARY KEY (alumno_id, columna_clave)
      )''');
    await batch.commit(noResult: true);
  }
}
