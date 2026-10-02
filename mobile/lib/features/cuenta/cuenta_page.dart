import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/enlaces.dart';
import '../../core/models/cobro.dart';
import '../../core/preferencias.dart';
import '../../core/providers.dart';
import '../../core/sync/sync_controller.dart';
import '../../ui/indicador_sync.dart';
import '../../ui/shell.dart';
import '../auth/cambiar_clave_dialog.dart';
import 'eliminar_cuenta_dialog.dart';
import '../../theme/tokens.dart';

class CuentaPage extends ConsumerWidget {
  const CuentaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final sync = ref.watch(syncControllerProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final ultima = sync.ultima;

    return Scaffold(
      appBar: AppBar(title: const Text('Cuenta')),
      body: ContenidoCentrado(
        maxAncho: 640,
        child: ListView(
          padding: const EdgeInsets.all(Espacio.l),
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  color: scheme.primary,
                  alignment: Alignment.center,
                  child: Text(
                    (session?.fullName.isNotEmpty ?? false) ? session!.fullName[0].toUpperCase() : '?',
                    style: text.headlineMedium?.copyWith(color: scheme.onPrimary),
                  ),
                ),
                const SizedBox(width: Espacio.l),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(session?.fullName ?? '', style: text.titleLarge),
                      Text(session?.email ?? '', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            if (session?.cobro case final cobro?) ...[
              const SizedBox(height: Espacio.xl),
              _TuPlan(cobro: cobro, asignaturas: ref.watch(clasesProvider).valueOrNull?.length),
            ],
            const SizedBox(height: Espacio.xl),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.cloud_outlined),
                    title: const Text('Respaldo en la nube'),
                    subtitle: Text(ultima == null
                        ? 'Todavía no se ha sincronizado en esta sesión'
                        : 'Última vez: ${TimeOfDay.fromDateTime(ultima).format(context)}'),
                    trailing: const IndicadorSync(),
                  ),
                  const Divider(height: 2),
                  ListTile(
                    leading: const Icon(Icons.slideshow_outlined),
                    title: const Text('Ver la introducción'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go('/bienvenida'),
                  ),
                  const Divider(height: 2),
                  SwitchListTile(
                    secondary: const Icon(Icons.checklist),
                    title: const Text('Guía de primeros pasos en Inicio'),
                    value: !ref.watch(banderaProvider(Bandera.primerosPasosOcultos)),
                    onChanged: (mostrar) =>
                        ref.read(banderaProvider(Bandera.primerosPasosOcultos).notifier).poner(!mostrar),
                  ),
                  const Divider(height: 2),
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('Cambiar contraseña'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => mostrarCambiarClave(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Espacio.xl),
            Card(
              child: Column(
                children: [
                  for (final (icono, titulo, url) in [
                    (Icons.chat_outlined, 'WhatsApp de soporte', Enlaces.whatsapp),
                    (Icons.help_outline, 'Ayuda y soporte', Enlaces.soporte),
                    (Icons.privacy_tip_outlined, 'Política de privacidad', Enlaces.privacidad),
                    (Icons.description_outlined, 'Términos de uso', Enlaces.terminos),
                  ]) ...[
                    ListTile(
                      leading: Icon(icono),
                      title: Text(titulo),
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      onTap: () => Enlaces.abrir(url),
                    ),
                    if (url != Enlaces.terminos) const Divider(height: 2),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Espacio.xl),
            OutlinedButton.icon(
              onPressed: () async {
                await ref.read(authControllerProvider.notifier).logout();
                // En la web se vuelve a la landing; en el teléfono, al login.
                if (kIsWeb) await Enlaces.volverAlSitio();
              },
              icon: const Icon(Icons.logout),
              label: const Text('Cerrar sesión'),
            ),
            const SizedBox(height: Espacio.s),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              onPressed: () => mostrarEliminarCuenta(context),
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('Eliminar mi cuenta'),
            ),
          ],
        ),
      ),
    );
  }
}

/// El plan de la cuenta: hasta cuándo está al día y cuántas asignaturas cubre. Los datos
/// para pagar sólo en la web (ver [AvisoCobro]).
class _TuPlan extends StatelessWidget {
  const _TuPlan({required this.cobro, required this.asignaturas});

  final Cobro cobro;
  final int? asignaturas;

  @override
  Widget build(BuildContext context) {
    final nivel = nivelesDocente[cobro.nivel]?.$1;
    final tope = cobro.topeAsignaturas;
    return Card(
      child: ListTile(
        leading: Icon(cobro.soloLectura ? Icons.lock_outline : Icons.workspace_premium_outlined),
        title: Text(cobro.planNombre ?? (nivel == null ? 'Tu plan' : 'Plan $nivel')),
        subtitle: Text([
          cobro.mensaje,
          if (asignaturas != null)
            tope == null ? '$asignaturas secciones, sin tope' : '$asignaturas de $tope secciones del plan',
          if (kIsWeb && cobro.comoPagar != null) 'Cómo pagar: ${cobro.comoPagar}',
        ].join('\n')),
        isThreeLine: true,
      ),
    );
  }
}
