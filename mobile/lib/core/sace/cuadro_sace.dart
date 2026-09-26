import 'dart:typed_data';

import 'hoja.dart';
import 'xls.dart';
import 'xlsx.dart';

/// Qué se captura en una columna. Define la validación y el teclado; lo que la app no
/// reconoce queda como [otro] y se acepta como número sin más reglas.
enum TipoColumna {
  nota(0, 100),
  inasistencias(0, 999),
  nivelacion(0, 100),
  otro(0, 9999);

  const TipoColumna(this.minimo, this.maximo);
  final int minimo;
  final int maximo;

  static TipoColumna desde(String nombre) {
    final n = normalizar(nombre);
    if (n.contains('INASIST')) return TipoColumna.inasistencias;
    if (n.contains('NIVELACION')) return TipoColumna.nivelacion;
    if (n.contains('NOTA') || n.contains('RECUPERACION')) return TipoColumna.nota;
    return TipoColumna.otro;
  }
}

/// Una columna editable tal como la trae la plantilla: el grupo es el encabezado de arriba
/// (`PARCIAL I`) y el nombre el de abajo (`NOTA TOTAL`). Sin subencabezado, son el mismo.
class ColumnaCuadro {
  const ColumnaCuadro({required this.grupo, required this.nombre, required this.col});

  final String grupo;
  final String nombre;

  /// Índice de columna en la hoja (base 0).
  final int col;

  TipoColumna get tipo => TipoColumna.desde(nombre);

  /// Identidad estable entre versiones de la plantilla: al reimportar, lo capturado se
  /// cruza por esto y no por la posición, que puede correrse si SACE agrega columnas.
  String get clave => claveDe(grupo, nombre);

  static String claveDe(String grupo, String nombre) => '${normalizar(grupo)}|${normalizar(nombre)}';
}

class AlumnoCuadro {
  const AlumnoCuadro({
    required this.documento,
    required this.identidad,
    required this.nombre,
    required this.fila,
    required this.valores,
  });

  final String documento;
  final String identidad;
  final String nombre;

  /// Fila en la hoja (base 0): el exportador escribe ahí.
  final int fila;

  /// Lo que la plantilla ya traía lleno, por [ColumnaCuadro.clave].
  final Map<String, int> valores;
}

/// El cuadro de calificaciones de una clase, interpretado desde el archivo de SACE.
/// No asume cuántos parciales hay ni qué columnas tiene cada uno: lo descubre por los
/// encabezados. Ver docs/formato-sace.md.
class CuadroSace {
  const CuadroSace({
    required this.hoja,
    required this.columnas,
    required this.alumnos,
    this.codigoCentro,
    this.centro,
    this.modalidad,
    this.gradoSeccion,
    this.jornada,
    this.asignatura,
  });

  /// Nombre de la hoja con el cuadro; en SACE parece un identificador interno y el
  /// exportador escribe en esa misma hoja.
  final String hoja;
  final List<ColumnaCuadro> columnas;
  final List<AlumnoCuadro> alumnos;

  final String? codigoCentro;
  final String? centro;
  final String? modalidad;
  final String? gradoSeccion;
  final String? jornada;
  final String? asignatura;

  /// Identifica la clase entre importaciones: el mismo cuadro bajado otra vez (con una
  /// columna nueva, por ejemplo) actualiza la clase en vez de duplicarla.
  String get claveClase => [codigoCentro, modalidad, gradoSeccion, jornada, asignatura]
      .map((p) => normalizar(p ?? ''))
      .join('|');

  static CuadroSace fromBytes(Uint8List bytes) {
    for (final sheet in Xls.esXls(bytes) ? Xls.read(bytes) : Xlsx.read(bytes)) {
      final cuadro = parse(sheet);
      if (cuadro != null) return cuadro;
    }
    throw FormatoNoSoportado(
        'No se encontró el cuadro de notas (falta la columna IDENTIDAD). ¿Es el archivo que descargaste de SACE?');
  }

  /// Null si la hoja no tiene la forma de un cuadro de SACE.
  static CuadroSace? parse(Hoja sheet) {
    int? headerRow, idCol, docCol, nameCol;
    for (final row in sheet.rowIndexes) {
      for (var col = 0; col <= sheet.lastColumn(row); col++) {
        if (normalizar(sheet.raw(row, col)) == 'IDENTIDAD') {
          headerRow = row;
          idCol = col;
          break;
        }
      }
      if (headerRow != null) break;
    }
    if (headerRow == null || idCol == null) return null;

    for (var col = 0; col <= sheet.lastColumn(headerRow); col++) {
      final text = normalizar(sheet.raw(headerRow, col));
      if (text == 'DOCUMENTO') docCol = col;
      if (text.contains('NOMBRE')) nameCol = col;
    }
    nameCol ??= idCol + 1;

    int rightEdge(int col) => sheet.mergeAt(headerRow!, col)?.right ?? col;
    final firstDataCol = [idCol, nameCol, ?docCol].map(rightEdge).reduce((a, b) => a > b ? a : b) + 1;

    final subRow = headerRow + 1;
    var lastCol = [sheet.lastColumn(headerRow), sheet.lastColumn(subRow)].reduce((a, b) => a > b ? a : b);
    for (final merge in sheet.merges) {
      if (merge.top == headerRow && merge.right > lastCol) lastCol = merge.right;
    }

    final columnas = <ColumnaCuadro>[];
    var hasSubRow = false;
    for (var col = firstDataCol; col <= lastCol; col++) {
      final group = sheet.text(headerRow, col);
      final sub = sheet.text(subRow, col);
      final subMerge = sheet.mergeAt(subRow, col);
      final subIsOwn = sub.isNotEmpty && (subMerge == null || subMerge.top == subRow);

      if (subIsOwn) {
        // Subcolumna de un grupo; si viene combinada a lo ancho, cuenta una sola vez.
        if (subMerge != null && col != subMerge.left) continue;
        hasSubRow = true;
        columnas.add(ColumnaCuadro(grupo: group.isEmpty ? sub : group, nombre: sub, col: col));
      } else if (group.isNotEmpty) {
        // Columna sin subencabezado (RECUPERACIÓN combinada hacia abajo, por ejemplo).
        final groupMerge = sheet.mergeAt(headerRow, col);
        if (groupMerge != null && col != groupMerge.left) continue;
        columnas.add(ColumnaCuadro(grupo: group, nombre: group, col: col));
      }
    }

    final idBottom = sheet.mergeAt(headerRow, idCol)?.bottom ?? headerRow;
    final dataStart = [idBottom + 1, hasSubRow ? subRow + 1 : headerRow + 1].reduce((a, b) => a > b ? a : b);

    final rows = sheet.rowIndexes.toList();
    final lastRow = rows.isEmpty ? -1 : rows.last;
    final alumnos = <AlumnoCuadro>[];
    for (var row = dataStart; row <= lastRow; row++) {
      if (_esFinDelDocumento(sheet, row)) break;
      final identidad = _identidad(sheet.raw(row, idCol));
      final nombre = sheet.raw(row, nameCol).trim();
      if (identidad.isEmpty && nombre.isEmpty) break;

      alumnos.add(AlumnoCuadro(
        documento: docCol == null ? '' : sheet.raw(row, docCol).trim(),
        identidad: identidad,
        nombre: nombre,
        fila: row,
        valores: {
          for (final c in columnas)
            if (_entero(sheet.raw(row, c.col)) case final valor?) c.clave: valor,
        },
      ));
    }

    final encabezado = _Encabezado.desde([
      for (final row in rows.where((r) => r < headerRow!))
        if (_primerTexto(sheet, row) case final texto?) texto,
    ]);

    return CuadroSace(
      hoja: sheet.nombre,
      columnas: columnas,
      alumnos: alumnos,
      codigoCentro: encabezado.codigoCentro,
      centro: encabezado.centro,
      modalidad: encabezado.modalidad,
      gradoSeccion: encabezado.gradoSeccion,
      jornada: encabezado.jornada,
      asignatura: encabezado.asignatura,
    );
  }

  static bool _esFinDelDocumento(Hoja sheet, int row) {
    for (var col = 0; col <= sheet.lastColumn(row); col++) {
      if (normalizar(sheet.raw(row, col)).contains('FIN DEL DOCUMENTO')) return true;
    }
    return false;
  }

  static String? _primerTexto(Hoja sheet, int row) {
    for (var col = 0; col <= sheet.lastColumn(row); col++) {
      final text = sheet.raw(row, col).trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  /// La identidad llega como texto, pero si alguien abrió y guardó el archivo, Excel pudo
  /// volverla número y comerse los ceros de la izquierda: se reponen a 13 dígitos.
  static String _identidad(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return text;
    final asNumber = double.tryParse(text);
    final digits = asNumber != null && !RegExp(r'^\d+$').hasMatch(text) ? asNumber.toStringAsFixed(0) : text;
    return RegExp(r'^\d{1,12}$').hasMatch(digits) ? digits.padLeft(13, '0') : digits;
  }

  static int? _entero(String raw) {
    final value = double.tryParse(raw.trim());
    return value?.round();
  }
}

class _Encabezado {
  String? codigoCentro, centro, modalidad, gradoSeccion, jornada, asignatura;

  /// Las líneas de arriba de la tabla, en orden. Se reconocen por su contenido y no por
  /// su posición; lo que no calza con nada y viene al final es la asignatura.
  static _Encabezado desde(List<String> lineas) {
    final e = _Encabezado();
    final sobrantes = <String>[];
    for (final linea in lineas) {
      final n = normalizar(linea);
      if (linea.contains('|') && e.centro == null) {
        final partes = linea.split('|');
        e.codigoCentro = partes.first.trim();
        e.centro = partes.skip(1).join('|').trim();
      } else if (n.startsWith('MODALIDAD')) {
        e.modalidad = linea.substring(linea.indexOf(':') + 1).trim();
      } else if (n.startsWith('JORNADA')) {
        e.jornada = linea.trim();
      } else if (n.contains('SECCION') && (n.contains('GRADO') || n.contains('CURSO') || n.contains('AÑO'))) {
        e.gradoSeccion = linea.trim();
      } else {
        sobrantes.add(linea.trim());
      }
    }
    if (sobrantes.isNotEmpty) e.asignatura = sobrantes.last;
    return e;
  }
}

/// Mayúsculas sin tildes y con espacios simples: los encabezados de SACE no siempre
/// traen las tildes y a veces vienen con espacios de más.
String normalizar(String text) {
  const from = 'ÁÉÍÓÚÜáéíóúü';
  const to = 'AEIOUUAEIOUU';
  final buffer = StringBuffer();
  for (final char in text.split('')) {
    final i = from.indexOf(char);
    buffer.write(i >= 0 ? to[i] : char);
  }
  return buffer.toString().toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}
