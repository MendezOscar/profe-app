import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

/// Abre el menú de compartir del teléfono con un PDF: WhatsApp, correo, guardar o imprimir.
/// En la computadora, si el navegador no puede compartir, se descarga.
Future<void> compartirPdf(BuildContext context, Uint8List bytes, String nombre) async {
  final caja = context.findRenderObject() as RenderBox?;
  final archivo = nombre.endsWith('.pdf') ? nombre : '$nombre.pdf';
  await SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: archivo)],
    fileNameOverrides: [archivo],
    // En iPad el menú necesita saber de dónde sale.
    sharePositionOrigin: caja == null || !caja.hasSize ? null : caja.localToGlobal(Offset.zero) & caja.size,
  ));
}

/// Igual que [compartirPdf], para otro tipo de archivo (el .zip de cuadros de SACE).
Future<void> compartirArchivo(BuildContext context, Uint8List bytes, String nombre, String mimeType) async {
  final caja = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(bytes, mimeType: mimeType, name: nombre)],
    fileNameOverrides: [nombre],
    sharePositionOrigin: caja == null || !caja.hasSize ? null : caja.localToGlobal(Offset.zero) & caja.size,
  ));
}

/// Nombre de archivo sin caracteres que algunos sistemas rechazan.
String nombreArchivo(String texto) =>
    texto.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
