import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/providers.dart';
import '../../ui/estado_vacio.dart';
import '../../ui/shell.dart';
import 'admin_comun.dart';
import '../../theme/tokens.dart';
import '../../ui/esqueleto.dart';
import '../../ui/estado_error.dart';

final institucionesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) => ref
    .watch(apiClientProvider)
    .get('/plataforma/instituciones', parse: (d) => (d as List).cast<Map<String, dynamic>>()));

/// Panel de quien opera ProfeApp: centros con licencia y cuentas del plan personal.
class PlataformaPage extends ConsumerWidget {
  const PlataformaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instituciones = ref.watch(institucionesProvider);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plataforma'),
        actions: [
          IconButton(tooltip: 'Actualizar', onPressed: () => ref.invalidate(institucionesProvider), icon: const Icon(Icons.refresh)),
          const MenuCuentaAdmin(),
        ],
      ),
      body: ContenidoCentrado(
        maxAncho: 1100,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.xxxl),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: () => _nuevoCentro(context, ref),
                  icon: const Icon(Icons.apartment),
                  label: const Text('Nuevo centro'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final cuenta = await pedirNombreYCorreo(context, ref,
                        titulo: 'Cuenta del plan docente', ruta: '/plataforma/docentes');
                    if (cuenta != null && context.mounted) await mostrarCuentaCreada(context, cuenta);
                  },
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Nueva cuenta de docente'),
                ),
              ],
            ),
            const SizedBox(height: Espacio.xl),
            Text('CENTROS', style: text.labelSmall),
            const SizedBox(height: Espacio.s),
            instituciones.when(
              loading: () => const SizedBox(height: 320, child: EsqueletoLista(filas: 4, conTarjeta: true)),
              error: (e, _) => SizedBox(
                height: 360,
                child: EstadoError(error: e, reintentar: () => ref.invalidate(institucionesProvider)),
              ),
              data: (lista) => lista.isEmpty
                  ? const EstadoVacio(
                      icono: Icons.apartment,
                      titulo: 'Sin centros todavía',
                      mensaje: 'Crea un centro cuando vendas una licencia institucional. Su administrador '
                          'recibe una contraseña temporal y da de alta a sus docentes.',
                    )
                  : Column(
                      children: [
                        for (final i in lista)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Espacio.s),
                            child: Card(
                              child: ListTile(
                                title: Text('${i['nombre']}', style: text.titleMedium),
                                subtitle: Text([
                                  planesCentro[i['plan']] ?? '${i['plan']}',
                                  '${i['docentes']} de ${i['maxDocentes']} docentes',
                                  'vence: ${i['venceEn'] == null ? 'sin fecha' : fechaCorta(i['venceEn'] as String)}',
                                  if (i['activa'] != true) 'SUSPENDIDO',
                                ].join(' · ')),
                                trailing: const Icon(Icons.edit_outlined),
                                onTap: () => _editar(context, ref, i),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _nuevoCentro(BuildContext context, WidgetRef ref) async {
    final creado = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _FormCentro());
    if (creado == null || !context.mounted) return;
    ref.invalidate(institucionesProvider);
    await mostrarCuentaCreada(context, creado['admin'] as Map<String, dynamic>, titulo: 'Centro creado: administrador');
  }

  Future<void> _editar(BuildContext context, WidgetRef ref, Map<String, dynamic> institucion) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _FormCentro(institucion: institucion));
    if (ok != null) ref.invalidate(institucionesProvider);
  }
}

/// Alta (con su administrador) o edición de la licencia de un centro.
class _FormCentro extends ConsumerStatefulWidget {
  const _FormCentro({this.institucion});

  final Map<String, dynamic>? institucion;

  @override
  ConsumerState<_FormCentro> createState() => _FormCentroState();
}

class _FormCentroState extends ConsumerState<_FormCentro> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.institucion?['nombre'] as String? ?? '');
  late final _cupo = TextEditingController(text: '${widget.institucion?['maxDocentes'] ?? 15}');
  final _adminNombre = TextEditingController();
  final _adminCorreo = TextEditingController();
  late String _plan = widget.institucion?['plan'] as String? ?? 'pequeno';
  late bool _activa = widget.institucion?['activa'] as bool? ?? true;
  late DateTime? _vence = widget.institucion == null
      ? DateTime(DateTime.now().year, 12, 31)
      : (widget.institucion!['venceEn'] == null ? null : DateTime.parse(widget.institucion!['venceEn'] as String).toLocal());
  var _guardando = false;
  String? _error;

  bool get _nuevo => widget.institucion == null;

  static const _cupoSugerido = {'pequeno': 15, 'mediano': 40, 'grande': 80, 'red': 200};

  @override
  void dispose() {
    for (final c in [_nombre, _cupo, _adminNombre, _adminCorreo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    final api = ref.read(apiClientProvider);
    final vence = _vence == null ? null : DateTime(_vence!.year, _vence!.month, _vence!.day, 23, 59).toUtc().toIso8601String();
    try {
      if (_nuevo) {
        final creado = await api.post('/plataforma/instituciones',
            body: {
              'nombre': _nombre.text.trim(),
              'plan': _plan,
              'maxDocentes': int.parse(_cupo.text),
              'venceEn': vence,
              'adminEmail': _adminCorreo.text.trim(),
              'adminNombre': _adminNombre.text.trim(),
            },
            parse: (d) => d as Map<String, dynamic>);
        if (mounted) Navigator.pop(context, creado);
      } else {
        await api.put<void>('/plataforma/instituciones/${widget.institucion!['id']}',
            body: {'plan': _plan, 'maxDocentes': int.parse(_cupo.text), 'venceEn': vence, 'activa': _activa});
        if (mounted) Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      setState(() => _error = e.isNetworkError ? 'Necesitas internet.' : e.message);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: const RoundedRectangleBorder(),
      title: Text(_nuevo ? 'Nuevo centro' : 'Licencia de ${widget.institucion!['nombre']}'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_nuevo) ...[
                  TextFormField(
                    controller: _nombre,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Nombre del centro'),
                    validator: (v) => (v?.trim().isEmpty ?? true) ? 'Escribe el nombre' : null,
                  ),
                  const SizedBox(height: Espacio.m),
                ],
                DropdownButtonFormField<String>(
                  initialValue: _plan,
                  decoration: const InputDecoration(labelText: 'Plan'),
                  items: [for (final e in planesCentro.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (p) => setState(() {
                    _plan = p!;
                    _cupo.text = '${_cupoSugerido[p]}';
                  }),
                ),
                const SizedBox(height: Espacio.m),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _cupo,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(labelText: 'Cupo de docentes'),
                        validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1 ? 'Mínimo 1' : null,
                      ),
                    ),
                    const SizedBox(width: Espacio.m),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final f = await showDatePicker(
                            context: context,
                            initialDate: _vence ?? DateTime.now(),
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2035),
                          );
                          if (f != null) setState(() => _vence = f);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Vence'),
                          child: Text(_vence == null ? 'Sin fecha' : fechaCorta(_vence!.toIso8601String())),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_nuevo) ...[
                  const SizedBox(height: Espacio.xl),
                  Text('ADMINISTRADOR DEL CENTRO', style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: Espacio.s),
                  TextFormField(
                    controller: _adminNombre,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Nombre (director, coordinador…)'),
                    validator: (v) => (v?.trim().isEmpty ?? true) ? 'Escribe el nombre' : null,
                  ),
                  const SizedBox(height: Espacio.m),
                  TextFormField(
                    controller: _adminCorreo,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Correo'),
                    validator: (v) => (v == null || !v.contains('@')) ? 'Correo no válido' : null,
                  ),
                ] else
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Licencia activa'),
                    subtitle: const Text('Suspendida, sus docentes no pueden entrar.'),
                    value: _activa,
                    onChanged: (v) => setState(() => _activa = v),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: Espacio.m),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _guardando ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _guardando ? null : _guardar, child: Text(_nuevo ? 'Crear centro' : 'Guardar')),
      ],
    );
  }
}
