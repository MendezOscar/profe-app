import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../../core/api/api_exception.dart';
import '../../../core/informes/compartir.dart';
import '../../../core/informes/informes_pdf.dart';
import '../../../core/providers.dart';
import '../../../theme/tokens.dart';
import 'comun_centro.dart';

/// Foto del alumno (JPEG) o null si no tiene.
final fotoAlumnoProvider = FutureProvider.autoDispose.family<Uint8List?, String>((ref, alumno) async {
  try {
    return await ref.watch(apiClientProvider).getBytes('/centro/alumnos/$alumno/foto');
  } on ApiException catch (e) {
    if (e.statusCode == 404) return null;
    rethrow;
  }
});

final marcaCentroProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) =>
    ref.watch(apiClientProvider).get('/centro/marca', parse: (d) => d as Map<String, dynamic>));

/// Foto tipo carnet: recorta al centro en 3:4 y la deja en 300 × 400 JPEG (~30 KB).
Uint8List? _reducirFoto(Uint8List bytes) {
  final original = img.decodeImage(bytes);
  if (original == null) return null;
  final orientada = img.bakeOrientation(original);
  final w = orientada.width, h = orientada.height;
  final (cw, ch) = w * 4 > h * 3 ? (h * 3 ~/ 4, h) : (w, w * 4 ~/ 3);
  final recorte = img.copyCrop(orientada, x: (w - cw) ~/ 2, y: (h - ch) ~/ 2, width: cw, height: ch);
  return img.encodeJpg(img.copyResize(recorte, width: 300, height: 400, interpolation: img.Interpolation.average), quality: 82);
}

/// Logo en PNG (conserva la transparencia), con su lado mayor en 400 px.
Uint8List? _reducirLogo(Uint8List bytes) {
  final original = img.decodeImage(bytes);
  if (original == null) return null;
  final grande = original.width >= original.height;
  final reducido = (grande ? original.width : original.height) <= 400
      ? original
      : img.copyResize(original, width: grande ? 400 : null, height: grande ? null : 400, interpolation: img.Interpolation.average);
  return img.encodePng(reducido, level: 9);
}

Future<Uint8List?> _elegirImagen(BuildContext context, Uint8List? Function(Uint8List) reducir) async {
  final messenger = ScaffoldMessenger.of(context);
  final r = await FilePicker.pickFiles(type: FileType.image, withData: true);
  final bytes = r?.files.single.bytes;
  if (bytes == null) return null;
  final listo = await compute(reducir, bytes);
  if (listo == null) messenger.showSnackBar(const SnackBar(content: Text('No se pudo leer esa imagen. Prueba con un JPG o PNG.')));
  return listo;
}

/// En la ficha: la foto para el carnet, cambiarla o quitarla, e imprimir el carnet.
class FotoCarnet extends ConsumerWidget {
  const FotoCarnet({super.key, required this.alumnoId, required this.nombre, required this.editar, required this.activo});

  final String alumnoId;
  final String nombre;
  final bool editar;
  final bool activo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foto = ref.watch(fotoAlumnoProvider(alumnoId));
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 90,
          height: 120,
          decoration: BoxDecoration(border: Border.all(color: scheme.outlineVariant), color: scheme.surfaceContainerHighest),
          child: switch (foto) {
            AsyncData(value: final bytes?) => Image.memory(bytes, fit: BoxFit.cover, semanticLabel: 'Foto de $nombre'),
            AsyncData() => Icon(Icons.person_outline, size: 48, color: scheme.onSurfaceVariant),
            AsyncError() => Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
        const SizedBox(width: Espacio.l),
        Expanded(
          child: Wrap(
            direction: Axis.vertical,
            spacing: Espacio.xs,
            children: [
              if (editar)
                TextButton.icon(
                  onPressed: () => _cambiar(context, ref),
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(foto.valueOrNull == null ? 'Subir foto' : 'Cambiar foto'),
                ),
              if (editar && foto.valueOrNull != null)
                TextButton.icon(
                  onPressed: () async {
                    if (await accionCentro(context, ref, (api) => api.delete('/centro/alumnos/$alumnoId/foto'))) {
                      ref.invalidate(fotoAlumnoProvider(alumnoId));
                    }
                  },
                  icon: const Icon(Icons.hide_image_outlined),
                  label: const Text('Quitar foto'),
                ),
              if (activo)
                TextButton.icon(
                  onPressed: () => imprimirCarnets(context, ref, '/centro/alumnos/$alumnoId/carnet', 'Carnet $nombre'),
                  icon: const Icon(Icons.badge_outlined),
                  label: const Text('Carnet estudiantil'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _cambiar(BuildContext context, WidgetRef ref) async {
    final bytes = await _elegirImagen(context, _reducirFoto);
    if (bytes == null || !context.mounted) return;
    if (await accionCentro(context, ref, (api) => api.put<void>('/centro/alumnos/$alumnoId/foto', body: {'base64': base64Encode(bytes)}),
        listo: 'Foto guardada.')) {
      ref.invalidate(fotoAlumnoProvider(alumnoId));
    }
  }
}

/// Baja los datos (de un alumno o de una sección) y comparte el PDF de carnets.
Future<void> imprimirCarnets(BuildContext context, WidgetRef ref, String ruta, String nombre) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final datos = await ref.read(apiClientProvider).get(ruta, parse: (d) => d as Map<String, dynamic>);
    if ((datos['alumnos'] as List).isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('No hay alumnos activos para imprimir.')));
      return;
    }
    final sinFoto = (datos['alumnos'] as List).where((a) => a['foto'] == null).length;
    final bytes = await InformesPdf.carnets(datos);
    if (context.mounted) await compartirPdf(context, bytes, nombreArchivo(nombre));
    if (sinFoto > 0) {
      messenger.showSnackBar(SnackBar(
          content: Text('$sinFoto ${sinFoto == 1 ? 'carnet salió' : 'carnets salieron'} sin foto: '
              'súbela en la ficha del alumno o pégala impresa en el recuadro.')));
    }
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.isNetworkError ? 'Necesitas internet.' : e.message)));
  }
}

const _paleta = ['#1F4E79', '#2B59C3', '#0B6E4F', '#2E7D32', '#8B1E3F', '#C62828', '#6A1B9A', '#E65100', '#B8860B', '#37474F'];

Color _deHex(String hex) => Color(int.parse('FF${hex.substring(1)}', radix: 16));

/// Logo, color y lema del centro que lleva el carnet.
Future<void> disenoCarnet(BuildContext context, WidgetRef ref) async {
  final Map<String, dynamic> marca;
  try {
    marca = await ref.read(marcaCentroProvider.future);
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.isNetworkError ? 'Necesitas internet.' : e.message)));
    }
    return;
  }
  if (!context.mounted) return;
  var color = marca['color'] as String;
  var tieneLogo = marca['tieneLogo'] == true;
  final lema = TextEditingController(text: marca['lema'] as String?);
  final hex = TextEditingController(text: color);

  await showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (dialogo, setState) => DialogoForm(
        titulo: 'Diseño del carnet',
        contenido: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('LOGO', style: Theme.of(dialogo).textTheme.labelSmall),
            const SizedBox(height: Espacio.xs),
            Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(border: Border.all(color: Theme.of(dialogo).colorScheme.outlineVariant)),
                  child: tieneLogo
                      ? FutureBuilder(
                          future: ref.read(apiClientProvider).getBytes('/centro/marca/logo'),
                          builder: (_, s) => s.hasData ? Image.memory(s.data!, fit: BoxFit.contain) : const SizedBox(),
                        )
                      : const Icon(Icons.image_outlined),
                ),
                const SizedBox(width: Espacio.m),
                Expanded(
                  child: Wrap(
                    children: [
                      TextButton(
                        onPressed: () async {
                          final bytes = await _elegirImagen(dialogo, _reducirLogo);
                          if (bytes == null || !dialogo.mounted) return;
                          if (await accionCentro(dialogo, ref,
                              (api) => api.put<void>('/centro/marca/logo', body: {'base64': base64Encode(bytes)}))) {
                            setState(() => tieneLogo = true);
                          }
                        },
                        child: Text(tieneLogo ? 'Cambiar logo' : 'Subir logo'),
                      ),
                      if (tieneLogo)
                        TextButton(
                          onPressed: () async {
                            if (await accionCentro(dialogo, ref, (api) => api.delete('/centro/marca/logo'))) {
                              setState(() => tieneLogo = false);
                            }
                          },
                          child: const Text('Quitar'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Espacio.l),
            Text('COLOR DEL CENTRO', style: Theme.of(dialogo).textTheme.labelSmall),
            const SizedBox(height: Espacio.xs),
            Wrap(
              spacing: Espacio.xs,
              runSpacing: Espacio.xs,
              children: [
                for (final p in _paleta)
                  InkWell(
                    onTap: () => setState(() {
                      color = p;
                      hex.text = p;
                    }),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _deHex(p),
                        border: Border.all(
                            width: color.toUpperCase() == p ? 3 : 0,
                            color: Theme.of(dialogo).colorScheme.onSurface),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Espacio.s),
            TextField(
              controller: hex,
              maxLength: 7,
              decoration: const InputDecoration(labelText: 'Otro color (#RRGGBB)', counterText: ''),
              onChanged: (v) {
                if (RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(v)) setState(() => color = v.toUpperCase());
              },
            ),
            const SizedBox(height: Espacio.m),
            TextField(
              controller: lema,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Lema (opcional)', hintText: 'Ciencia, disciplina y valores'),
            ),
          ],
        ),
        guardar: () async {
          final ok = await accionCentro(dialogo, ref,
              (api) => api.put<void>('/centro/marca', body: {'color': color, 'lema': lema.text}),
              listo: 'Diseño del carnet guardado.');
          if (ok) ref.invalidate(marcaCentroProvider);
          return ok;
        },
      ),
    ),
  );
}
