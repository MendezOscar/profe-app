import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/enlaces.dart';
import '../../core/providers.dart';
import '../auth/cambiar_clave_dialog.dart';
import '../cuenta/eliminar_cuenta_dialog.dart';
import '../../theme/tokens.dart';

/// Nombres de los planes institucionales, como en la página de precios.
const planesCentro = {
  'pequeno': 'Centro pequeño',
  'mediano': 'Centro mediano',
  'grande': 'Centro grande',
  'red': 'Red o distrito',
};

/// La contraseña temporal sólo se ve una vez: se muestra para copiarla y compartirla.
Future<void> mostrarCuentaCreada(BuildContext context, Map<String, dynamic> cuenta, {String titulo = 'Cuenta creada'}) {
  final texto = 'ProfeApp\nCorreo: ${cuenta['email']}\nContraseña temporal: ${cuenta['claveTemporal']}\n'
      'Entra en https://profe-app.pages.dev/app/ o en la app. Al entrar te pedirá crear tu contraseña.';
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      shape: const RoundedRectangleBorder(),
      title: Text(titulo),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${cuenta['nombre']}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Espacio.m),
            SelectableText('Correo: ${cuenta['email']}'),
            const SizedBox(height: Espacio.xs),
            SelectableText('Contraseña temporal: ${cuenta['claveTemporal']}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: Espacio.l),
            const Text('Compártela con la persona. Solo se muestra esta vez; al entrar deberá crear su contraseña.'),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: texto));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copiado para compartir.')));
            }
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copiar'),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Listo')),
      ],
    ),
  );
}

/// Formulario de nombre y correo. Devuelve la respuesta del servidor, o null si se canceló.
Future<Map<String, dynamic>?> pedirNombreYCorreo(
  BuildContext context,
  WidgetRef ref, {
  required String titulo,
  required String ruta,
}) =>
    showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _FormCuenta(titulo: titulo, ruta: ruta),
    );

class _FormCuenta extends ConsumerStatefulWidget {
  const _FormCuenta({required this.titulo, required this.ruta});

  final String titulo;
  final String ruta;

  @override
  ConsumerState<_FormCuenta> createState() => _FormCuentaState();
}

class _FormCuentaState extends ConsumerState<_FormCuenta> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _correo = TextEditingController();
  var _guardando = false;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    _correo.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final cuenta = await ref.read(apiClientProvider).post(widget.ruta,
          body: {'email': _correo.text.trim(), 'nombre': _nombre.text.trim()},
          parse: (d) => d as Map<String, dynamic>);
      if (mounted) Navigator.pop(context, cuenta);
    } on ApiException catch (e) {
      setState(() => _error = e.isNetworkError ? 'Necesitas internet.' : e.message);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        shape: const RoundedRectangleBorder(),
        title: Text(widget.titulo),
        content: SizedBox(
          width: 420,
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nombre,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nombre completo'),
                  validator: (v) => (v?.trim().isEmpty ?? true) ? 'Escribe el nombre' : null,
                ),
                const SizedBox(height: Espacio.m),
                TextFormField(
                  controller: _correo,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Correo'),
                  validator: (v) => (v == null || !v.contains('@')) ? 'Correo no válido' : null,
                  onFieldSubmitted: (_) => _guardar(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: Espacio.m),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: _guardando ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: _guardando ? null : _guardar, child: const Text('Crear cuenta')),
        ],
      );
}

/// Menú de la cuenta para los paneles de administración.
class MenuCuentaAdmin extends ConsumerWidget {
  const MenuCuentaAdmin({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
        tooltip: 'Cuenta',
        icon: const Icon(Icons.account_circle_outlined),
        onSelected: (o) async {
          switch (o) {
            case 'clave':
              return mostrarCambiarClave(context);
            case 'ayuda':
              return Enlaces.abrir(Enlaces.soporte);
            case 'privacidad':
              return Enlaces.abrir(Enlaces.privacidad);
            case 'terminos':
              return Enlaces.abrir(Enlaces.terminos);
            case 'eliminar':
              return mostrarEliminarCuenta(context);
          }
          await ref.read(authControllerProvider.notifier).logout();
          if (kIsWeb) await Enlaces.volverAlSitio();
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'clave', child: Text('Cambiar contraseña')),
          const PopupMenuItem(value: 'ayuda', child: Text('Ayuda')),
          const PopupMenuItem(value: 'privacidad', child: Text('Privacidad')),
          const PopupMenuItem(value: 'terminos', child: Text('Términos')),
          const PopupMenuItem(value: 'salir', child: Text('Cerrar sesión')),
          // La de plataforma no se elimina desde la app (ve los datos de todos).
          if (ref.read(sessionProvider)?.role == 'AdminCentro')
            const PopupMenuItem(value: 'eliminar', child: Text('Eliminar mi cuenta')),
        ],
      );
}

String fechaCorta(String? iso) {
  if (iso == null) return 'Nunca';
  final d = DateTime.parse(iso).toLocal();
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
