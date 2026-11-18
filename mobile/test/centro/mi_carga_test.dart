import 'package:flutter_test/flutter_test.dart';
import 'package:profeapp/core/centro/mi_carga.dart';
import 'package:profeapp/core/models/clase.dart';

SeccionCentro _seccion(String nombre, Map<String, String> alumnos, {List<String> asignaturas = const ['Español']}) =>
    SeccionCentro(
      id: nombre,
      grado: '7.º grado',
      nombre: nombre,
      jornada: 'matutina',
      esGuia: false,
      asignaturas: asignaturas,
      alumnos: [for (final e in alumnos.entries) AlumnoMatricula(identidad: e.key, nombre: e.key, estado: e.value)],
    );

List<Alumno> _cuadro(List<String> ids) => [for (final id in ids) Alumno(id: id, identidad: id, nombre: id)];

void main() {
  final a = _seccion('A', {'0801-2014-00001': 'activa', '0801201400002': 'retirada', '0801201400003': 'activa'});
  final b = _seccion('B', {'0801201400009': 'activa'});

  test('La lista del cuadro se coteja con la sección que comparte más alumnos', () {
    final cotejo = cotejar(_cuadro(['0801201400001', '0801201400002']), [b, a])!;
    expect(cotejo.seccion.nombre, 'A');
    expect(cotejo.retirados.map((x) => x.identidad), ['0801201400002']);
    expect(cotejo.faltan.map((x) => x.identidad), ['0801201400003']);
  });

  test('Sin al menos la mitad de alumnos en común no hay sección', () {
    expect(cotejar(_cuadro(['0801201400001', 'X1', 'X2']), [a]), isNull);
    expect(cotejar(const [], [a]), isNull);
  });

  test('El cuadro de una asignatura cuenta si calza la lista y el nombre, sin tildes', () {
    final clase = ClaseResumen(
      id: 'c1',
      asignatura: 'ESPANOL',
      gradoSeccion: '',
      jornada: '',
      centro: '',
      alumnos: 2,
      actualizadaEn: DateTime(2027),
    );
    final ids = {'c1': {'0801201400001', '0801201400003'}};
    expect(tieneCuadro(a, 'Español', [clase], ids), isTrue);
    expect(tieneCuadro(a, 'Matemáticas', [clase], ids), isFalse);
    expect(tieneCuadro(b, 'Español', [clase], ids), isFalse);
  });
}
