import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/enlaces.dart';

/// Entrada del docente. Las cuentas no se crean desde la app.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _tardando = false;

  @override
  void initState() {
    super.initState();
    ref.read(authControllerProvider.notifier).despertarServidor();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    // Si tarda, es que el servidor está despertando: se avisa para que no parezca trabado.
    final aviso = Future.delayed(const Duration(seconds: 5), () {
      if (mounted && ref.read(authControllerProvider).isLoading) setState(() => _tardando = true);
    });
    await ref.read(authControllerProvider.notifier).login(_email.text, _password.text);
    aviso.ignore();
    if (mounted) setState(() => _tardando = false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Image.asset('assets/brand/logo-azul.png', height: 44, semanticLabel: 'ProfeApp'),
                  ),
                  const SizedBox(height: 12),
                  Text('Tus notas sin internet, listas para subir a SACE',
                      style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.mail_outline)),
                    validator: (value) =>
                        (value == null || !value.contains('@')) ? 'Ingresa un correo válido' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      ),
                    ),
                    validator: (value) => (value == null || value.length < 4) ? 'Contraseña muy corta' : null,
                  ),
                  if (auth.error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      // Sin esquinas redondeadas: regla de la marca.
                      color: scheme.errorContainer,
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(auth.error!, style: TextStyle(color: scheme.onErrorContainer)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: auth.isLoading ? null : _submit,
                    child: auth.isLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Entrar'),
                  ),
                  if (_tardando && auth.isLoading)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'Conectando con el servidor… la primera vez del día puede tardar hasta un minuto.',
                        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      if (kIsWeb)
                        TextButton.icon(
                          onPressed: Enlaces.volverAlSitio,
                          icon: const Icon(Icons.arrow_back, size: 18),
                          label: const Text('Volver al sitio'),
                        ),
                      TextButton(onPressed: () => Enlaces.abrir(Enlaces.soporte), child: const Text('Ayuda')),
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
    );
  }
}
