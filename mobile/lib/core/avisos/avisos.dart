import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../planes/calculo_parcial.dart';
import '../planes/estadisticas.dart';
import '../preferencias.dart';
import '../providers.dart';
import '../sync/sync_controller.dart';
import 'recordatorio.dart';

enum TipoAviso {
  calificar(Icons.edit_note),
  lista(Icons.fact_check_outlined),
  cierre(Icons.event_outlined),
  rubrica(Icons.rule),
  riesgo(Icons.warning_amber),
  exportar(Icons.upload_file),
  respaldo(Icons.cloud_off_outlined);

  const TipoAviso(this.icono);
  final IconData icono;
}

/// Algo que el docente tiene pendiente. El [id] cambia cuando cambia la situación
/// (otro número de faltantes, otro día), así un aviso descartado vuelve si hay algo nuevo.
class Aviso {
  const Aviso({required this.id, required this.tipo, required this.titulo, required this.detalle, this.ruta, this.urgente = false});

  final String id;
  final TipoAviso tipo;
  final String titulo;
  final String detalle;

  /// Adónde lleva tocarlo: la pantalla donde se resuelve.
  final String? ruta;
  final bool urgente;
}

/// Días de la semana en que el docente suele dar esta clase: los que se repiten en sus
/// listas de las últimas cuatro semanas.
Set<int> diasDeClase(List<DateTime> sesiones, DateTime hoy) {
  final desde = hoy.subtract(const Duration(days: 28));
  final conteo = <int, int>{};
  for (final s in sesiones.where((s) => s.isAfter(desde))) {
    conteo[s.weekday] = (conteo[s.weekday] ?? 0) + 1;
  }
  return {for (final MapEntry(key: dia, value: n) in conteo.entries) if (n >= 2) dia};
}

/// Los avisos del momento, los urgentes primero. Todo sale de lo que ya está en el teléfono.
List<Aviso> calcularAvisos({
  required List<AvanceClase> avances,
  required Map<String, ({String parcial, DateTime cerradoEn})> cierres,
  required Map<String, DateTime> exportados,
  required DateTime? ultimaSync,
  required DateTime ahora,
}) {
  final hoy = DateUtils.dateOnly(ahora);
  final avisos = <Aviso>[];

  for (final avance in avances) {
    final clase = avance.clase;
    final nombre = clase.asignatura;
    final base = '/inicio/asignaturas/${clase.id}';

    // Cerrado un parcial y el cuadro no se exportó desde entonces.
    if (cierres[clase.id] case final cierre?) {
      final exportado = exportados[clase.id];
      if (exportado == null || exportado.isBefore(cierre.cerradoEn)) {
        avisos.add(Aviso(
          id: 'exportar:${clase.id}:${cierre.parcial}',
          tipo: TipoAviso.exportar,
          titulo: 'Exporta el cuadro de $nombre para SACE',
          detalle: 'Cerraste el ${_titulo(cierre.parcial)} y el cuadro no se ha exportado desde entonces.',
          ruta: '$base/cuadro',
        ));
      }
    }

    final plan = avance.plan;
    final resultado = avance.resultado;
    if (plan == null || resultado == null || plan.cerrado) continue;
    final parcial = plan.parcial.titulo;
    final conParcial = '?parcial=${Uri.encodeQueryComponent(plan.parcial.clave)}';
    final alumnos = plan.alumnos.length;

    for (final a in plan.actividades) {
      if (!DateUtils.dateOnly(a.fecha).isBefore(hoy)) continue;
      final faltan = plan.alumnos.where((al) => plan.calificaciones[a.id]?[al.id] == null).length;
      if (faltan == 0) continue;
      avisos.add(Aviso(
        id: 'calificar:${a.id}:$faltan',
        tipo: TipoAviso.calificar,
        titulo: 'Te falta calificar «${a.titulo}»',
        detalle: '$nombre · ${faltan == alumnos ? 'sin notas todavía' : 'faltan $faltan de $alumnos'}',
        ruta: '$base/actividades/${a.id}$conParcial',
        urgente: hoy.difference(DateUtils.dateOnly(a.fecha)).inDays >= 7,
      ));
    }

    final fechas = [for (final s in plan.sesiones) DateUtils.dateOnly(s.fecha)];
    if (diasDeClase(fechas, hoy).contains(hoy.weekday) && !fechas.contains(hoy)) {
      avisos.add(Aviso(
        id: 'lista:${clase.id}:${hoy.toIso8601String()}',
        tipo: TipoAviso.lista,
        titulo: 'Hoy no has pasado lista en $nombre',
        detalle: 'Sueles dar esta clase este día.',
        ruta: '/asistencia/${clase.id}',
      ));
    }

    if (plan.rubros.isNotEmpty && resultado.totalPlan != 100) {
      avisos.add(Aviso(
        id: 'rubrica:${clase.id}:${plan.parcial.clave}:${resultado.totalPlan}',
        tipo: TipoAviso.rubrica,
        titulo: 'La rúbrica del $parcial suma ${formatoPuntos(resultado.totalPlan)} de 100',
        detalle: '$nombre · ajusta los puntos de los rubros.',
        ruta: '$base$conParcial',
      ));
    }

    if (plan.actividades.isNotEmpty) {
      final ultima = DateUtils.dateOnly(plan.actividades.map((a) => a.fecha).reduce((a, b) => a.isAfter(b) ? a : b));
      final dias = ultima.difference(hoy).inDays;
      final pendiente = resultado.actividadesIncompletas.isNotEmpty;
      if (dias >= 0 && dias <= 7 && pendiente) {
        avisos.add(Aviso(
          id: 'cierre:${clase.id}:${plan.parcial.clave}',
          tipo: TipoAviso.cierre,
          titulo: 'El $parcial de $nombre termina ${dias == 0 ? 'hoy' : dias == 1 ? 'mañana' : 'en $dias días'}',
          detalle: '${resultado.actividadesIncompletas.length} actividades todavía sin todas sus notas.',
          ruta: '$base$conParcial',
          urgente: dias <= 2,
        ));
      } else if (dias < 0 && !pendiente && resultado.totalPlan == 100 && resultado.asignado >= 100) {
        avisos.add(Aviso(
          id: 'cierre:${clase.id}:${plan.parcial.clave}:listo',
          tipo: TipoAviso.cierre,
          titulo: 'Ya puedes cerrar el $parcial de $nombre',
          detalle: 'Todo está calificado. Al cerrarlo, la nota pasa al cuadro de SACE.',
          ruta: '$base$conParcial&pestana=2',
        ));
      }
    }

    final riesgo = calcularEstadisticas(plan).enRiesgo;
    if (riesgo.isNotEmpty) {
      avisos.add(Aviso(
        id: 'riesgo:${clase.id}:${plan.parcial.clave}:${riesgo.map((r) => r.alumno.id).join(',')}',
        tipo: TipoAviso.riesgo,
        titulo: '${riesgo.length} ${riesgo.length == 1 ? 'alumno en riesgo' : 'alumnos en riesgo'} en $nombre',
        detalle: 'Bajo $notaMinima o con muchas faltas en el $parcial.',
        ruta: '$base$conParcial&pestana=3',
      ));
    }
  }

  if (ultimaSync != null && ahora.difference(ultimaSync) > const Duration(hours: 24)) {
    final horas = ahora.difference(ultimaSync).inHours;
    avisos.add(Aviso(
      id: 'respaldo:${hoy.toIso8601String()}',
      tipo: TipoAviso.respaldo,
      titulo: 'Tus cambios no se respaldan desde hace ${horas >= 48 ? '${horas ~/ 24} días' : 'más de un día'}',
      detalle: 'Conéctate a internet para guardar una copia en línea.',
      urgente: horas >= 72,
    ));
  }

  avisos.sort((a, b) => (b.urgente ? 1 : 0) - (a.urgente ? 1 : 0));
  return avisos;
}

String _titulo(String clave) => clave[0] + clave.substring(1).toLowerCase().replaceFirstMapped(RegExp(r' ([ivx]+)$'), (m) => ' ${m[1]!.toUpperCase()}');

/// Clave con la hora del último export de cada clase (sólo en este dispositivo).
String claveExportado(String claseId) => 'profeapp.exportado.$claseId';

const _claveDescartados = 'profeapp.avisos_descartados';

class DescartadosNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => (ref.watch(preferenciasProvider).getStringList(_claveDescartados) ?? const []).toSet();

  /// Guarda sólo los que siguen vigentes: los viejos no se acumulan.
  Future<void> descartar(String id) async {
    final vigentes = {for (final a in ref.read(todosLosAvisosProvider).valueOrNull ?? const <Aviso>[]) a.id};
    state = {...state.where(vigentes.contains), id};
    await ref.read(preferenciasProvider).setStringList(_claveDescartados, state.toList());
  }
}

final descartadosProvider = NotifierProvider<DescartadosNotifier, Set<String>>(DescartadosNotifier.new);

/// Los avisos vigentes, también los descartados.
final todosLosAvisosProvider = FutureProvider<List<Aviso>>((ref) async {
  final avances = await ref.watch(tableroProvider.future);
  final prefs = ref.watch(preferenciasProvider);
  // Se recalcula al terminar cada sincronización.
  ref.watch(syncControllerProvider.select((s) => s.ultima));
  final ids = [for (final a in avances) a.clase.id];
  final cierres = await ref.watch(planesRepositoryProvider).ultimosCierres(ids);
  return calcularAvisos(
    avances: avances,
    cierres: cierres,
    exportados: {
      for (final id in ids)
        if (prefs.getString(claveExportado(id)) case final t?) id: DateTime.parse(t),
    },
    ultimaSync: switch (prefs.getString(claveUltimaSync)) { final t? => DateTime.parse(t), null => null },
    ahora: DateTime.now(),
  );
});

/// Lo que se muestra: los vigentes menos los descartados.
final avisosProvider = FutureProvider<List<Aviso>>((ref) async {
  final todos = await ref.watch(todosLosAvisosProvider.future);
  final descartados = ref.watch(descartadosProvider);
  final visibles = [for (final a in todos) if (!descartados.contains(a.id)) a];
  // El recordatorio de las 5 p. m. se reprograma con lo pendiente de ahora.
  if (ref.watch(banderaProvider(Bandera.recordatorio))) unawaited(Recordatorio.programar(visibles));
  return visibles;
});
