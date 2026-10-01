import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/providers.dart';
import '../../theme/tokens.dart';

/// Cambio de contraseña. Necesita internet: la contraseña vive en el servidor.
Future<void> mostrarCambiarClave(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _CambiarClaveDialog());

/// Primera entrada con una contraseña temporal (la dio el centro o soporte): hay que
/// cambiarla antes de usar la app.
class CambiarClaveObligatoriaPage extends ConsumerWidget {
  const CambiarClaveObligatoriaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => const Scaffold(
        body: Center(child: SingleChildScrollView(child: _CambiarClaveDialog(obligatorio: true))),
      );
}

class _CambiarClaveDialog extends ConsumerStatefulWidget {
  const _CambiarClaveDialog({this.obligatorio = false});

  final bool obligatorio;

  @override
  ConsumerState<_CambiarClaveDialog> createState() => _CambiarClaveDialogState();
}

class _CambiarClaveDialogState extends ConsumerState<_CambiarClaveDialog> {
  final _form = GlobalKey<FormState>();
  final _actual = TextEditingController();
  final _nueva = TextEditingController();
  final _confirmacion = TextEditingController();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _actual.dispose();
    _nueva.dispose();
    _confirmacion.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      // Con el cliente de la app y no a mano: si el token venció, se renueva solo.
      await ref.read(apiClientProvider).post<void>('/auth/change-password', body: {
        'currentPassword': _actual.text,
        'newPassword': _nueva.text,
        // Este dispositivo sigue con sesión; en los demás se cierra.
        'refreshToken': ref.read(sessionProvider)?.refreshToken,
      });
      await ref.read(authControllerProvider.notifier).claveCambiada();
      if (!mounted || widget.obligatorio) return; // El router sigue solo.
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contraseña actualizada.')));
    } on ApiException catch (error) {
      setState(() => _error = error.isNetworkError ? 'Necesitas internet para cambiar la contraseña.' : error.message);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.obligatorio ? 'Crea tu contraseña' : 'Cambiar contraseña'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.obligatorio)
              const Padding(
                padding: EdgeInsets.only(bottom: Espacio.l),
                child: Text('Entraste con una contraseña temporal. Crea la tuya para seguir.'),
              ),
            TextFormField(
              controller: _actual,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(labelText: widget.obligatorio ? 'Contraseña temporal' : 'Contraseña actual'),
              validator: (v) => (v == null || v.isEmpty) ? 'Escribe tu contraseña actual' : null,
            ),
            const SizedBox(height: Espacio.m),
            TextFormField(
              controller: _nueva,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(
                labelText: 'Contraseña nueva',
                helperText: 'Mínimo 8 caracteres, con mayúscula, minúscula y número',
                helperMaxLines: 2,
              ),
              validator: (v) => (v == null || v.length < 8) ? 'Mínimo 8 caracteres' : null,
            ),
            const SizedBox(height: Espacio.m),
            TextFormField(
              controller: _confirmacion,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Repite la contraseña nueva'),
              validator: (v) => v != _nueva.text ? 'No coincide con la nueva' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: Espacio.m),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.obligatorio)
          TextButton(
            onPressed: _guardando ? null : () => ref.read(authControllerProvider.notifier).logout(),
            child: const Text('Cerrar sesión'),
          )
        else
          TextButton(onPressed: _guardando ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
