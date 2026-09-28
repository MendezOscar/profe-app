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
  Future<List<Parcial>> parciales(String claseId) async => (await parcialesDe([claseId]))[claseId] ?? const [];

  /// Los parciales de varias clases en una sola consulta (el tablero).
  Future<Map<String, List<Parcial>>> parcialesDe(List<String> claseIds) async {
    if (claseIds.isEmpty) return const {};
    final db = await _db;
    final columnas = await db.query('columnas',
        where: 'clase_id IN (${_marcas(claseIds)})', whereArgs: claseIds, orderBy: 'clase_id, orden');
    final grupos = <String, Map<String, List<Map<String, Object?>>>>{};
    for (final c in columnas) {
      if (c['grupo'] == c['nombre']) continue;
      ((grupos[c['clase_id'] as String] ??= {})[c['grupo'] as String] ??= []).add(c);
    }
    return {
      for (final MapEntry(key: claseId, value: deLaClase) in grupos.entries)
        claseId: [
          for (final MapEntry(key: grupo, value: cols) in deLaClase.entries)
            if (_primera(cols, TipoColumna.nota) case final nota?)
              Parcial(
                clave: normalizar(grupo),
                titulo: grupo,
                notaClave: nota,
                inasistenciasClave: _primera(cols, TipoColumna.inasistencias),
              ),
        ],
    };
  }

  static String _marcas(List<Object?> valores) => List.filled(valores.length, '?').join(', ');

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

  Future<PlanParcial> plan(String claseId, Parcial parcial) async => (await planes([(claseId, parcial)])).single;

  /// Un plan por clase (a lo sumo un parcial por clase), con las mismas consultas para
  /// una clase que para veinte: el tablero no hace una ronda por asignatura.
  Future<List<PlanParcial>> planes(List<(String, Parcial)> pedidos) async {
    if (pedidos.isEmpty) return const [];
    final db = await _db;
    final parcialDe = {for (final (claseId, parcial) in pedidos) claseId: parcial.clave};
    final ids = parcialDe.keys.toList();
    final enClases = 'clase_id IN (${_marcas(ids)})';
    bool delPedido(Map<String, Object?> f) => parcialDe[f['clase_id']] == f['parcial'];
    Map<String, List<Map<String, Object?>>> porClase(Iterable<Map<String, Object?>> filas) {
      final mapa = <String, List<Map<String, Object?>>>{};
      for (final f in filas) {
        (mapa[f['clase_id'] as String] ??= []).add(f);
      }
      return mapa;
    }

    final rubros = porClase((await db.query('rubros',
            where: '$enClases AND eliminado = 0', whereArgs: ids, orderBy: 'orden'))
        .where(delPedido));
    final actividades = porClase((await db.query('actividades',
            where: '$enClases AND eliminado = 0', whereArgs: ids, orderBy: 'fecha, titulo'))
        .where(delPedido));
    final alumnos = porClase(await db.query('alumnos',
        columns: ['id', 'clase_id', 'nombre', 'identidad'],
        where: '$enClases AND activo = 1',
        whereArgs: ids,
        orderBy: 'orden'));
    final notas = (await db.rawQuery('''
      SELECT a.clase_id, a.parcial, c.actividad_id, c.alumno_id, c.valor FROM calificaciones c
      JOIN actividades a ON a.id = c.actividad_id
      WHERE a.$enClases AND a.eliminado = 0 AND c.valor IS NOT NULL''', ids))
        .where(delPedido);
    final sesiones = porClase((await db.query('sesiones',
            where: '$enClases AND eliminado = 0', whereArgs: ids, orderBy: 'fecha DESC'))
        .where(delPedido));
    final asistencias = (await db.rawQuery('''
      SELECT s.clase_id, s.parcial, x.sesion_id, x.alumno_id, x.estado FROM asistencias x
      JOIN sesiones s ON s.id = x.sesion_id
      WHERE s.$enClases AND s.eliminado = 0 AND x.estado IS NOT NULL''', ids))
        .where(delPedido);
    final estados = {
      for (final e in (await db.query('parciales', where: enClases, whereArgs: ids)).where(delPedido))
        e['clase_id'] as String: e['cerrado_en'] as String?,
    };

    // Los ids de actividad y sesión son únicos: no hace falta separarlos por clase.
    final calificaciones = <String, Map<String, double>>{};
    for (final n in notas) {
      (calificaciones[n['actividad_id'] as String] ??= {})[n['alumno_id'] as String] = (n['valor'] as num).toDouble();
    }
    final porSesion = <String, Map<String, EstadoAsistencia>>{};
    for (final x in asistencias) {
      (porSesion[x['sesion_id'] as String] ??= {})[x['alumno_id'] as String] =
          EstadoAsistencia.desde(x['estado'] as String?);
    }

    return [
      for (final (claseId, parcial) in pedidos)
        () {
          final deActividades = [
            for (final a in actividades[claseId] ?? const <Map<String, Object?>>[])
              Actividad(
                id: a['id'] as String,
                rubroId: a['rubro_id'] as String,
                titulo: a['titulo'] as String,
                fecha: DateTime.parse(a['fecha'] as String),
                puntos: (a['puntos'] as num).toDouble(),
                descripcion: a['descripcion'] as String?,
              ),
          ];
          final deSesiones = [
            for (final x in sesiones[claseId] ?? const <Map<String, Object?>>[])
              Sesion(id: x['id'] as String, fecha: DateTime.parse(x['fecha'] as String)),
          ];
          final cerrado = estados[claseId];
          return PlanParcial(
            claseId: claseId,
            parcial: parcial,
            rubros: [
              for (final r in rubros[claseId] ?? const <Map<String, Object?>>[])
                Rubro(
                  id: r['id'] as String,
                  nombre: r['nombre'] as String,
                  puntos: (r['puntos'] as num).toDouble(),
                  orden: r['orden'] as int,
                ),
            ],
            actividades: deActividades,
            alumnos: [
              for (final a in alumnos[claseId] ?? const <Map<String, Object?>>[])
                AlumnoPlan(id: a['id'] as String, nombre: a['nombre'] as String, identidad: a['identidad'] as String),
            ],
            calificaciones: {for (final a in deActividades) if (calificaciones[a.id] case final c?) a.id: c},
            asistencias: {for (final x in deSesiones) if (porSesion[x.id] case final e?) x.id: e},
            sesiones: deSesiones,
            cerradoEn: cerrado == null ? null : DateTime.parse(cerrado),
          );
        }(),
    ];
  }

  /// Claves de los parciales cerrados de una clase, en una sola consulta.
  Future<Set<String>> parcialesCerrados(String claseId) async => (await cerradosDe([claseId]))[claseId] ?? const {};

  /// Parciales cerrados de varias clases, en una sola consulta.
  Future<Map<String, Set<String>>> cerradosDe(List<String> claseIds) async {
    if (claseIds.isEmpty) return const {};
    final db = await _db;
    final filas = await db.query('parciales',
        columns: ['clase_id', 'parcial'],
        where: 'clase_id IN (${_marcas(claseIds)}) AND cerrado_en IS NOT NULL',
        whereArgs: claseIds);
    final mapa = <String, Set<String>>{};
    for (final f in filas) {
      (mapa[f['clase_id'] as String] ??= {}).add(f['parcial'] as String);
    }
    return mapa;
  }

  /// Qué partes de la app ya usó el docente, para la guía de primeros pasos.
  Future<({bool plan, bool actividad, bool lista, bool cierre})> progreso() async {
    final db = await _db;
    Future<bool> hay(String sql) async => (await db.rawQuery(sql)).isNotEmpty;
    return (
      plan: await hay('SELECT 1 FROM rubros WHERE eliminado = 0 LIMIT 1'),
      actividad: await hay('SELECT 1 FROM actividades WHERE eliminado = 0 LIMIT 1'),
      lista: await hay('SELECT 1 FROM sesiones WHERE eliminado = 0 LIMIT 1'),
      cierre: await hay('SELECT 1 FROM parciales WHERE cerrado_en IS NOT NULL LIMIT 1'),
    );
  }

  // ── Cierre ────────────────────────────────────────────────────────────────

  /// Pasa la nota y las faltas de cada alumno al cuadro de SACE (las mismas celdas que
  /// se capturan a mano), listas para exportar. El parcial queda cerrado hasta reabrirlo.
  Future<void> cerrar(PlanParcial plan) async {
    final resultado = calcularParcial(plan);
    await _clases.guardarValores(plan.claseId, [
      for (final alumno in plan.alumnos) ...[
        if (plan.parcial.notaClave case final clave?) (alumno.id, clave, resultado.porAlumno[alumno.id]!.nota),
        if (plan.parcial.inasistenciasClave case final clave?)
          (alumno.id, clave, resultado.porAlumno[alumno.id]!.inasistencias),
      ],
    ]);
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
