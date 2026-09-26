import 'dart:convert';
import 'dart:typed_data';

import '../api/api_client.dart';
import '../models/clase.dart';

/// Pide a la API el cuadro relleno. Escribir un .xls sin romperlo lo hace el servidor con
/// NPOI; necesita internet, igual que subirlo a SACE. Ver docs/formato-sace.md.
class ExportadorCuadro {
  ExportadorCuadro(this._api);

  final ApiClient _api;

  Future<Uint8List> exportar(CuadroParaExportar cuadro) => _api.postBytes('/cuadros/exportar', body: {
        'archivoBase64': base64Encode(cuadro.archivo),
        'nombreArchivo': cuadro.nombreArchivo,
        'hoja': cuadro.hoja,
        'celdas': [
          for (final c in cuadro.celdas) {'fila': c.fila, 'col': c.col, 'valor': c.valor},
        ],
      });
}
