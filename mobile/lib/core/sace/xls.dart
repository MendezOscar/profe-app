import 'dart:typed_data';

import 'hoja.dart';

/// Lector de .xls (Excel 97-2003, BIFF8), el formato en que SACE entrega el cuadro.
/// Sólo lee: texto, números y celdas combinadas. Escribirlo lo hace la API con NPOI,
/// que conserva todo lo que acá se ignora (estilos, anchos, el nombre de la hoja).
class Xls {
  static bool esXls(Uint8List bytes) =>
      bytes.length >= 8 && bytes[0] == 0xD0 && bytes[1] == 0xCF && bytes[2] == 0x11 && bytes[3] == 0xE0;

  static List<Hoja> read(Uint8List bytes) {
    try {
      final contenedor = _Cfb(bytes);
      final libro = contenedor.stream('Workbook') ?? contenedor.stream('Book');
      if (libro == null) throw FormatoNoSoportado('El archivo no contiene un libro de Excel.');
      return _Biff8(libro).hojas();
    } on FormatoNoSoportado {
      rethrow;
    } on RangeError {
      throw FormatoNoSoportado('El archivo está dañado o incompleto.');
    }
  }
}

/// Contenedor OLE (Compound File Binary): un mini sistema de archivos con sectores
/// encadenados por una FAT. El libro vive en el stream "Workbook".
class _Cfb {
  _Cfb(this._bytes) : _data = ByteData.sublistView(_bytes) {
    _sectorSize = 1 << _data.getUint16(0x1E, Endian.little);
    _miniSectorSize = 1 << _data.getUint16(0x20, Endian.little);
    _miniCutoff = _data.getUint32(0x38, Endian.little);
    _fat = _leerFat();
    _miniFat = _cadena(_data.getUint32(0x3C, Endian.little))
        .expand((s) => _uint32s(_offset(s), _sectorSize ~/ 4))
        .toList();
    _entradas = _leerDirectorio(_data.getUint32(0x30, Endian.little));
    final raiz = _entradas.firstWhere((e) => e.tipo == 5);
    _miniStream = _leerCadena(raiz.inicio, null);
  }

  static const _finDeCadena = 0xFFFFFFFE;

  final Uint8List _bytes;
  final ByteData _data;
  late final int _sectorSize;
  late final int _miniSectorSize;
  late final int _miniCutoff;
  late final List<int> _fat;
  late final List<int> _miniFat;
  late final List<_Entrada> _entradas;
  late final Uint8List _miniStream;

  Uint8List? stream(String nombre) {
    final entrada = _entradas.where((e) => e.tipo == 2 && e.nombre == nombre).firstOrNull;
    if (entrada == null) return null;
    return entrada.tamano < _miniCutoff ? _leerMini(entrada.inicio, entrada.tamano) : _leerCadena(entrada.inicio, entrada.tamano);
  }

  int _offset(int sector) => (sector + 1) * _sectorSize;

  Iterable<int> _uint32s(int offset, int count) sync* {
    for (var i = 0; i < count; i++) {
      yield _data.getUint32(offset + i * 4, Endian.little);
    }
  }

  /// La FAT está repartida en sectores listados en la DIFAT: 109 en la cabecera y el
  /// resto en sectores DIFAT encadenados (sólo en archivos grandes).
  List<int> _leerFat() {
    final sectoresFat = <int>[..._uint32s(0x4C, 109).take(_data.getUint32(0x2C, Endian.little))];
    var difat = _data.getUint32(0x44, Endian.little);
    final porSector = _sectorSize ~/ 4 - 1;
    while (difat < _finDeCadena && sectoresFat.length < _data.getUint32(0x2C, Endian.little)) {
      sectoresFat.addAll(_uint32s(_offset(difat), porSector));
      difat = _data.getUint32(_offset(difat) + porSector * 4, Endian.little);
    }
    return [for (final s in sectoresFat) ..._uint32s(_offset(s), _sectorSize ~/ 4)];
  }

  List<int> _cadena(int inicio, [List<int>? fat]) {
    final tabla = fat ?? _fat;
    final sectores = <int>[];
    for (var s = inicio; s < _finDeCadena && sectores.length <= tabla.length; s = tabla[s]) {
      sectores.add(s);
    }
    return sectores;
  }

  Uint8List _leerCadena(int inicio, int? tamano) {
    final builder = BytesBuilder(copy: false);
    for (final s in _cadena(inicio)) {
      final offset = _offset(s);
      builder.add(Uint8List.sublistView(_bytes, offset, (offset + _sectorSize).clamp(0, _bytes.length)));
    }
    final todo = builder.takeBytes();
    return tamano == null ? todo : Uint8List.sublistView(todo, 0, tamano);
  }

  Uint8List _leerMini(int inicio, int tamano) {
    final builder = BytesBuilder(copy: false);
    for (final s in _cadena(inicio, _miniFat)) {
      builder.add(Uint8List.sublistView(_miniStream, s * _miniSectorSize, (s + 1) * _miniSectorSize));
    }
    return Uint8List.sublistView(builder.takeBytes(), 0, tamano);
  }

  List<_Entrada> _leerDirectorio(int inicio) {
    final dir = _leerCadena(inicio, null);
    final data = ByteData.sublistView(dir);
    return [
      for (var o = 0; o + 128 <= dir.length; o += 128)
        _Entrada(
          nombre: String.fromCharCodes(
              Uint16List.fromList([for (var i = 0; i < (data.getUint16(o + 0x40, Endian.little) ~/ 2 - 1).clamp(0, 31); i++) data.getUint16(o + i * 2, Endian.little)])),
          tipo: dir[o + 0x42],
          inicio: data.getUint32(o + 0x74, Endian.little),
          tamano: data.getUint32(o + 0x78, Endian.little),
        ),
    ];
  }
}

class _Entrada {
  const _Entrada({required this.nombre, required this.tipo, required this.inicio, required this.tamano});
  final String nombre;
  final int tipo; // 1 = carpeta, 2 = stream, 5 = raíz
  final int inicio;
  final int tamano;
}

/// Registros BIFF8: [tipo u16][largo u16][datos]. Del bloque global salen las hojas
/// (BOUNDSHEET) y los textos compartidos (SST); de cada hoja, sus celdas.
class _Biff8 {
  _Biff8(this._stream) : _data = ByteData.sublistView(_stream);

  final Uint8List _stream;
  final ByteData _data;

  static const _bof = 0x0809, _eof = 0x000A, _boundsheet = 0x0085, _sst = 0x00FC, _continue = 0x003C;
  static const _labelSst = 0x00FD, _label = 0x0204, _number = 0x0203, _rk = 0x027E, _mulRk = 0x00BD;
  static const _formula = 0x0006, _string = 0x0207, _mergedCells = 0x00E5;

  List<Hoja> hojas() {
    final hojas = <(String, int)>[];
    var sst = const <String>[];

    for (var pos = 0; pos + 4 <= _stream.length;) {
      final (tipo, largo) = _cabecera(pos);
      if (tipo == _boundsheet && _stream[pos + 4 + 5] == 0) {
        // Sólo hojas de cálculo (tipo 0): los gráficos y macros no traen celdas.
        final offset = _data.getUint32(pos + 4, Endian.little);
        final cch = _stream[pos + 4 + 6];
        final alto = _stream[pos + 4 + 7] & 1 == 1;
        hojas.add((_chars(pos + 4 + 8, cch, alto), offset));
      } else if (tipo == _sst) {
        sst = _leerSst(pos);
      } else if (tipo == _eof) {
        break;
      }
      pos += 4 + largo;
    }

    return [for (final (nombre, offset) in hojas) _leerHoja(nombre, offset, sst)];
  }

  (int, int) _cabecera(int pos) => (_data.getUint16(pos, Endian.little), _data.getUint16(pos + 2, Endian.little));

  Hoja _leerHoja(String nombre, int inicio, List<String> sst) {
    final cells = <int, Map<int, String>>{};
    final merges = <CellRange>[];
    void poner(int fila, int col, String texto) {
      if (texto.isNotEmpty) (cells[fila] ??= {})[col] = texto;
    }

    (int, int)? formulaTexto;
    var pos = inicio;
    if (_cabecera(pos).$1 == _bof) pos += 4 + _cabecera(pos).$2;

    while (pos + 4 <= _stream.length) {
      final (tipo, largo) = _cabecera(pos);
      final d = pos + 4;
      if (tipo == _eof) break;

      switch (tipo) {
        case _labelSst:
          final isst = _data.getUint32(d + 6, Endian.little);
          poner(_u16(d), _u16(d + 2), isst < sst.length ? sst[isst] : '');
        case _label:
          final cch = _u16(d + 6);
          poner(_u16(d), _u16(d + 2), _chars(d + 9, cch, _stream[d + 8] & 1 == 1));
        case _number:
          poner(_u16(d), _u16(d + 2), numeroComoTexto(_data.getFloat64(d + 6, Endian.little)));
        case _rk:
          poner(_u16(d), _u16(d + 2), numeroComoTexto(_rkValor(_data.getUint32(d + 6, Endian.little))));
        case _mulRk:
          final filaRk = _u16(d);
          final primera = _u16(d + 2);
          final celdas = (largo - 6) ~/ 6;
          for (var i = 0; i < celdas; i++) {
            poner(filaRk, primera + i, numeroComoTexto(_rkValor(_data.getUint32(d + 4 + i * 6 + 2, Endian.little))));
          }
        case _formula:
          // Resultado en caché: número, o 0xFFFF en los bytes 6-7 cuando es texto (viene
          // en el registro STRING siguiente) u otra cosa que no nos interesa.
          if (_u16(d + 12) != 0xFFFF) {
            poner(_u16(d), _u16(d + 2), numeroComoTexto(_data.getFloat64(d + 6, Endian.little)));
          } else if (_stream[d + 6] == 0) {
            formulaTexto = (_u16(d), _u16(d + 2));
          }
        case _string:
          if (formulaTexto case (final fila, final col)) {
            poner(fila, col, _chars(d + 3, _u16(d), _stream[d + 2] & 1 == 1));
            formulaTexto = null;
          }
        case _mergedCells:
          final cantidad = _u16(d);
          for (var i = 0; i < cantidad; i++) {
            final o = d + 2 + i * 8;
            merges.add(CellRange(_u16(o), _u16(o + 4), _u16(o + 2), _u16(o + 6)));
          }
      }
      pos += 4 + largo;
    }
    return Hoja(nombre, cells, merges);
  }

  int _u16(int pos) => _data.getUint16(pos, Endian.little);

  /// RK: número comprimido en 32 bits. Bit 1: entero de 30 bits; si no, los 30 bits altos
  /// de un double. Bit 0: el valor está multiplicado por 100.
  static double _rkValor(int rk) {
    final double valor;
    if (rk & 0x02 != 0) {
      valor = (rk.toSigned(32) >> 2).toDouble();
    } else {
      final bytes = ByteData(8)..setUint32(4, rk & 0xFFFFFFFC, Endian.little);
      valor = bytes.getFloat64(0, Endian.little);
    }
    return rk & 0x01 != 0 ? valor / 100 : valor;
  }

  /// Caracteres de un texto BIFF8: de 1 byte (Latin-1) o de 2 (UTF-16LE).
  String _chars(int pos, int cch, bool alto) => alto
      ? String.fromCharCodes([for (var i = 0; i < cch; i++) _u16(pos + i * 2)])
      : String.fromCharCodes(Uint8List.sublistView(_stream, pos, pos + cch));

  /// La tabla de textos compartidos. Puede continuar en registros CONTINUE, y un texto
  /// partido entre dos registros repite al inicio del siguiente el byte de 1 o 2 bytes.
  List<String> _leerSst(int pos) {
    final trozos = <Uint8List>[];
    var p = pos;
    do {
      final (_, largo) = _cabecera(p);
      trozos.add(Uint8List.sublistView(_stream, p + 4, p + 4 + largo));
      p += 4 + largo;
    } while (p + 4 <= _stream.length && _cabecera(p).$1 == _continue);

    final lector = _LectorTrozos(trozos);
    lector.saltar(4);
    final unicos = lector.u32();
    final textos = <String>[];
    for (var i = 0; i < unicos && !lector.fin; i++) {
      final cch = lector.u16();
      final flags = lector.u8();
      final runs = flags & 0x08 != 0 ? lector.u16() : 0;
      final ext = flags & 0x04 != 0 ? lector.u32() : 0;
      textos.add(lector.chars(cch, flags & 0x01 != 0));
      lector.saltar(runs * 4 + ext);
    }
    return textos;
  }
}

class _LectorTrozos {
  _LectorTrozos(this._trozos);

  final List<Uint8List> _trozos;
  var _trozo = 0;
  var _pos = 0;

  bool get fin => _trozo >= _trozos.length;

  void _avanzarSiHaceFalta() {
    while (!fin && _pos >= _trozos[_trozo].length) {
      _trozo++;
      _pos = 0;
    }
  }

  int u8() {
    _avanzarSiHaceFalta();
    return _trozos[_trozo][_pos++];
  }

  int u16() => u8() | (u8() << 8);
  int u32() => u16() | (u16() << 16);

  void saltar(int n) {
    for (var i = 0; i < n; i++) {
      u8();
    }
  }

  String chars(int cch, bool alto) {
    final codes = <int>[];
    var dosBytes = alto;
    for (var i = 0; i < cch; i++) {
      if (_pos >= _trozos[_trozo].length) {
        // Al cruzar a un CONTINUE, el primer byte dice si lo que sigue es de 1 o 2 bytes.
        _trozo++;
        _pos = 0;
        dosBytes = u8() & 1 == 1;
      }
      codes.add(dosBytes ? u16() : u8());
    }
    return String.fromCharCodes(codes);
  }
}
