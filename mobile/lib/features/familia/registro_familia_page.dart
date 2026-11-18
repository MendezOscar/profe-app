import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/enlaces.dart';
import '../../theme/tokens.dart';

/// Alta del padre o la madre con el código de familia que entrega el centro.
class RegistroFamiliaPage extends ConsumerStatefulWidget {
  const RegistroFamiliaPage({super.key});

  @override
  ConsumerState<RegistroFamiliaPage> createState() => _RegistroFamiliaPageState();
}

class _RegistroFamiliaPageState extends ConsumerState<RegistroFamiliaPage> {
  final _form = GlobalKey<FormState>();
  final _codigo = TextEditingController();
  final _nombre = TextEditingController();
  final _correo = TextEditingController();
  final _clave = TextEditingController();
  var _oculta = true;

  @override
  void dispose() {
    for (final c in [_codigo, _nombre, _correo, _clave]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _crear() async {
    if (!_form.currentState!.validate()) return;
    await ref.read(authControllerProvider.notifier).registrarPadre(
          codigo: _codigo.text,
          email: _correo.text,
          password: _clave.text,
          nombre: _nombre.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/login')),
        title: const Text('Cuenta de familia'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Espacio.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _form,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Ve las notas, la asistencia y los avisos del centro de tu hijo o hija.', style: text.titleMedium),
                    const SizedBox(height: Espacio.s),
                    Text('El código te lo da la secretaría del centro. Si ya tienes cuenta, entra con ella y agrega el '
                        'código desde el menú de tu cuenta.',
                        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: Espacio.xl),
                    TextFormField(
                      controller: _codigo,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'Código del centro', hintText: 'ABCD-2345'),
                      validator: (v) =>
                          (v ?? '').replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length != 8 ? 'El código tiene 8 letras y números' : null,
                    ),
                    const SizedBox(height: Espacio.m),
                    TextFormField(
                      controller: _nombre,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.name],
                      decoration: const InputDecoration(labelText: 'Tu nombre completo'),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Escribe tu nombre' : null,
                    ),
                    const SizedBox(height: Espacio.m),
                    TextFormField(
                      controller: _correo,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'Correo'),
                      validator: (v) => (v ?? '').contains('@') ? null : 'Correo no válido',
                    ),
                    const SizedBox(height: Espacio.m),
                    TextFormField(
                      controller: _clave,
                      obscureText: _oculta,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: 'Crea una contraseña',
                        helperText: 'Al menos 8 caracteres, con mayúscula, minúscula y número.',
                        helperMaxLines: 2,
                        suffixIcon: IconButton(
                          tooltip: _oculta ? 'Mostrar' : 'Ocultar',
                          icon: Icon(_oculta ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _oculta = !_oculta),
                        ),
                      ),
                      validator: (v) => (v ?? '').length < 8 ? 'Al menos 8 caracteres' : null,
                      onFieldSubmitted: (_) => _crear(),
                    ),
                    if (auth.error != null) ...[
                      const SizedBox(height: Espacio.m),
                      Text(auth.error!, style: TextStyle(color: scheme.error)),
                    ],
                    const SizedBox(height: Espacio.xl),
                    FilledButton(
                      onPressed: auth.isLoading ? null : _crear,
                      child: auth.isLoading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Crear mi cuenta'),
                    ),
                    const SizedBox(height: Espacio.l),
                    Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        TextButton(onPressed: () => Enlaces.abrir(Enlaces.privacidad), child: const Text('Privacidad')),
                        TextButton(onPressed: () => Enlaces.abrir(Enlaces.terminos), child: const Text('Términos')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
