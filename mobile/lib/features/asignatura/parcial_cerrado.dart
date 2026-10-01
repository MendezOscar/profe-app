import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/planes/modelos.dart';
import '../../core/providers.dart';
import '../../theme/tokens.dart';

/// Aviso de parcial cerrado: sus notas ya pasaron al cuadro. Reabrirlo permite corregir;
/// al cerrarlo otra vez, el cuadro se actualiza.
class ParcialCerrado extends ConsumerWidget {
  const ParcialCerrado({super.key, required this.plan});

  final PlanParcial plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final fecha = DateFormat.yMMMd('es').format(plan.cerradoEn!.toLocal());
    return Container(
      color: scheme.secondary,
      padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.s, Espacio.s, Espacio.s),
      child: Row(
        children: [
          Icon(Icons.lock_outline, color: scheme.onSecondary),
          const SizedBox(width: Espacio.m),
          Expanded(
            child: Text('Cerrado el $fecha. Las notas ya están en el cuadro de SACE.',
                style: TextStyle(color: scheme.onSecondary)),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: scheme.onSecondary),
            onPressed: () async {
              await ref.read(planesRepositoryProvider).reabrir(plan.claseId, plan.parcial.clave);
              planCambiado(ref, plan.claseId, plan.parcial.clave);
            },
            child: const Text('Reabrir'),
          ),
        ],
      ),
    );
  }
}
