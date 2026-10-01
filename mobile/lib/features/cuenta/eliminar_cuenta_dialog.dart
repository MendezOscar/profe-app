import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/local/local_db.dart';
import '../../core/providers.dart';
import '../../theme/tokens.dart';

/// Eliminar la cuenta desde la app, como exigen App Store y Google Play. Borra todo en el
/// servidor y en este dispositivo. Pide la contraseña para confirmar.
Future<void> mostrarEliminarCuenta(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _EliminarCuentaDialog());

class _EliminarCuentaDialog extends ConsumerStatefulWidget {
  const _EliminarCuentaDialog();

  @override
  ConsumerState<_EliminarCuentaDialog> createState() => _EliminarCuentaDialogState();
}

class _EliminarCuentaDialogState extends ConsumerState<_EliminarCuentaDialog> {
  final _clave = TextEditingController();
  var _entiendo = false;
  var _borrando = false;
  String? _error;

  @override
  void dispose() {
    _clave.dispose();
    super.dispose();
  }

  Future<void> _eliminar() async {
    setState(() {
      _borrando = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).post<void>('/auth/delete-account', body: {'password': _clave.text});
      final userId = ref.read(sessionProvider)?.userId;
      final db = ref.read(localDbProvider);
      try {
        await (await db).close();
      } catch (_) {
        // Ya estaba cerrada.
      }
      await ref.read(authControllerProvider.notifier).logout();
      if (userId != null) await LocalDb.borrar(userId);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (error) {
      setState(() => _error = error.isNetworkError ? 'Necesitas internet para eliminar la cuenta.' : error.message);
    } finally {
      if (mounted) setState(() => _borrando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      shape: const RoundedRectangleBorder(),
      title: const Text('Eliminar mi cuenta'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Se borran para siempre tu cuenta, tus asignaturas, cuadros de SACE, planes, notas y '
                'asistencia, tanto en la nube como en este dispositivo. No se puede deshacer.\n\n'
                'Si necesitas tus cuadros, expórtalos antes.',
              ),
              const SizedBox(height: Espacio.l),
              TextField(
                controller: _clave,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(labelText: 'Tu contraseña'),
                onChanged: (_) => setState(() {}),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _entiendo,
                onChanged: (v) => setState(() => _entiendo = v ?? false),
                title: const Text('Entiendo que se borra todo'),
              ),
              if (_error != null) Text(_error!, style: TextStyle(color: scheme.error)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _borrando ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
          onPressed: _borrando || !_entiendo || _clave.text.isEmpty ? null : _eliminar,
          child: _borrando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Eliminar para siempre'),
        ),
      ],
    );
  }
}
