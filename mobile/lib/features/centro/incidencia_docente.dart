import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/centro/mi_carga.dart';
import '../../core/providers.dart';
import '../../theme/tokens.dart';
import '../admin/centro/comun_centro.dart';
import '../admin/centro/convivencia_tab.dart';

/// El catedrático registra una falta disciplinaria de un alumno de su sección. Va al centro
/// y a la familia (con aviso). Necesita internet.
Future<void> reportarIncidencia(BuildContext context, WidgetRef ref, SeccionCentro seccion) async {
  final alumnos = seccion.alumnos.where((a) => a.activo).toList();
  AlumnoMatricula? elegido;
  var gravedad = 'leve';
  var fecha = aIso(DateTime.now());
  final descripcion = TextEditingController();
  final medida = TextEditingController();

  await showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (dialogo, setState) => DialogoForm(
        titulo: 'Incidencia · ${seccion.grado} ${seccion.nombre}',
        contenido: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<AlumnoMatricula>(
              initialValue: elegido,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Alumno'),
              items: [
                for (final a in alumnos)
                  DropdownMenuItem(value: a, child: Text(a.nombre, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (a) => setState(() => elegido = a),
            ),
            const SizedBox(height: Espacio.m),
            CamposIncidencia(
              gravedad: gravedad,
              fecha: fecha,
              descripcion: descripcion,
              medida: medida,
              alGravedad: (g) => setState(() => gravedad = g),
              alFecha: (f) => setState(() => fecha = f),
            ),
          ],
        ),
        guardar: () async {
          final messenger = ScaffoldMessenger.of(dialogo);
          if (elegido == null) {
            messenger.showSnackBar(const SnackBar(content: Text('Elige al alumno.')));
            return false;
          }
          try {
            await ref.read(apiClientProvider).post<void>('/mi-centro/incidencias', body: {
              'seccionId': seccion.id,
              'identidad': elegido!.identidad,
              'fecha': fecha,
              'gravedad': gravedad,
              'descripcion': descripcion.text,
              'medida': medida.text,
            });
            messenger.showSnackBar(const SnackBar(content: Text('Incidencia registrada. El centro y la familia ya la ven.')));
            return true;
          } on ApiException catch (e) {
            messenger.showSnackBar(SnackBar(content: Text(e.isNetworkError ? 'Necesitas internet.' : e.message)));
            return false;
          }
        },
      ),
    ),
  );
}
