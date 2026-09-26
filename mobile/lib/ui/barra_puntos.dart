import 'package:flutter/material.dart';

import '../core/planes/calculo_parcial.dart';

/// Cuánto de los 100 puntos lleva algo (el plan, las actividades, un alumno).
/// Se pinta en rojo si se pasa del total.
class BarraPuntos extends StatelessWidget {
  const BarraPuntos({super.key, required this.valor, this.total = 100, this.etiqueta, this.alto = 8});

  final double valor;
  final double total;
  final String? etiqueta;
  final double alto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final excede = valor > total;
    final progreso = total <= 0 ? 0.0 : (valor / total).clamp(0.0, 1.0);
    final resumen = '${formatoPuntos(valor)} / ${formatoPuntos(total)} pts';

    return Semantics(
      label: etiqueta == null ? resumen : '$etiqueta: $resumen',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (etiqueta != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(child: Text(etiqueta!, style: text.labelMedium)),
                  Text(resumen,
                      style: text.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600, color: excede ? scheme.error : scheme.onSurface)),
                ],
              ),
            ),
          LinearProgressIndicator(
            value: progreso,
            minHeight: alto,
            borderRadius: BorderRadius.zero,
            backgroundColor: scheme.primaryContainer,
            color: excede ? scheme.error : scheme.primary,
          ),
        ],
      ),
    );
  }
}
