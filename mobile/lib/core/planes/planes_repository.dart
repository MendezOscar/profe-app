import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../local/clases_repository.dart';
import '../sace/cuadro_sace.dart';
import 'calculo_parcial.dart';
import 'modelos.dart';

/// Planes de calificación, actividades, notas y asistencia en la base del teléfono.
/// Nada se borra de verdad al momento: queda la lápida hasta que el servidor se entera.
class PlanesRepository {
  PlanesRepository(this._db, this._clases);

  final Future<Database> _db;
  final ClasesRepository _clases;
  static const _uuid = Uuid();

  // ── Parciales ─────────────────────────────────────────────────────────────

  /// Los parciales que trae la plantilla de la clase, en su orden. Un grupo cuenta como
  /// parcial si tiene subcolumnas y una de ellas es de nota (RECUPERACIÓN va sola).
  Future<List<Parcial>> parciales(String claseId) async {
    final db = await _db;
    final columnas = await db.query('columnas', where: 'clase_id = ?', whereArgs: [claseId], orderBy: 'orden');
    final grupos = <String, List<Map<String, Object?>>>{};
    for (final c in columnas) {
      if (c['grupo'] == c['nombre']) continue;
      (grupos[c['grupo'] as String] ??= []).add(c);
    }
    return [
      for (final MapEntry(key: grupo, value: cols) in grupos.entries)
        if (_primera(cols, TipoColumna.nota) case final nota?)
          Parcial(
            clave: normalizar(grupo),
            titulo: grupo,
            notaClave: nota,
            inasistenciasClave: _primera(cols, TipoColumna.inasistencias),
          ),
    ];
  }

  static String? _primera(List<Map<String, Object?>> cols, TipoColumna tipo) =>
      cols.where((c) => c['tipo'] == tipo.name).map((c) => c['clave'] as String).firstOrNull;

  // ── Plantillas ────────────────────────────────────────────────────────────

  /// Las del docente primero, luego las que vienen con la app.
  Future<List<Plantilla>> plantillas() async {
    final db = await _db;
    final rows = await db.query('plantillas', where: 'eliminado = 0', orderBy: 'nombre');
    return [
      for (final r in rows)
        Plantilla(
          id: r['id'] as String,
          nombre: r['nombre'] as String,
          rubros: [
            for (final j in (jsonDecode(r['rubros_json'] as String) as List).cast<Map<String, dynamic>>())
              RubroPlantilla.fromJson(j),
          ],
        ),
      ...Plantilla.prearmadas,
    ];
  }

  /// Crea o actualiza. Una prearmada se guarda como copia nueva del docente.
  Future<String> guardarPlantilla({String? id, required String nombre, required List<RubroPlantilla> rubros}) async {
    final db = await _db;
    final plantillaId = id == null || id.startsWith('pre:') ? _uuid.v4() : id;
    await db.insert(
      'plantillas',
      {
        'id': plantillaId,
        'nombre': nombre.trim(),
        'rubros_json': jsonEncode([for (final r in rubros) r.toJson()]),
        'eliminado': 0,
        ..._sucia(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return plantillaId;
  }

  Future<void> eliminarPlantilla(String id) async {
    final db = await _db;
    await db.update('plantillas', {'eliminado': 1, ..._sucia()}, where: 'id = ?', whereArgs: [id]);
  }

  // ── Plan de la clase ──────────────────────────────────────────────────────

  /// Copia los rubros a la clase en esos parciales. Sólo en los que todavía no tienen
  /// plan: un plan en marcha no se pisa. Devuelve en cuántos parciales se aplicó.
  Future<int> aplicarPlantilla(String claseId, Iterable<String> parciales, List<RubroPlantilla> rubros) async {
    final db = await _db;
    var aplicados = 0;
    await db.transaction((tx) async {
      for (final parcial in parciales) {
        if (await _tieneRubros(tx, claseId, parcial)) continue;
        for (final (orden, r) in rubros.indexed) {
          await tx.insert('rubros', {
            'id': _uuid.v4(),
            'clase_id': claseId,
            'parcial': parcial,
            'nombre': r.nombre,
            'puntos': r.puntos,
            'orden': orden,
            ..._sucia(),
          });
        }
        aplicados++;
      }
    });
    return aplicados;
  }

  /// "Mismo plan que el parcial anterior": copia sólo los rubros, no las actividades.
  Future<bool> copiarPlan(String claseId, {required String desde, required String hacia}) async {
    final db = await _db;
    final origen = await db.query('rubros',
        where: 'clase_id = ? AND parcial = ? AND eliminado = 0', whereArgs: [claseId, desde], orderBy: 'orden');
    if (origen.isEmpty) return false;
    final aplicados = await aplicarPlantilla(claseId, [hacia], [
      for (final r in origen) RubroPlantilla(r['nombre'] as String, (r['puntos'] as num).toDouble()),
    ]);
    return aplicados > 0;
  }

  Future<bool> _tieneRubros(DatabaseExecutor db, String claseId, String parcial) async =>
      (await db.query('rubros',
              columns: ['id'],
              where: 'clase_id = ? AND parcial = ? AND eliminado = 0',
              whereArgs: [claseId, parcial],
              limit: 1))
          .isNotEmpty;

  Future<String> guardarRubro(String claseId, String parcial,
      {String? id, required String nombre, required double puntos, int? orden}) async {
    final db = await _db;
    final rubroId = id ?? _uuid.v4();
    final siguiente = orden ??
        ((await db.rawQuery('SELECT COALESCE(MAX(orden), -1) + 1 AS n FROM rubros WHERE clase_id = ? AND parcial = ?',
                [claseId, parcial]))
            .first['n'] as int);
    await db.insert(
      'rubros',
      {
        'id': rubroId,
        'clase_id': claseId,
        'parcial': parcial,
        'nombre': nombre.trim(),
        'puntos': puntos,
        'orden': siguiente,
        'eliminado': 0,
        ..._sucia(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return rubroId;
  }

  /// Nuevo orden de los rubros tras arrastrarlos.
  Future<void> ordenarRubros(List<String> ids) async {
    final db = await _db;
    await db.transaction((tx) async {
      for (final (orden, id) in ids.indexed) {
        await tx.update('rubros', {'orden': orden, ..._sucia()}, where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  /// Un rubro con actividades no se borra: primero hay que moverlas o borrarlas.
  Future<bool> eliminarRubro(String id) async {
    final db = await _db;
    final usadas = await db.query('actividades',
        columns: ['id'], where: 'rubro_id = ? AND eliminado = 0', whereArgs: [id], limit: 1);
    if (usadas.isNotEmpty) return false;
    await db.update('rubros', {'eliminado': 1, ..._sucia()}, where: 'id = ?', whereArgs: [id]);
    return true;
  }

  // ── Actividades y notas ───────────────────────────────────────────────────

  Future<String> guardarActividad(
    String claseId,
    String parcial, {
    String? id,
    required String rubroId,
    required String titulo,
    required DateTime fecha,
    required double puntos,
    String? descripcion,
  }) async {
    final db = await _db;
    final actividadId = id ?? _uuid.v4();
    await _guardar(db, 'actividades', {
      'id': actividadId,
      'clase_id': claseId,
      'parcial': parcial,
      'rubro_id': rubroId,
      'titulo': titulo.trim(),
      'fecha': _fecha(fecha),
      'puntos': puntos,
      'descripcion': (descripcion?.trim().isEmpty ?? true) ? null : descripcion!.trim(),
      'eliminado': 0,
      ..._sucia(),
    });
    return actividadId;
  }

  /// Reversible con [restaurarActividad] mientras el docente tenga el "Deshacer" a mano.
  Future<void> eliminarActividad(String id) => _marcar('actividades', id, eliminado: true);

  Future<void> restaurarActividad(String id) => _marcar('actividades', id, eliminado: false);

  Future<void> _marcar(String tabla, String id, {required bool eliminado}) async {
    final db = await _db;
    await db.update(tabla, {'eliminado': eliminado ? 1 : 0, ..._sucia()}, where: 'id = ?', whereArgs: [id]);
  }

  /// Null deja la nota pendiente. Los puntos se validan en la pantalla contra la actividad.
  Future<void> calificar(String actividadId, String alumnoId, double? valor) async {
    final db = await _db;
    await db.insert(
      'calificaciones',
      {'actividad_id': actividadId, 'alumno_id': alumnoId, 'valor': valor, ..._sucia()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── Asistencia ────────────────────────────────────────────────────────────

  /// La lista de ese día; si no existe, se crea. Una por clase y fecha.
  Future<String> sesion(String claseId, String parcial, DateTime fecha) async {
    final db = await _db;
    final existente = await db.query('sesiones',
        columns: ['id'], where: 'clase_id = ? AND fecha = ? AND eliminado = 0', whereArgs: [claseId, _fecha(fecha)]);
    if (existente.isNotEmpty) return existente.first['id'] as String;
    final id = _uuid.v4();
    await db.insert('sesiones', {'id': id, 'clase_id': claseId, 'parcial': parcial, 'fecha': _fecha(fecha), ..._sucia()});
    return id;
  }

  Future<void> eliminarSesion(String id) => _marcar('sesiones', id, eliminado: true);

  Future<void> marcarAsistencia(String sesionId, String alumnoId, EstadoAsistencia estado) async {
    final db = await _db;
    await db.insert(
      'asistencias',
      {'sesion_id': sesionId, 'alumno_id': alumnoId, 'estado': estado.codigo, ..._sucia()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── Lectura ───────────────────────────────────────────────────────────────

  Future<PlanParcial> plan(String claseId, Parcial parcial) async {
    final db = await _db;
    final args = [claseId, parcial.clave];
    final rubros = await db.query('rubros',
        where: 'clase_id = ? AND parcial = ? AND eliminado = 0', whereArgs: args, orderBy: 'orden');
    final actividades = await db.query('actividades',
        where: 'clase_id = ? AND parcial = ? AND eliminado = 0', whereArgs: args, orderBy: 'fecha, titulo');
    final alumnos = await db.query('alumnos',
        columns: ['id', 'nombre', 'identidad'], where: 'clase_id = ? AND activo = 1', whereArgs: [claseId], orderBy: 'orden');
    final notas = await db.rawQuery('''
      SELECT c.actividad_id, c.alumno_id, c.valor FROM calificaciones c
      JOIN actividades a ON a.id = c.actividad_id
      WHERE a.clase_id = ? AND a.parcial = ? AND a.eliminado = 0 AND c.valor IS NOT NULL''', args);
    final sesiones = await db.query('sesiones',
        where: 'clase_id = ? AND parcial = ? AND eliminado = 0', whereArgs: args, orderBy: 'fecha DESC');
    final asistencias = await db.rawQuery('''
      SELECT x.sesion_id, x.alumno_id, x.estado FROM asistencias x
      JOIN sesiones s ON s.id = x.sesion_id
      WHERE s.clase_id = ? AND s.parcial = ? AND s.eliminado = 0 AND x.estado IS NOT NULL''', args);
    final estado = await db.query('parciales', where: 'clase_id = ? AND parcial = ?', whereArgs: args);

    final calificaciones = <String, Map<String, double>>{};
    for (final n in notas) {
      (calificaciones[n['actividad_id'] as String] ??= {})[n['alumno_id'] as String] = (n['valor'] as num).toDouble();
    }
    final porSesion = <String, Map<String, EstadoAsistencia>>{};
    for (final x in asistencias) {
      (porSesion[x['sesion_id'] as String] ??= {})[x['alumno_id'] as String] =
          EstadoAsistencia.desde(x['estado'] as String?);
    }
    final cerrado = estado.firstOrNull?['cerrado_en'] as String?;

    return PlanParcial(
      claseId: claseId,
      parcial: parcial,
      rubros: [
        for (final r in rubros)
          Rubro(
            id: r['id'] as String,
            nombre: r['nombre'] as String,
            puntos: (r['puntos'] as num).toDouble(),
            orden: r['orden'] as int,
          ),
      ],
      actividades: [
        for (final a in actividades)
          Actividad(
            id: a['id'] as String,
            rubroId: a['rubro_id'] as String,
            titulo: a['titulo'] as String,
            fecha: DateTime.parse(a['fecha'] as String),
            puntos: (a['puntos'] as num).toDouble(),
            descripcion: a['descripcion'] as String?,
          ),
      ],
      alumnos: [
        for (final a in alumnos)
          AlumnoPlan(id: a['id'] as String, nombre: a['nombre'] as String, identidad: a['identidad'] as String),
      ],
      calificaciones: calificaciones,
      sesiones: [
        for (final s in sesiones) Sesion(id: s['id'] as String, fecha: DateTime.parse(s['fecha'] as String)),
      ],
      asistencias: porSesion,
      cerradoEn: cerrado == null ? null : DateTime.parse(cerrado),
    );
  }

  // ── Cierre ────────────────────────────────────────────────────────────────

  /// Pasa la nota y las faltas de cada alumno al cuadro de SACE (las mismas celdas que
  /// se capturan a mano), listas para exportar. El parcial queda cerrado hasta reabrirlo.
  Future<void> cerrar(PlanParcial plan) async {
    final resultado = calcularParcial(plan);
    for (final alumno in plan.alumnos) {
      final nota = resultado.porAlumno[alumno.id]!;
      if (plan.parcial.notaClave case final clave?) await _clases.guardarValor(alumno.id, clave, nota.nota);
      if (plan.parcial.inasistenciasClave case final clave?) {
        await _clases.guardarValor(alumno.id, clave, nota.inasistencias);
      }
    }
    await _estadoParcial(plan.claseId, plan.parcial.clave, ahoraUtc());
  }

  Future<void> reabrir(String claseId, String parcial) => _estadoParcial(claseId, parcial, null);

  Future<void> _estadoParcial(String claseId, String parcial, String? cerradoEn) async {
    final db = await _db;
    await db.insert(
      'parciales',
      {'clase_id': claseId, 'parcial': parcial, 'cerrado_en': cerradoEn, ..._sucia()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Actualiza o inserta por id. No INSERT OR REPLACE: el reemplazo borra la fila y con
  /// ella, en cascada, las notas o la asistencia que cuelgan de ella.
  static Future<void> _guardar(DatabaseExecutor db, String tabla, Map<String, Object?> fila) async {
    final n = await db.update(tabla, fila, where: 'id = ?', whereArgs: [fila['id']]);
    if (n == 0) await db.insert(tabla, fila);
  }

  static Map<String, Object> _sucia() => {'actualizado_en': ahoraUtc(), 'sucia': 1};

  static String _fecha(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
