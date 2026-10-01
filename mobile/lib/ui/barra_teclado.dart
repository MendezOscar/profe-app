import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// Barra sobre el teclado mientras se captura: el teclado numérico del iPhone no trae
/// tecla de "Siguiente" ni de cerrar. "Siguiente" sigue el orden de lectura de la pantalla.
class BarraTeclado extends StatelessWidget {
  const BarraTeclado({super.key});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.viewInsetsOf(context).bottom == 0) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: Container(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant))),
        padding: const EdgeInsets.symmetric(horizontal: Espacio.s),
        height: 48,
        child: Row(
          children: [
            TextButton.icon(
              onPressed: () => FocusScope.of(context).previousFocus(),
              icon: const Icon(Icons.keyboard_arrow_up),
              label: const Text('Anterior'),
            ),
            TextButton.icon(
              onPressed: () => FocusScope.of(context).nextFocus(),
              icon: const Icon(Icons.keyboard_arrow_down),
              label: const Text('Siguiente'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
              child: const Text('Listo'),
            ),
          ],
        ),
      ),
    );
  }
}
