import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Arma un .xlsx mínimo en memoria. Los textos van a sharedStrings como los escribe
/// Excel; los enteros, como número.
Uint8List xlsxDePrueba(Map<String, Object> celdas, {List<String> combinadas = const []}) {
  final textos = <String>[];
  final filas = <int, List<String>>{};

  for (final MapEntry(key: ref, value: valor) in celdas.entries) {
    final fila = int.parse(ref.replaceAll(RegExp('[A-Z]'), ''));
    final String xml;
    if (valor is int) {
      xml = '<c r="$ref"><v>$valor</v></c>';
    } else {
      textos.add(valor as String);
      xml = '<c r="$ref" t="s"><v>${textos.length - 1}</v></c>';
    }
    (filas[fila] ??= []).add(xml);
  }

  final sheetData = (filas.keys.toList()..sort()).map((f) => '<row r="$f">${filas[f]!.join()}</row>').join();
  final merges = combinadas.isEmpty
      ? ''
      : '<mergeCells count="${combinadas.length}">${combinadas.map((m) => '<mergeCell ref="$m"/>').join()}</mergeCells>';
  const ns = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"';
  const nsR = 'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';

  final archive = Archive()
    ..addFile(ArchiveFile.string('xl/workbook.xml',
        '<?xml version="1.0"?><workbook $ns $nsR><sheets><sheet name="Notas" sheetId="1" r:id="rId1"/></sheets></workbook>'))
    ..addFile(ArchiveFile.string('xl/_rels/workbook.xml.rels',
        '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '</Relationships>'))
    ..addFile(ArchiveFile.string('xl/sharedStrings.xml',
        '<?xml version="1.0"?><sst $ns>${textos.map((t) => '<si><t>${_escapar(t)}</t></si>').join()}</sst>'))
    ..addFile(ArchiveFile.string(
        'xl/worksheets/sheet1.xml', '<?xml version="1.0"?><worksheet $ns><sheetData>$sheetData</sheetData>$merges</worksheet>'));

  return ZipEncoder().encodeBytes(archive);
}

/// Media, dos parciales, nivelación sólo en el Parcial I (captura del BTP en Contaduría).
Uint8List cuadroMedia({bool conNivelacionParcial2 = false}) => xlsxDePrueba({
      'A1': '080100642M02 | ESPANA JESUS MILLA SELVA',
      'A2': 'MODALIDAD: BACHILLERATO TÉCNICO PROFESIONAL EN CONTADURÍA Y FINANZAS',
      'A3': 'ONCEAVO GRADO SECCIÓN 12',
      'A4': 'JORNADA VESPERTINA',
      'A5': 'LENGUA Y LITERATURA',
      'A6': 'DOCUMENTO', 'B6': 'IDENTIDAD', 'C6': 'NOMBRE',
      'D6': 'PARCIAL I', 'G6': 'PARCIAL II',
      (conNivelacionParcial2 ? 'J6' : 'I6'): 'RECUPERACIÓN',
      'D7': 'INASISTENCIAS', 'E7': 'NOTA TOTAL', 'F7': 'NIVELACIÓN',
      'G7': 'INASISTENCIAS', 'H7': 'NOTA TOTAL',
      if (conNivelacionParcial2) 'I7': 'NIVELACIÓN',
      'A8': 'HND', 'B8': '0801200101758', 'C8': 'ADRIANA YISSEL HERNANDEZ SIERRA',
      'D8': 0, 'E8': 72, 'F8': 0, 'G8': 0, 'H8': 70,
      'A9': 'HND', 'B9': '0000000164448', 'C9': 'EMELY NAHOMY VICENTE ANDINO',
      'D9': 0, 'E9': 60, 'F9': 10, 'G9': 0, 'H9': 50, (conNivelacionParcial2 ? 'J9' : 'I9'): 51,
      'A10': 'HND', 'B10': '0815199800344', 'C10': 'JHEIMY MABEL VALLADARES LOPEZ',
      'D10': 0, 'G10': 0,
      'A11': '**********Fin del documento**********',
      'A12': 'Nota: Únicamente ingrese notas en las casillas generadas por el sistema para este documento.',
    }, combinadas: [
      'A1:I1', 'A2:I2', 'A3:I3', 'A4:I4', 'A5:I5',
      'A6:A7', 'B6:B7', 'C6:C7',
      'D6:F6', conNivelacionParcial2 ? 'G6:I6' : 'G6:H6',
      conNivelacionParcial2 ? 'J6:J7' : 'I6:I7',
      'A11:I11', 'A12:I12',
    ]);

String _escapar(String t) => t.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
