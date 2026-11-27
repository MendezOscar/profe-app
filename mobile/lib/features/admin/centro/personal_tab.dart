import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../theme/tokens.dart';
import '../../../ui/esqueleto.dart';
import '../../../ui/estado_error.dart';
import '../admin_comun.dart';
import 'comun_centro.dart';

final personalProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => ref.watch(apiClientProvider).get('/centro/personal', parse: (d) => (d as List).cast<Map<String, dynamic>>()),
);

/// Cuentas de dirección, subdirección, secretaría y orientación. No ocupan cupo de docentes.
class PersonalTab extends ConsumerWidget {
  const PersonalTab({super.key, required this.puedeEditar});

  final bool puedeEditar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personal = ref.watch(personalProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    Future<void> accion(Map<String, dynamic> p, String opcion) async {
      final id = p['id'];
      if (opcion.startsWith('cargo:')) {
        await accionCentro(
          context,
          ref,
          (api) => api.put<void>('/centro/personal/$id/cargo', body: {'cargo': opcion.substring(6)}),
          listo: 'Cargo cambiado.',
        );
      } else if (opcion == 'clave') {
        Map<String, dynamic>? cuenta;
        await accionCentro(
          context,
          ref,
          (api) async => cuenta = await api.post(
            '/centro/personal/$id/restablecer-clave',
            parse: (d) => d as Map<String, dynamic>,
          ),
        );
        if (cuenta != null && context.mounted) {
          await mostrarCuentaCreada(context, cuenta!, titulo: 'Contraseña restablecida');
        }
      } else {
        await accionCentro(
          context,
          ref,
          (api) => api.post<void>('/centro/personal/$id/${p['activo'] == true ? 'desactivar' : 'activar'}'),
        );
      }
      ref.invalidate(personalProvider);
    }

    return personal.when(
      loading: () => const EsqueletoLista(filas: 3, conTarjeta: true),
      error: (e, _) => EstadoError(error: e, reintentar: () => ref.invalidate(personalProvider)),
      data: (lista) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.xxxl),
            children: [
              EncabezadoPestana(
                titulo: 'Personal',
                ayuda:
                    'Dirección, subdirección y secretaría administran el centro; orientación sólo consulta. '
                    'Estas cuentas no ocupan cupo de docentes.',
                acciones: [
                  if (puedeEditar)
                    FilledButton.icon(
                      onPressed: () => _agregar(context, ref),
                      icon: const Icon(Icons.person_add_alt),
                      label: const Text('Agregar personal'),
                    ),
                ],
              ),
              for (final p in lista)
                Card(
                  margin: const EdgeInsets.only(bottom: Espacio.s),
                  child: ListTile(
                    title: Text('${p['nombre']}${p['esYo'] == true ? ' (tú)' : ''}'),
                    subtitle: Text(
                      '${nombreCargo(p['cargo'] as String?)} · ${p['email']}'
                      '${p['activo'] == true ? '' : ' · inactiva'}',
                      style: text.bodySmall?.copyWith(
                        color: p['activo'] == true ? scheme.onSurfaceVariant : scheme.error,
                      ),
                    ),
                    trailing: puedeEditar
                        ? PopupMenuButton<String>(
                            tooltip: 'Más opciones',
                            onSelected: (o) => accion(p, o),
                            itemBuilder: (_) => [
                              for (final c in cargos.entries)
                                if (c.key != p['cargo'])
                                  PopupMenuItem(value: 'cargo:${c.key}', child: Text('Cargo: ${c.value}')),
                              const PopupMenuItem(value: 'clave', child: Text('Restablecer contraseña')),
                              if (p['esYo'] != true)
                                PopupMenuItem(
                                  value: 'estado',
                                  child: Text(p['activo'] == true ? 'Desactivar' : 'Activar'),
                                ),
                            ],
                          )
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _agregar(BuildContext context, WidgetRef ref) {
    final nombre = TextEditingController();
    final correo = TextEditingController();
    var cargo = 'secretaria';
    return showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogo, setState) => DialogoForm(
          titulo: 'Agregar personal',
          textoGuardar: 'Crear cuenta',
          contenido: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombre,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nombre completo'),
              ),
              const SizedBox(height: Espacio.m),
              TextField(
                controller: correo,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Correo'),
              ),
              const SizedBox(height: Espacio.m),
              DropdownButtonFormField<String>(
                initialValue: cargo,
                decoration: const InputDecoration(labelText: 'Cargo'),
                items: [for (final c in cargos.entries) DropdownMenuItem(value: c.key, child: Text(c.value))],
                onChanged: (v) => setState(() => cargo = v ?? cargo),
              ),
            ],
          ),
          guardar: () async {
            Map<String, dynamic>? cuenta;
            final ok = await accionCentro(dialogo, ref, (api) async {
              cuenta = await api.post(
                '/centro/personal',
                body: {'email': correo.text.trim(), 'nombre': nombre.text.trim(), 'cargo': cargo},
                parse: (d) => d as Map<String, dynamic>,
              );
            });
            if (ok) {
              ref.invalidate(personalProvider);
              if (dialogo.mounted) Navigator.pop(dialogo);
              if (context.mounted) await mostrarCuentaCreada(context, cuenta!, titulo: 'Cuenta creada');
            }
            return false;
          },
        ),
      ),
    );
  }
}
