import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/enlaces.dart';
import '../../theme/profeapp_theme.dart';

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
          padding: const EdgeInsets.all(Espacio.xl),
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
                    child: Image.asset(logoMarca(context), height: 44, semanticLabel: 'ProfeApp'),
                  ),
                  const SizedBox(height: Espacio.m),
                  Text('Tus notas sin internet, listas para subir a SACE',
                      style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: Espacio.xxl),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.mail_outline)),
                    validator: (value) =>
                        (value == null || !value.contains('@')) ? 'Ingresa un correo válido' : null,
                  ),
                  const SizedBox(height: Espacio.m),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      ),
                    ),
                    validator: (value) => (value == null || value.length < 4) ? 'Contraseña muy corta' : null,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => mostrarOlvideClave(context, _email.text.trim()),
                      child: const Text('¿Olvidaste tu contraseña?'),
                    ),
                  ),
                  if (auth.error != null) ...[
                    const SizedBox(height: Espacio.l),
                    Container(
                      padding: const EdgeInsets.all(Espacio.m),
                      // Sin esquinas redondeadas: regla de la marca.
                      color: scheme.errorContainer,
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
                          const SizedBox(width: Espacio.s),
                          Expanded(
                            child: Text(auth.error!, style: TextStyle(color: scheme.onErrorContainer)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: Espacio.xl),
                  FilledButton(
                    onPressed: auth.isLoading ? null : _submit,
                    child: auth.isLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Entrar'),
                  ),
                  if (_tardando && auth.isLoading)
                    Padding(
                      padding: const EdgeInsets.only(top: Espacio.m),
                      child: Text(
                        'Conectando con el servidor… la primera vez del día puede tardar hasta un minuto.',
                        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: Espacio.xl),
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

/// Sin recuperación por correo todavía: explica a quién pedir una contraseña temporal. Al
/// docente de un centro se la repone su dirección desde el panel; al del plan personal (y a
/// la propia dirección), ProfeApp desde la plataforma, después de confirmar que la cuenta es suya.
Future<void> mostrarOlvideClave(BuildContext context, String correo) {
  final texto = 'Hola, olvidé mi contraseña de ProfeApp.${correo.contains('@') ? ' Mi cuenta es $correo.' : ''}';
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(),
    builder: (context) {
      final text = Theme.of(context).textTheme;
      final scheme = Theme.of(context).colorScheme;
      Widget paso(IconData icono, String titulo, String detalle) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(icono, color: scheme.primary),
            title: Text(titulo, style: text.titleSmall),
            subtitle: Text(detalle),
          );
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Espacio.l, 0, Espacio.l, Espacio.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('¿Olvidaste tu contraseña?', style: text.titleLarge),
              const SizedBox(height: Espacio.xs),
              Text('Te damos una contraseña temporal y, al entrar, eliges una nueva. Tus datos no se pierden.',
                  style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: Espacio.m),
              paso(Icons.apartment_outlined, 'Si tu cuenta es de un centro educativo',
                  'Pídesela a la dirección o coordinación de tu centro: la restablece en un momento desde su panel.'),
              paso(Icons.person_outline, 'Si tienes el plan personal, o administras un centro',
                  'Escríbenos desde el correo de tu cuenta o por WhatsApp. Confirmamos que la cuenta es tuya y te enviamos una temporal.'),
              const SizedBox(height: Espacio.m),
              FilledButton.icon(
                onPressed: () => Enlaces.abrir(Uri.parse('https://wa.me/50498242108?text=${Uri.encodeComponent(texto)}')),
                icon: const Icon(Icons.chat_outlined),
                label: const Text('Escribir por WhatsApp'),
              ),
              const SizedBox(height: Espacio.s),
              OutlinedButton.icon(
                onPressed: () => Enlaces.abrir(Uri(
                  scheme: 'mailto',
                  path: 'soporte@profeapphn.com',
                  query: 'subject=${Uri.encodeComponent('Olvidé mi contraseña')}&body=${Uri.encodeComponent(texto)}',
                )),
                icon: const Icon(Icons.mail_outline),
                label: const Text('Escribir a soporte@profeapphn.com'),
              ),
              const SizedBox(height: Espacio.s),
              Text('Nunca te pediremos tu contraseña.', textAlign: TextAlign.center, style: text.bodySmall),
            ],
          ),
        ),
      );
    },
  );
}
