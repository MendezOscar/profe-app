import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/cobro.dart';
import '../core/providers.dart';
import '../theme/tokens.dart';

/// Franja arriba del contenido cuando el plan está por vencer, en gracia o ya de sólo
/// lectura. En la app de las tiendas sólo informa; los datos para pagar se ven en la web,
/// porque las tiendas no admiten indicar en la app cómo pagar por fuera.
class AvisoCobro extends ConsumerWidget {
  const AvisoCobro({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cobro = ref.watch(sessionProvider.select((s) => s?.cobro));
    if (cobro == null || !cobro.pideAtencion) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final grave = cobro.estado != EstadoCobro.porVencer;
    final fondo = grave ? scheme.errorContainer : scheme.secondaryContainer;
    final tinta = grave ? scheme.onErrorContainer : scheme.onSecondaryContainer;

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: fondo,
        padding: const EdgeInsets.symmetric(horizontal: Espacio.l, vertical: Espacio.s),
        child: SafeArea(
          bottom: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(cobro.soloLectura ? Icons.lock_outline : Icons.event_busy_outlined, size: 18, color: tinta),
              const SizedBox(width: Espacio.s),
              Expanded(
                child: Text(
                  [cobro.mensaje, if (kIsWeb && cobro.comoPagar != null) 'Cómo pagar: ${cobro.comoPagar}'].join('\n'),
                  style: text.bodySmall?.copyWith(color: tinta),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
