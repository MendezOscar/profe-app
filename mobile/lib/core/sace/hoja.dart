/// El archivo no se puede leer como cuadro de SACE. El mensaje es para el docente.
class FormatoNoSoportado implements Exception {
  FormatoNoSoportado(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Rango de celdas combinadas, en índices base 0.
class CellRange {
  const CellRange(this.top, this.left, this.bottom, this.right);
  final int top, left, bottom, right;

  bool contains(int row, int col) => row >= top && row <= bottom && col >= left && col <= right;
}

/// Una hoja ya leída, venga de un .xls o de un .xlsx: sólo texto, filas y columnas en
/// base 0. No se interpreta nada del cuadro acá; eso es de CuadroSace.
class Hoja {
  Hoja(this.nombre, this._cells, this.merges);

  /// Nombre de la pestaña. En los cuadros de SACE parece ser un identificador interno
  /// (`19847174~1~1123`): el exportador la busca por este nombre y no lo cambia.
  final String nombre;
  final Map<int, Map<int, String>> _cells;
  final List<CellRange> merges;

  Iterable<int> get rowIndexes => _cells.keys.toList()..sort();

  int lastColumn(int row) {
    final cols = _cells[row]?.keys;
    return cols == null || cols.isEmpty ? -1 : cols.reduce((a, b) => a > b ? a : b);
  }

  String raw(int row, int col) => _cells[row]?[col] ?? '';

  /// Texto visible: una celda dentro de una combinación muestra el de su esquina superior izquierda.
  String text(int row, int col) {
    for (final merge in merges) {
      if (merge.contains(row, col)) return raw(merge.top, merge.left).trim();
    }
    return raw(row, col).trim();
  }

  CellRange? mergeAt(int row, int col) {
    for (final merge in merges) {
      if (merge.contains(row, col)) return merge;
    }
    return null;
  }
}

/// Los números se guardan como texto sin ".0" cuando son enteros: así una nota 81 se lee
/// igual venga del .xls (double) o del .xlsx (texto).
String numeroComoTexto(double value) =>
    value == value.roundToDouble() && value.abs() < 1e15 ? value.toStringAsFixed(0) : value.toString();
