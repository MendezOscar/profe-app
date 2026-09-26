import 'package:flutter/material.dart';

/// Pantalla sin datos que explica qué hacer y ofrece el siguiente paso.
class EstadoVacio extends StatelessWidget {
  const EstadoVacio({super.key, required this.icono, required this.titulo, required this.mensaje, this.accion});

  final IconData icono;
  final String titulo;
  final String mensaje;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: scheme.primaryContainer,
                child: Icon(icono, size: 40, color: scheme.primary),
              ),
              const SizedBox(height: 20),
              Text(titulo, style: text.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(mensaje,
                  style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
              if (accion != null) ...[const SizedBox(height: 24), accion!],
            ],
          ),
        ),
      ),
    );
  }
}
