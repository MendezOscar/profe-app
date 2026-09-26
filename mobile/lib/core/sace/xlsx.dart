import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'hoja.dart';

/// Lector mínimo de .xlsx directo sobre el XML. SACE entrega .xls, pero un docente
/// puede haberlo guardado como .xlsx: se acepta igual.
class Xlsx {
  static List<Hoja> read(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
      throw FormatoNoSoportado('El archivo no es un Excel (.xlsx) válido.');
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw FormatoNoSoportado('El archivo está dañado o incompleto.');
    }

    String? part(String path) {
      final file = archive.findFile(path);
      return file == null ? null : utf8.decode(file.content);
    }

    final workbookXml = part('xl/workbook.xml');
    final relsXml = part('xl/_rels/workbook.xml.rels');
    if (workbookXml == null || relsXml == null) {
      throw FormatoNoSoportado('El archivo no es un Excel (.xlsx) válido.');
    }

    final shared = _sharedStrings(part('xl/sharedStrings.xml'));
    final targets = {
      for (final rel in XmlDocument.parse(relsXml).findAllElements('Relationship', namespace: '*'))
        rel.getAttribute('Id')!: rel.getAttribute('Target')!,
    };

    final sheets = <Hoja>[];
    for (final sheet in XmlDocument.parse(workbookXml).findAllElements('sheet', namespace: '*')) {
      final relId = sheet.attributes.firstWhere((a) => a.name.local == 'id').value;
      final target = targets[relId];
      if (target == null) continue;
      final path = target.startsWith('/') ? target.substring(1) : 'xl/$target';
      final xml = part(path);
      if (xml == null) continue;
      sheets.add(_sheet(sheet.getAttribute('name') ?? path, xml, shared));
    }
    return sheets;
  }

  static List<String> _sharedStrings(String? xml) {
    if (xml == null) return const [];
    // Un texto con formato mixto viene partido en varios <t>: se juntan todos.
    return XmlDocument.parse(xml)
        .findAllElements('si', namespace: '*')
        .map((si) => si.findAllElements('t', namespace: '*').map((t) => t.innerText).join())
        .toList();
  }

  static Hoja _sheet(String name, String xml, List<String> shared) {
    final document = XmlDocument.parse(xml);
    final cells = <int, Map<int, String>>{};

    for (final c in document.findAllElements('c', namespace: '*')) {
      final ref = c.getAttribute('r');
      if (ref == null) continue;
      final (row, col) = parseRef(ref);
      final type = c.getAttribute('t');
      final value = c.findElements('v', namespace: '*').firstOrNull?.innerText;

      final text = switch (type) {
        's' => value == null ? '' : shared[int.parse(value)],
        'inlineStr' => c.findAllElements('t', namespace: '*').map((t) => t.innerText).join(),
        'str' || 'b' || 'e' => value ?? '',
        _ => switch (value == null ? null : double.tryParse(value)) {
            final double number => numeroComoTexto(number),
            _ => value ?? '',
          },
      };
      if (text.isEmpty) continue;
      (cells[row] ??= {})[col] = text;
    }

    final merges = document.findAllElements('mergeCell', namespace: '*').map((m) {
      final parts = m.getAttribute('ref')!.split(':');
      final (top, left) = parseRef(parts[0]);
      final (bottom, right) = parts.length > 1 ? parseRef(parts[1]) : (top, left);
      return CellRange(top, left, bottom, right);
    }).toList();

    return Hoja(name, cells, merges);
  }

  /// `AB12` → (11, 27), en base 0.
  static (int row, int col) parseRef(String ref) {
    var col = 0;
    var i = 0;
    while (i < ref.length && _isLetter(ref.codeUnitAt(i))) {
      col = col * 26 + (ref.codeUnitAt(i) & 0x1F);
      i++;
    }
    return (int.parse(ref.substring(i)) - 1, col - 1);
  }

  static bool _isLetter(int unit) => (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122);
}
