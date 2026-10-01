import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/clase.dart';
import '../../core/providers.dart';
import '../../core/sync/sync_controller.dart';
import '../../theme/tokens.dart';

/// Elimina una clase (un cuadro subido) después de explicar qué se pierde y pedir que el
/// docente lo confirme de forma explícita. No se puede deshacer: se borra en todos sus
/// dispositivos y en el respaldo.
Future<void> eliminarClase(BuildContext context, WidgetRef ref, ClaseResumen clase) async {
  final contenido = await ref.read(planesRepositoryProvider).contenido(clase.id);
  if (!context.mounted) return;
  final confirmar = await showDialog<bool>(context: context, builder: (_) => _Confirmar(clase, contenido));
  if (confirmar != true || !context.mounted) return;

  await ref.read(clasesRepositoryProvider).eliminar(clase.id);
  ref.invalidate(clasesProvider);
  ref.invalidate(tableroProvider);
  ref.read(syncControllerProvider.notifier).programar();
  if (!context.mounted) return;
  context.go('/inicio');
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Se eliminó ${clase.asignatura}.')));
}

class _Confirmar extends StatefulWidget {
  const _Confirmar(this.clase, this.contenido);

  final ClaseResumen clase;
  final ({int actividades, int notas, int listas}) contenido;

  @override
  State<_Confirmar> createState() => _ConfirmarState();
}

class _ConfirmarState extends State<_Confirmar> {
  var _entiendo = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final clase = widget.clase;
    final c = widget.contenido;
    final seccion = [clase.gradoSeccion, clase.jornada].where((t) => t.isNotEmpty).join(' · ');

    return AlertDialog(
      icon: Icon(Icons.delete_forever_outlined, color: scheme.error),
      title: Text('¿Eliminar ${clase.asignatura}?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (seccion.isNotEmpty) Text(seccion, style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: Espacio.m),
            const Text('Se borra para siempre:'),
            const SizedBox(height: Espacio.s),
            _Punto('${clase.alumnos} alumnos y el cuadro de SACE que subiste'),
            _Punto('${c.actividades} actividades del plan y ${c.notas} notas puestas'),
            _Punto('${c.listas} listas de asistencia'),
            _Punto('Las notas totales e inasistencias capturadas en el cuadro'),
            const SizedBox(height: Espacio.m),
            const Text('Se elimina en todos tus dispositivos y en el respaldo en línea. '
                'Si ya exportaste el cuadro, ese archivo no se toca. '
                'Para volver a tenerla tendrías que importar el cuadro otra vez y calificar desde cero.'),
            const SizedBox(height: Espacio.s),
            CheckboxListTile(
              value: _entiendo,
              onChanged: (v) => setState(() => _entiendo = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Entiendo que no se puede deshacer'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
          onPressed: _entiendo ? () => Navigator.pop(context, true) : null,
          child: const Text('Eliminar'),
        ),
      ],
    );
  }
}

class _Punto extends StatelessWidget {
  const _Punto(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Espacio.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [const Text('•  '), Expanded(child: Text(texto))],
        ),
      );
}
