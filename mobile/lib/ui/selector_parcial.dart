import 'package:flutter/material.dart';

import '../core/planes/modelos.dart';
import '../theme/tokens.dart';

/// Los parciales del cuadro en un solo renglón, sin desplazarse: "I · II · III · IV" caben
/// en un teléfono de 360 px. Con fichas "PARCIAL I…IV" el cuarto quedaba cortado.
class SelectorParcial extends StatelessWidget {
  const SelectorParcial({super.key, required this.parciales, required this.actual, required this.onCambio});

  final List<Parcial> parciales;
  final Parcial actual;
  final ValueChanged<Parcial> onCambio;

  /// Alto que ocupa, para el `bottom` de una AppBar; crece con la letra del sistema.
  static double alto(BuildContext context) => 56 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);

  /// "PARCIAL III" → "III"; cualquier otro nombre se deja como viene.
  static String corto(String titulo) => titulo.replaceFirst(RegExp(r'^\s*PARCIAL\s+', caseSensitive: false), '');

  @override
  Widget build(BuildContext context) {
    final todosParciales = parciales.every((p) => corto(p.titulo) != p.titulo);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.s, Espacio.l, Espacio.s),
      child: Row(
        children: [
          if (todosParciales)
            Padding(
              padding: const EdgeInsets.only(right: Espacio.m),
              child: Text('Parcial', style: Theme.of(context).textTheme.labelLarge),
            ),
          Expanded(
            child: SegmentedButton<String>(
              style: SegmentedButton.styleFrom(shape: const RoundedRectangleBorder()),
              showSelectedIcon: false,
              segments: [
                for (final p in parciales)
                  ButtonSegment(
                    value: p.clave,
                    label: Semantics(
                      label: p.titulo,
                      excludeSemantics: true,
                      child: Text(corto(p.titulo), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
              ],
              selected: {actual.clave},
              onSelectionChanged: (s) => onCambio(parciales.firstWhere((p) => p.clave == s.first)),
            ),
          ),
        ],
      ),
    );
  }
}
