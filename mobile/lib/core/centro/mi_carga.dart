import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/clase.dart';
import '../providers.dart';
import '../sace/cuadro_sace.dart';

/// Un alumno en la matrícula del centro. [estado]: activa, retirada o trasladada.
class AlumnoMatricula {
  const AlumnoMatricula({required this.identidad, required this.nombre, required this.estado});

  final String identidad;
  final String nombre;
  final String estado;

  bool get activo => estado == 'activa';
}

/// Sección donde el docente da clase o es guía, con la lista que lleva secretaría.
class SeccionCentro {
  const SeccionCentro({
    required this.id,
    required this.grado,
    required this.nombre,
    required this.jornada,
    required this.esGuia,
    required this.asignaturas,
    required this.alumnos,
  });

  factory SeccionCentro.fromJson(Map<String, dynamic> j) => SeccionCentro(
        id: j['id'] as String,
        grado: j['grado'] as String,
        nombre: j['nombre'] as String,
        jornada: j['jornada'] as String,
        esGuia: j['esGuia'] as bool,
        asignaturas: (j['asignaturas'] as List).cast<String>(),
        alumnos: [
          for (final a in (j['alumnos'] as List).cast<Map<String, dynamic>>())
            AlumnoMatricula(identidad: a['identidad'] as String, nombre: a['nombre'] as String, estado: a['estado'] as String),
        ],
      );

  final String id;
  final String grado;
  final String nombre;
  final String jornada;
  final bool esGuia;
  final List<String> asignaturas;
  final List<AlumnoMatricula> alumnos;

  String get titulo => '$grado $nombre · ${jornada[0].toUpperCase()}${jornada.substring(1)}';
}

/// Una clase del horario del docente. [dia]: 1 = lunes … 6 = sábado; horas "07:00:00".
class ClaseHorario {
  const ClaseHorario({
    required this.dia,
    required this.inicio,
    required this.fin,
    required this.asignatura,
    required this.seccion,
    this.aula,
  });

  factory ClaseHorario.fromJson(Map<String, dynamic> j) => ClaseHorario(
        dia: j['dia'] as int,
        inicio: j['inicio'] as String,
        fin: j['fin'] as String,
        asignatura: j['asignatura'] as String,
        seccion: j['seccion'] as String,
        aula: j['aula'] as String?,
      );

  final int dia;
  final String inicio;
  final String fin;
  final String asignatura;
  final String seccion;
  final String? aula;

  /// "07:00:00" → "7:00".
  static String hora(String t) {
    final p = t.split(':');
    return '${int.parse(p[0])}:${p[1]}';
  }
}

class MiCarga {
  const MiCarga({required this.centro, required this.anio, required this.secciones, this.horario = const []});

  factory MiCarga.fromJson(Map<String, dynamic> j) => MiCarga(
        centro: j['centro'] as String?,
        anio: j['anio'] as int?,
        secciones: [for (final s in (j['secciones'] as List).cast<Map<String, dynamic>>()) SeccionCentro.fromJson(s)],
        horario: [
          for (final c in ((j['horario'] as List?) ?? const []).cast<Map<String, dynamic>>()) ClaseHorario.fromJson(c),
        ],
      );

  final String? centro;
  final int? anio;
  final List<SeccionCentro> secciones;
  final List<ClaseHorario> horario;

  /// Clases de un día de la semana (DateTime.weekday: 1 = lunes).
  List<ClaseHorario> delDia(int dia) => horario.where((c) => c.dia == dia).toList();
}

/// La carga que el centro le asignó al docente. Null sin internet o sin centro: la app
/// sigue funcionando igual, esto sólo agrega información.
final miCargaProvider = FutureProvider<MiCarga?>((ref) async {
  try {
    final carga = await ref
        .watch(apiClientProvider)
        .get('/mi-centro/carga', parse: (d) => MiCarga.fromJson(d as Map<String, dynamic>));
    return carga.centro == null ? null : carga;
  } catch (_) {
    return null;
  }
});

/// Identidad comparable: sin guiones ni espacios, en mayúsculas (igual que el servidor).
String identidadComparable(String identidad) => identidad.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// Lo que difiere entre el cuadro de SACE de una asignatura y la matrícula del centro.
class Cotejo {
  const Cotejo({required this.seccion, required this.retirados, required this.faltan});

  final SeccionCentro seccion;

  /// En el cuadro, pero retirados o trasladados según el centro.
  final List<AlumnoMatricula> retirados;

  /// Matriculados en la sección que no están en el cuadro (el cuadro es anterior).
  final List<AlumnoMatricula> faltan;

  bool get hayDiferencias => retirados.isNotEmpty || faltan.isNotEmpty;
}

/// La sección del centro que corresponde a la lista de una asignatura: la que comparte más
/// alumnos, si comparte al menos la mitad del cuadro. Null si ninguna calza.
SeccionCentro? seccionDe(Iterable<String> identidadesCuadro, List<SeccionCentro> secciones) {
  final cuadro = identidadesCuadro.map(identidadComparable).toSet();
  if (cuadro.isEmpty) return null;
  SeccionCentro? mejor;
  var comunes = 0;
  for (final s in secciones) {
    final n = s.alumnos.where((a) => cuadro.contains(identidadComparable(a.identidad))).length;
    if (n > comunes) {
      mejor = s;
      comunes = n;
    }
  }
  return comunes * 2 >= cuadro.length ? mejor : null;
}

Cotejo? cotejar(List<Alumno> alumnosCuadro, List<SeccionCentro> secciones) {
  final seccion = seccionDe(alumnosCuadro.map((a) => a.identidad), secciones);
  if (seccion == null) return null;
  final cuadro = alumnosCuadro.map((a) => identidadComparable(a.identidad)).toSet();
  return Cotejo(
    seccion: seccion,
    retirados: [for (final a in seccion.alumnos) if (!a.activo && cuadro.contains(identidadComparable(a.identidad))) a],
    faltan: [for (final a in seccion.alumnos) if (a.activo && !cuadro.contains(identidadComparable(a.identidad))) a],
  );
}

/// Si el docente ya tiene en la app el cuadro de esta asignatura de la sección: alguna clase
/// cuya lista calce con la sección y cuyo nombre de asignatura coincida.
bool tieneCuadro(SeccionCentro seccion, String asignatura, List<ClaseResumen> clases, Map<String, Set<String>> identidades) {
  // La Ñ también se iguala: hay cuadros que escriben ESPANOL.
  String comparable(String texto) => normalizar(texto).replaceAll('Ñ', 'N');
  final buscada = comparable(asignatura);
  return clases.any((c) {
    final nombre = comparable(c.asignatura);
    if (!(nombre.contains(buscada) || buscada.contains(nombre))) return false;
    return seccionDe(identidades[c.id] ?? const {}, [seccion]) != null;
  });
}

/// Excusas y permisos del centro para un día ("2026-11-18"), por identidad comparable:
/// "Excusa: Gripe". Vacío sin centro o sin internet: la lista se pasa igual.
final excusasDelDiaProvider = FutureProvider.autoDispose.family<Map<String, String>, String>((ref, fecha) async {
  if (await ref.watch(miCargaProvider.future) == null) return const {};
  try {
    final lista = await ref.watch(apiClientProvider).get('/mi-centro/excusas',
        query: {'fecha': fecha}, parse: (d) => (d as List).cast<Map<String, dynamic>>());
    final excusas = <String, String>{};
    for (final e in lista) {
      final clave = identidadComparable(e['identidad'] as String);
      final texto = '${e['tipo'] == 'permiso' ? 'Permiso' : 'Excusa'}: ${e['motivo']}';
      excusas[clave] = excusas.containsKey(clave) ? '${excusas[clave]}; $texto' : texto;
    }
    return excusas;
  } catch (_) {
    return const {};
  }
});
