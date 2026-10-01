import 'package:flutter/material.dart';
import '../theme/tokens.dart';

enum TonoEstado { normal, error }

/// Pantalla sin datos que explica qué hacer y ofrece el siguiente paso.
class EstadoVacio extends StatelessWidget {
  const EstadoVacio({
    super.key,
    required this.icono,
    required this.titulo,
    required this.mensaje,
    this.accion,
    this.tono = TonoEstado.normal,
  });

  final IconData icono;
  final String titulo;
  final String mensaje;
  final Widget? accion;
  final TonoEstado tono;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Espacio.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(Espacio.l),
                color: tono == TonoEstado.error ? scheme.errorContainer : scheme.primaryContainer,
                child: Icon(icono, size: 40, color: tono == TonoEstado.error ? scheme.error : scheme.primary),
              ),
              const SizedBox(height: Espacio.xl),
              Semantics(header: true, child: Text(titulo, style: text.titleLarge, textAlign: TextAlign.center)),
              const SizedBox(height: Espacio.s),
              Text(mensaje,
                  style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
              if (accion != null) ...[const SizedBox(height: Espacio.xl), accion!],
            ],
          ),
        ),
      ),
    );
  }
}
