import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/providers.dart';
import '../../../theme/tokens.dart';

/// Año lectivo elegido en el panel (null = el actual del centro).
final anioElegidoProvider = StateProvider<String?>((ref) => null);

/// Organización del centro para el año elegido: años, grados con asignaturas, aulas,
/// secciones con su carga y docentes.
final estructuraProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  final anio = ref.watch(anioElegidoProvider);
  return ref
      .watch(apiClientProvider)
      .get(
        '/centro/estructura',
        query: anio == null ? null : {'anioId': anio},
        parse: (d) => d as Map<String, dynamic>,
      );
});

const nivelesEducativos = {'prebasica': 'Prebásica', 'basica': 'Básica', 'media': 'Media'};

const jornadas = {
  'matutina': 'Matutina',
  'vespertina': 'Vespertina',
  'nocturna': 'Nocturna',
  'doble': 'Doble jornada',
  'sabatina': 'Sabatina',
};

const cargos = {
  'director': 'Dirección',
  'subdirector': 'Subdirección',
  'secretaria': 'Secretaría',
  'orientador': 'Orientación',
};

String nombreCargo(String? cargo) => cargo == null ? 'Administración' : cargos[cargo] ?? cargo;

/// Llama a la API, muestra el error si falla y refresca la estructura. Devuelve si salió bien.
Future<bool> accionCentro(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function(ApiClient api) llamada, {
  String? listo,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await llamada(ref.read(apiClientProvider));
    ref.invalidate(estructuraProvider);
    if (listo != null) messenger.showSnackBar(SnackBar(content: Text(listo)));
    return true;
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.isNetworkError ? 'Necesitas internet.' : e.message)));
    return false;
  }
}

Future<bool> confirmar(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  String accion = 'Eliminar',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: const RoundedRectangleBorder(),
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: Text(accion),
          ),
        ],
      ),
    ) ??
    false;

/// "2027-02-01" → "01/02/2027".
String fechaIso(String? iso) {
  if (iso == null) return '—';
  final d = DateTime.parse(iso);
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String aIso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Campo de fecha que abre el calendario. [opcional] permite dejarlo vacío.
class CampoFecha extends StatelessWidget {
  const CampoFecha({
    super.key,
    required this.etiqueta,
    required this.valor,
    required this.alCambiar,
    this.opcional = false,
  });

  final String etiqueta;
  final String? valor;
  final ValueChanged<String?> alCambiar;
  final bool opcional;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      final inicial = valor == null ? DateTime.now() : DateTime.parse(valor!);
      final d = await showDatePicker(
        context: context,
        initialDate: inicial,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (d != null) alCambiar(aIso(d));
    },
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: etiqueta,
        suffixIcon: opcional && valor != null
            ? IconButton(tooltip: 'Quitar fecha', icon: const Icon(Icons.close), onPressed: () => alCambiar(null))
            : const Icon(Icons.calendar_today_outlined),
      ),
      child: Text(valor == null ? 'Sin fecha' : fechaIso(valor)),
    ),
  );
}

/// Encabezado de una pestaña: título, explicación y acciones.
class EncabezadoPestana extends StatelessWidget {
  const EncabezadoPestana({super.key, required this.titulo, this.ayuda, this.acciones = const []});

  final String titulo;
  final String? ayuda;
  final List<Widget> acciones;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Espacio.l),
      child: Wrap(
        spacing: Espacio.s,
        runSpacing: Espacio.s,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: text.titleLarge),
                if (ayuda != null)
                  Text(ayuda!, style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (acciones.isNotEmpty) Wrap(spacing: Espacio.s, runSpacing: Espacio.s, children: acciones),
        ],
      ),
    );
  }
}

/// Diálogo de formulario con Guardar/Cancelar. [guardar] devuelve si cerrar.
class DialogoForm extends StatefulWidget {
  const DialogoForm({
    super.key,
    required this.titulo,
    required this.contenido,
    required this.guardar,
    this.textoGuardar = 'Guardar',
  });

  final String titulo;
  final Widget contenido;
  final Future<bool> Function() guardar;
  final String textoGuardar;

  @override
  State<DialogoForm> createState() => _DialogoFormState();
}

class _DialogoFormState extends State<DialogoForm> {
  var _guardando = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    shape: const RoundedRectangleBorder(),
    title: Text(widget.titulo),
    content: SizedBox(width: 460, child: SingleChildScrollView(child: widget.contenido)),
    actions: [
      TextButton(onPressed: _guardando ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(
        onPressed: _guardando
            ? null
            : () async {
                setState(() => _guardando = true);
                final cerrar = await widget.guardar();
                if (!context.mounted) return;
                setState(() => _guardando = false);
                if (cerrar) Navigator.pop(context);
              },
        child: Text(widget.textoGuardar),
      ),
    ],
  );
}
