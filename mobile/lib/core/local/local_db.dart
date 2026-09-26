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
        version: 3,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => _create(db),
        onUpgrade: (db, from, to) async {
          if (from < 2) await _sync(db);
          if (from < 3) await _planes(db);
        },
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
        actualizada_en TEXT NOT NULL,
        sucia INTEGER NOT NULL DEFAULT 1,
        plantilla_sucia INTEGER NOT NULL DEFAULT 1,
        eliminada INTEGER NOT NULL DEFAULT 0,
        version INTEGER NOT NULL DEFAULT 0
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
    _crearValores(batch, 'valores');
    _crearSyncEstado(batch);
    _crearPlanes(batch);
    await batch.commit(noResult: true);
  }

  // Por clave de columna y no por id: sobrevive a que la plantilla se reimporte.
  // valor NULL es un borrado que todavía hay que avisarle al servidor.
  static void _crearValores(Batch batch, String tabla) => batch.execute('''
      CREATE TABLE $tabla (
        alumno_id TEXT NOT NULL REFERENCES alumnos(id) ON DELETE CASCADE,
        columna_clave TEXT NOT NULL,
        valor INTEGER,
        actualizado_en TEXT NOT NULL,
        PRIMARY KEY (alumno_id, columna_clave)
      )''');

  /// Cursor del último pull y otros datos de la sincronización.
  static void _crearSyncEstado(Batch batch) =>
      batch.execute('CREATE TABLE sync_estado (clave TEXT PRIMARY KEY, valor TEXT NOT NULL)');

  /// v1 → v2: marcas de sincronización. SQLite no deja volver nullable una columna, así
  /// que valores se recrea copiando lo que había.
  static Future<void> _sync(Database db) async {
    final batch = db.batch();
    for (final columna in [
      'sucia INTEGER NOT NULL DEFAULT 1',
      'plantilla_sucia INTEGER NOT NULL DEFAULT 1',
      'eliminada INTEGER NOT NULL DEFAULT 0',
      'version INTEGER NOT NULL DEFAULT 0',
    ]) {
      batch.execute('ALTER TABLE clases ADD COLUMN $columna');
    }
    _crearValores(batch, 'valores_v2');
    batch.execute('INSERT INTO valores_v2 SELECT alumno_id, columna_clave, valor, actualizado_en FROM valores');
    batch.execute('DROP TABLE valores');
    batch.execute('ALTER TABLE valores_v2 RENAME TO valores');
    _crearSyncEstado(batch);
    await batch.commit(noResult: true);
  }

  /// v2 → v3: planes de calificación y asistencia.
  static Future<void> _planes(Database db) async {
    final batch = db.batch();
    _crearPlanes(batch);
    await batch.commit(noResult: true);
  }

  /// Plan de calificación por puntos y asistencia. Cada fila lleva su propia marca de
  /// sincronización: sucia = 1 hasta que el servidor la recibe con ese actualizado_en.
  /// Los borrados son lápidas (eliminado = 1, o valor/estado NULL) hasta avisarle al servidor.
  /// Los id nacen en el teléfono y viajan tal cual: una actividad no tiene otra clave natural.
  /// parcial es la clave normalizada del grupo del cuadro (`PARCIAL I`).
  static void _crearPlanes(Batch batch) {
    const sync = 'actualizado_en TEXT NOT NULL, sucia INTEGER NOT NULL DEFAULT 1';
    // Plantillas del docente: los rubros van como JSON porque son pocos y se editan juntos.
    batch.execute('''
      CREATE TABLE plantillas (
        id TEXT PRIMARY KEY,
        nombre TEXT NOT NULL,
        rubros_json TEXT NOT NULL,
        eliminado INTEGER NOT NULL DEFAULT 0,
        $sync
      )''');
    // El plan concreto de una clase en un parcial: copia de una plantilla, editable aparte.
    batch.execute('''
      CREATE TABLE rubros (
        id TEXT PRIMARY KEY,
        clase_id TEXT NOT NULL REFERENCES clases(id) ON DELETE CASCADE,
        parcial TEXT NOT NULL,
        nombre TEXT NOT NULL,
        puntos REAL NOT NULL,
        orden INTEGER NOT NULL,
        eliminado INTEGER NOT NULL DEFAULT 0,
        $sync
      )''');
    batch.execute('''
      CREATE TABLE actividades (
        id TEXT PRIMARY KEY,
        clase_id TEXT NOT NULL REFERENCES clases(id) ON DELETE CASCADE,
        parcial TEXT NOT NULL,
        rubro_id TEXT NOT NULL,
        titulo TEXT NOT NULL,
        fecha TEXT NOT NULL,
        puntos REAL NOT NULL,
        descripcion TEXT,
        eliminado INTEGER NOT NULL DEFAULT 0,
        $sync
      )''');
    // valor NULL = pendiente (o un borrado por avisar); 0 = no entregó.
    batch.execute('''
      CREATE TABLE calificaciones (
        actividad_id TEXT NOT NULL REFERENCES actividades(id) ON DELETE CASCADE,
        alumno_id TEXT NOT NULL REFERENCES alumnos(id) ON DELETE CASCADE,
        valor REAL,
        $sync,
        PRIMARY KEY (actividad_id, alumno_id)
      )''');
    batch.execute('''
      CREATE TABLE sesiones (
        id TEXT PRIMARY KEY,
        clase_id TEXT NOT NULL REFERENCES clases(id) ON DELETE CASCADE,
        parcial TEXT NOT NULL,
        fecha TEXT NOT NULL,
        eliminado INTEGER NOT NULL DEFAULT 0,
        $sync
      )''');
    // estado: P presente, A ausente, T tarde, J justificada. Sin fila = presente.
    batch.execute('''
      CREATE TABLE asistencias (
        sesion_id TEXT NOT NULL REFERENCES sesiones(id) ON DELETE CASCADE,
        alumno_id TEXT NOT NULL REFERENCES alumnos(id) ON DELETE CASCADE,
        estado TEXT,
        $sync,
        PRIMARY KEY (sesion_id, alumno_id)
      )''');
    batch.execute('''
      CREATE TABLE parciales (
        clase_id TEXT NOT NULL REFERENCES clases(id) ON DELETE CASCADE,
        parcial TEXT NOT NULL,
        cerrado_en TEXT,
        $sync,
        PRIMARY KEY (clase_id, parcial)
      )''');
    batch.execute('CREATE INDEX ix_actividades_clase ON actividades (clase_id, parcial)');
    batch.execute('CREATE INDEX ix_sesiones_clase ON sesiones (clase_id, parcial)');
  }
}
