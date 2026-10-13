import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';

import 'preferencias.dart';

const _exportados = 'profeapp.cuadros_exportados';
const _pedidaEl = 'profeapp.resena_pedida_el';

/// Pide la calificación en la tienda después de un logro (exportar el cuadro), desde la
/// segunda vez y no más de una vez cada 4 meses. La tienda decide si muestra el cuadro:
/// Apple y Google limitan cuántas veces aparece, así que puede no salir nada.
Future<void> pedirResenaSiToca(WidgetRef ref) async {
  if (kIsWeb) return;
  final prefs = ref.read(preferenciasProvider);
  final exportados = (prefs.getInt(_exportados) ?? 0) + 1;
  await prefs.setInt(_exportados, exportados);
  if (exportados < 2) return;

  final pedida = DateTime.tryParse(prefs.getString(_pedidaEl) ?? '');
  if (pedida != null && DateTime.now().difference(pedida).inDays < 120) return;

  final review = InAppReview.instance;
  if (!await review.isAvailable()) return;
  await prefs.setString(_pedidaEl, DateTime.now().toIso8601String());
  await review.requestReview();
}
