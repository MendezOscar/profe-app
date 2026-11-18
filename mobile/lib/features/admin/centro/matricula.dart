import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/sace/cuadro_sace.dart';
import '../../../core/informes/compartir.dart';
import '../../../core/informes/informes_pdf.dart';
import '../../../core/sace/hoja.dart';
import '../../../theme/tokens.dart';
import '../../../ui/esqueleto.dart';
import '../../../ui/estado_error.dart';
import '../../../ui/estado_vacio.dart';
import 'comun_centro.dart';
import 'convivencia_tab.dart';
import 'familias_centro.dart';

const tiposMatricula = {
  'nuevo_ingreso': 'Nuevo ingreso',
  'reingreso': 'Reingreso',
  'traslado_entrante': 'Traslado entrante',
};

const estadosMatricula = {'activa': 'Activa', 'retirada': 'Retirado', 'trasladada': 'Trasladado'};

final alumnosSeccionProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, seccion) => ref
    .watch(apiClientProvider)
    .get('/centro/secciones/$seccion/alumnos', parse: (d) => (d as List).cast<Map<String, dynamic>>()));

final fichaProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, alumno) =>
    ref.watch(apiClientProvider).get('/centro/alumnos/$alumno', parse: (d) => d as Map<String, dynamic>));

void abrirFicha(BuildContext context, String alumnoId) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FichaAlumnoPage(alumnoId: alumnoId)));

// ── Alumnos de una sección ───────────────────────────────────────────────────

/// Lista de la sección: se llena con el archivo de SACE (cualquier cuadro de la sección
/// trae a todos sus alumnos) o a mano.
class AlumnosSeccionPage extends ConsumerWidget {
  const AlumnosSeccionPage({super.key, required this.seccion, required this.titulo, required this.editar});

  final Map<String, dynamic> seccion;
  final String titulo;
  final bool editar;

  String get _id => seccion['id'] as String;

  void _refrescar(WidgetRef ref) {
    ref.invalidate(alumnosSeccionProvider(_id));
    ref.invalidate(estructuraProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alumnos = ref.watch(alumnosSeccionProvider(_id));
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final cupo = seccion['cupo'] as int?;

    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: alumnos.when(
        loading: () => const EsqueletoLista(filas: 8),
        error: (e, _) => EstadoError(error: e, reintentar: () => ref.invalidate(alumnosSeccionProvider(_id))),
        data: (lista) {
          final activos = lista.where((a) => a['estado'] == 'activa').length;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.xxxl),
                children: [
                  EncabezadoPestana(
                    titulo: '$activos ${activos == 1 ? 'alumno' : 'alumnos'}${cupo == null ? '' : ' de $cupo'}',
                    ayuda: cupo != null && activos > cupo
                        ? 'La sección pasa su cupo por ${activos - cupo}.'
                        : 'Importa el archivo de SACE de la sección: cualquier cuadro de notas trae a todos sus alumnos.',
                    acciones: [
                      if (editar) ...[
                        OutlinedButton.icon(
                          onPressed: () => _matricular(context, ref),
                          icon: const Icon(Icons.person_add_alt),
                          label: const Text('A mano'),
                        ),
                        FilledButton.icon(
                          onPressed: () => _importar(context, ref),
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Importar de SACE'),
                        ),
                      ],
                    ],
                  ),
                  if (lista.isEmpty)
                    const EstadoVacio(
                      icono: Icons.groups_2_outlined,
                      titulo: 'Sección sin alumnos',
                      mensaje: 'Descarga de SACE el cuadro de notas de esta sección e impórtalo aquí.',
                    ),
                  for (final a in lista)
                    Card(
                      margin: const EdgeInsets.only(bottom: Espacio.xs),
                      child: ListTile(
                        title: Text('${a['nombre']}',
                            style: a['estado'] == 'activa'
                                ? null
                                : TextStyle(color: scheme.onSurfaceVariant, decoration: TextDecoration.lineThrough)),
                        subtitle: Text(
                          [
                            '${a['identidad']}',
                            if (a['tipo'] != 'nuevo_ingreso') tiposMatricula[a['tipo']] ?? '',
                            if (a['estado'] != 'activa')
                              '${estadosMatricula[a['estado']]} el ${fechaIso(a['fechaBaja'] as String?)}',
                          ].join(' · '),
                          style: text.bodySmall?.copyWith(color: a['estado'] == 'activa' ? null : scheme.error),
                        ),
                        onTap: () => abrirFicha(context, a['alumnoId'] as String),
                        trailing: editar
                            ? PopupMenuButton<String>(
                                tooltip: 'Más opciones',
                                onSelected: (o) => _accion(context, ref, a, o),
                                itemBuilder: (_) => [
                                  const PopupMenuItem(value: 'ficha', child: Text('Ver ficha')),
                                  if (a['estado'] == 'activa') ...[
                                    const PopupMenuItem(value: 'seccion', child: Text('Cambiar de sección')),
                                    const PopupMenuItem(value: 'baja', child: Text('Retiro o traslado')),
                                  ] else
                                    const PopupMenuItem(value: 'reactivar', child: Text('Reactivar matrícula')),
                                ],
                              )
                            : const Icon(Icons.chevron_right),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _accion(BuildContext context, WidgetRef ref, Map<String, dynamic> a, String opcion) async {
    final id = a['matriculaId'];
    switch (opcion) {
      case 'ficha':
        abrirFicha(context, a['alumnoId'] as String);
      case 'reactivar':
        if (await accionCentro(context, ref, (api) => api.post<void>('/centro/matriculas/$id/reactivar'),
            listo: 'Matrícula reactivada.')) {
          _refrescar(ref);
        }
      case 'seccion':
        await _cambiarSeccion(context, ref, a);
      case 'baja':
        await _darDeBaja(context, ref, a);
    }
  }

  Future<void> _importar(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls'],
      withData: true,
    );
    final bytes = picked?.files.single.bytes;
    if (bytes == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    final CuadroSace cuadro;
    try {
      cuadro = CuadroSace.fromBytes(bytes);
    } on FormatoNoSoportado catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!context.mounted) return;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: const RoundedRectangleBorder(),
        title: const Text('Importar alumnos de SACE'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('El archivo es de: ${[cuadro.gradoSeccion, cuadro.jornada, cuadro.asignatura].whereType<String>().join(' · ')}'),
              const SizedBox(height: Espacio.s),
              Text('Se matricularán ${cuadro.alumnos.length} alumnos en $titulo.',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: Espacio.s),
              const Text('Los que ya están en la lista no se repiten. Si alguno está en otra sección, te aviso antes de moverlo.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Importar')),
        ],
      ),
    );
    if (confirmado != true || !context.mounted) return;

    final alumnos = [for (final a in cuadro.alumnos) {'identidad': a.identidad, 'nombre': a.nombre}];
    Map<String, dynamic>? r;
    await accionCentro(context, ref, (api) async {
      r = await api.post('/centro/secciones/$_id/importar', body: {'alumnos': alumnos}, parse: (d) => d as Map<String, dynamic>);
    });
    _refrescar(ref);
    if (r == null || !context.mounted) return;

    final conflictos = (r!['enOtraSeccion'] as List).cast<Map<String, dynamic>>();
    final partes = [
      '${r!['nuevos']} matriculados',
      if (r!['yaEstaban'] as int > 0) '${r!['yaEstaban']} ya estaban',
      if (r!['cupo'] != null && (r!['activos'] as int) > (r!['cupo'] as int)) 'la sección pasa su cupo (${r!['activos']} de ${r!['cupo']})',
    ];
    if (conflictos.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text('${partes.join(', ')}.')));
      return;
    }

    final mover = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: const RoundedRectangleBorder(),
        title: Text('${conflictos.length} ${conflictos.length == 1 ? 'alumno está' : 'alumnos están'} en otra sección'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${partes.join(', ')}. Estos no se movieron:'),
                const SizedBox(height: Espacio.s),
                for (final c in conflictos) Text('• ${c['nombre']} — en ${c['seccion']}'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Dejarlos donde están')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text('Moverlos a $titulo')),
        ],
      ),
    );
    if (mover != true || !context.mounted) return;
    await accionCentro(
        context,
        ref,
        (api) => api.post<void>('/centro/secciones/$_id/importar', body: {
              'alumnos': [for (final c in conflictos) {'identidad': c['identidad'], 'nombre': c['nombre']}],
              'moverDeSeccion': true,
            }),
        listo: 'Alumnos movidos a $titulo.');
    _refrescar(ref);
  }

  Future<void> _matricular(BuildContext context, WidgetRef ref) {
    final identidad = TextEditingController();
    final nombre = TextEditingController();
    var tipo = 'nuevo_ingreso';
    return showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogo, setState) => DialogoForm(
          titulo: 'Matricular alumno',
          textoGuardar: 'Matricular',
          contenido: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: identidad,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Identidad', hintText: '0801-2014-01234'),
              ),
              const SizedBox(height: Espacio.m),
              TextField(
                controller: nombre,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nombre completo'),
              ),
              const SizedBox(height: Espacio.m),
              DropdownButtonFormField<String>(
                initialValue: tipo,
                decoration: const InputDecoration(labelText: 'Tipo de matrícula'),
                items: [for (final e in tiposMatricula.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => tipo = v ?? tipo),
              ),
            ],
          ),
          guardar: () async {
            final ok = await accionCentro(dialogo, ref,
                (api) => api.post<void>('/centro/secciones/$_id/alumnos',
                    body: {'identidad': identidad.text, 'nombre': nombre.text, 'tipo': tipo}),
                listo: 'Alumno matriculado.');
            if (ok) _refrescar(ref);
            return ok;
          },
        ),
      ),
    );
  }

  Future<void> _cambiarSeccion(BuildContext context, WidgetRef ref, Map<String, dynamic> alumno) async {
    final datos = await ref.read(estructuraProvider.future);
    if (!context.mounted) return;
    final grados = {for (final g in (datos['grados'] as List).cast<Map<String, dynamic>>()) g['id']: g['nombre']};
    final otras = (datos['secciones'] as List).cast<Map<String, dynamic>>().where((s) => s['id'] != _id).toList();
    if (otras.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay otra sección este año.')));
      return;
    }
    String? destino = otras.first['id'] as String;
    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogo, setState) => DialogoForm(
          titulo: 'Cambiar de sección',
          contenido: DropdownButtonFormField<String>(
            initialValue: destino,
            isExpanded: true,
            decoration: InputDecoration(labelText: 'Nueva sección de ${alumno['nombre']}'),
            items: [
              for (final s in otras)
                DropdownMenuItem(
                  value: s['id'] as String,
                  child: Text('${grados[s['gradoId']]} ${s['nombre']} · ${jornadas[s['jornada']]}'),
                ),
            ],
            onChanged: (v) => setState(() => destino = v),
          ),
          guardar: () async {
            final ok = await accionCentro(dialogo, ref,
                (api) => api.put<void>('/centro/matriculas/${alumno['matriculaId']}/seccion', body: {'seccionId': destino}),
                listo: 'Alumno cambiado de sección.');
            if (ok) _refrescar(ref);
            return ok;
          },
        ),
      ),
    );
  }

  Future<void> _darDeBaja(BuildContext context, WidgetRef ref, Map<String, dynamic> alumno) {
    var estado = 'retirada';
    String? fecha = aIso(DateTime.now());
    final motivo = TextEditingController();
    return showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogo, setState) => DialogoForm(
          titulo: 'Retiro o traslado de ${alumno['nombre']}',
          textoGuardar: 'Registrar',
          contenido: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'retirada', label: Text('Retiro')),
                  ButtonSegment(value: 'trasladada', label: Text('Traslado')),
                ],
                selected: {estado},
                onSelectionChanged: (s) => setState(() => estado = s.first),
              ),
              const SizedBox(height: Espacio.m),
              CampoFecha(etiqueta: 'Fecha', valor: fecha, alCambiar: (v) => setState(() => fecha = v ?? fecha)),
              const SizedBox(height: Espacio.m),
              TextField(
                controller: motivo,
                maxLength: 300,
                decoration: InputDecoration(labelText: estado == 'trasladada' ? 'A qué centro y por qué' : 'Motivo'),
              ),
            ],
          ),
          guardar: () async {
            final ok = await accionCentro(dialogo, ref,
                (api) => api.post<void>('/centro/matriculas/${alumno['matriculaId']}/baja',
                    body: {'estado': estado, 'fecha': fecha, 'motivo': motivo.text}),
                listo: 'Baja registrada.');
            if (ok) _refrescar(ref);
            return ok;
          },
        ),
      ),
    );
  }
}

// ── Buscador de alumnos ──────────────────────────────────────────────────────

/// Todos los alumnos del centro, por nombre o identidad, con su sección de este año.
class AlumnosTab extends ConsumerStatefulWidget {
  const AlumnosTab({super.key});

  @override
  ConsumerState<AlumnosTab> createState() => _AlumnosTabState();
}

class _AlumnosTabState extends ConsumerState<AlumnosTab> {
  final _buscar = TextEditingController();
  final _alumnos = <Map<String, dynamic>>[];
  var _total = 0;
  var _mas = false;
  var _pagina = 0;
  var _cargando = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _cargar(reiniciar: true);
  }

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _cargar({bool reiniciar = false}) async {
    setState(() {
      _cargando = true;
      _error = null;
      if (reiniciar) _pagina = 0;
    });
    try {
      final r = await ref.read(apiClientProvider).get('/centro/alumnos',
          query: {'buscar': _buscar.text.trim(), 'pagina': _pagina}, parse: (d) => d as Map<String, dynamic>);
      if (!mounted) return;
      setState(() {
        if (reiniciar) _alumnos.clear();
        _alumnos.addAll((r['alumnos'] as List).cast<Map<String, dynamic>>());
        _total = r['total'] as int;
        _mas = r['mas'] as bool;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.xxxl),
          children: [
            const EncabezadoPestana(
              titulo: 'Alumnos',
              ayuda: 'Busca por nombre o identidad para ver su ficha. Para matricular, entra a la sección.',
            ),
            TextField(
              controller: _buscar,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Nombre o identidad'),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _cargar(reiniciar: true),
            ),
            const SizedBox(height: Espacio.m),
            if (_error != null)
              EstadoError(error: _error!, reintentar: () => _cargar(reiniciar: true))
            else ...[
              if (!_cargando || _alumnos.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: Espacio.s),
                  child: Text('$_total ${_total == 1 ? 'alumno' : 'alumnos'}', style: text.labelSmall),
                ),
              for (final a in _alumnos)
                Card(
                  margin: const EdgeInsets.only(bottom: Espacio.xs),
                  child: ListTile(
                    title: Text('${a['nombre']}'),
                    subtitle: Text(
                      [
                        '${a['identidad']}',
                        a['seccion'] == null ? 'Sin matrícula este año' : '${a['seccion']}',
                        if (a['estado'] != null && a['estado'] != 'activa') '${estadosMatricula[a['estado']]}',
                      ].join(' · '),
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => abrirFicha(context, a['id'] as String),
                  ),
                ),
              if (_cargando)
                const Padding(padding: EdgeInsets.all(Espacio.l), child: Center(child: CircularProgressIndicator()))
              else if (_mas)
                Center(
                  child: TextButton(
                    onPressed: () {
                      _pagina++;
                      _cargar();
                    },
                    child: const Text('Ver más'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Ficha del alumno ─────────────────────────────────────────────────────────

class FichaAlumnoPage extends ConsumerWidget {
  const FichaAlumnoPage({super.key, required this.alumnoId});

  final String alumnoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ficha = ref.watch(fichaProvider(alumnoId));
    return Scaffold(
      appBar: AppBar(title: Text(ficha.valueOrNull?['nombre'] as String? ?? 'Ficha del alumno')),
      body: ficha.when(
        loading: () => const EsqueletoLista(filas: 6),
        error: (e, _) => EstadoError(error: e, reintentar: () => ref.invalidate(fichaProvider(alumnoId))),
        data: (datos) => _FormFicha(key: ValueKey(datos), datos: datos),
      ),
    );
  }
}

class _FormFicha extends ConsumerStatefulWidget {
  const _FormFicha({super.key, required this.datos});

  final Map<String, dynamic> datos;

  @override
  ConsumerState<_FormFicha> createState() => _FormFichaState();
}

class _Encargado {
  _Encargado(Map<String, dynamic>? e)
      : nombre = TextEditingController(text: e?['nombre'] as String? ?? ''),
        parentesco = TextEditingController(text: e?['parentesco'] as String? ?? ''),
        telefono = TextEditingController(text: e?['telefono'] as String? ?? ''),
        correo = TextEditingController(text: e?['correo'] as String? ?? '');

  final TextEditingController nombre, parentesco, telefono, correo;

  void dispose() {
    for (final c in [nombre, parentesco, telefono, correo]) {
      c.dispose();
    }
  }
}

class _FormFichaState extends ConsumerState<_FormFicha> {
  late final Map<String, dynamic> d = widget.datos;
  late final _identidad = TextEditingController(text: d['identidad'] as String);
  late final _nombre = TextEditingController(text: d['nombre'] as String);
  late final _direccion = TextEditingController(text: d['direccion'] as String? ?? '');
  late final _salud = TextEditingController(text: d['salud'] as String? ?? '');
  late final _notas = TextEditingController(text: d['notas'] as String? ?? '');
  late String? _nacimiento = d['fechaNacimiento'] as String?;
  late String? _sexo = d['sexo'] as String?;
  late final _encargados = [for (final e in (d['encargados'] as List).cast<Map<String, dynamic>>()) _Encargado(e)];
  late var _principal = 0;
  var _guardando = false;

  bool get _editar => d['puedeEditar'] == true;

  @override
  void dispose() {
    for (final c in [_identidad, _nombre, _direccion, _salud, _notas]) {
      c.dispose();
    }
    for (final e in _encargados) {
      e.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    final ok = await accionCentro(context, ref, (api) => api.put<void>('/centro/alumnos/${d['id']}', body: {
          'identidad': _identidad.text,
          'nombre': _nombre.text,
          'fechaNacimiento': _nacimiento,
          'sexo': _sexo,
          'direccion': _direccion.text,
          'salud': _salud.text,
          'notas': _notas.text,
          'encargados': [
            for (final (i, e) in _encargados.indexed)
              {
                'nombre': e.nombre.text.trim(),
                'parentesco': e.parentesco.text,
                'telefono': e.telefono.text,
                'correo': e.correo.text,
                'principal': i == _principal,
              },
          ],
        }), listo: 'Ficha guardada.');
    if (!mounted) return;
    setState(() => _guardando = false);
    if (ok) ref.invalidate(fichaProvider(d['id'] as String));
  }

  Future<void> _constancia(Map<String, dynamic> matricula) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final centro = await ref.read(apiClientProvider).get('/centro', parse: (x) => x as Map<String, dynamic>);
      // "7.º grado A (matutina)" → sección y jornada por separado.
      final seccion = matricula['seccion'] as String;
      final corte = seccion.lastIndexOf(' (');
      final bytes = await InformesPdf.constanciaEstudio(
        centro: centro['institucion']['nombre'] as String,
        alumno: d['nombre'] as String,
        identidad: d['identidad'] as String,
        seccion: corte < 0 ? seccion : seccion.substring(0, corte),
        jornada: corte < 0 ? null : seccion.substring(corte + 2, seccion.length - 1),
        anio: matricula['anio'] as int,
      );
      if (mounted) await compartirPdf(context, bytes, nombreArchivo('Constancia de estudio ${d['nombre']}'));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.isNetworkError ? 'Necesitas internet.' : e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final matriculas = (d['matriculas'] as List).cast<Map<String, dynamic>>();

    Widget campo(TextEditingController c, String etiqueta, {int lineas = 1, String? ayuda}) => Padding(
          padding: const EdgeInsets.only(bottom: Espacio.m),
          child: TextField(
            controller: c,
            readOnly: !_editar,
            minLines: lineas,
            maxLines: lineas == 1 ? 1 : lineas + 3,
            decoration: InputDecoration(labelText: etiqueta, helperText: ayuda),
          ),
        );

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Medida.lectura),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.xxxl),
          children: [
            Text('DATOS', style: text.labelSmall),
            const SizedBox(height: Espacio.s),
            campo(_nombre, 'Nombre completo'),
            campo(_identidad, 'Identidad'),
            Padding(
              padding: const EdgeInsets.only(bottom: Espacio.m),
              child: CampoFecha(
                etiqueta: 'Fecha de nacimiento',
                valor: _nacimiento,
                opcional: _editar,
                alCambiar: (v) => _editar ? setState(() => _nacimiento = v) : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: Espacio.m),
              child: SegmentedButton<String?>(
                segments: const [
                  ButtonSegment(value: 'F', label: Text('Femenino')),
                  ButtonSegment(value: 'M', label: Text('Masculino')),
                  ButtonSegment(value: null, label: Text('Sin dato')),
                ],
                selected: {_sexo},
                onSelectionChanged: _editar ? (s) => setState(() => _sexo = s.first) : null,
              ),
            ),
            campo(_direccion, 'Dirección'),
            campo(_salud, 'Salud', lineas: 2, ayuda: 'Alergias, condiciones o medicamentos. Solo lo ve el personal del centro.'),
            campo(_notas, 'Notas de secretaría', lineas: 2, ayuda: 'Becas, necesidades especiales u otros datos.'),
            const SizedBox(height: Espacio.s),
            Row(
              children: [
                Expanded(child: Text('ENCARGADOS', style: text.labelSmall)),
                if (_editar && _encargados.length < 4)
                  TextButton.icon(
                    onPressed: () => setState(() => _encargados.add(_Encargado(null))),
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar'),
                  ),
              ],
            ),
            if (_encargados.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: Espacio.m),
                child: Text('Sin encargados registrados.', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ),
            for (final (i, e) in _encargados.indexed)
              Card(
                margin: const EdgeInsets.only(bottom: Espacio.s),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.s, Espacio.s, Espacio.xs),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(i == _principal ? 'Encargado principal' : 'Encargado ${i + 1}',
                                style: text.titleSmall),
                          ),
                          if (_editar && i != _principal)
                            TextButton(onPressed: () => setState(() => _principal = i), child: const Text('Hacer principal')),
                          if (_editar)
                            IconButton(
                              tooltip: 'Quitar',
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() {
                                _encargados.removeAt(i).dispose();
                                if (_principal >= _encargados.length) _principal = 0;
                              }),
                            ),
                        ],
                      ),
                      campo(e.nombre, 'Nombre'),
                      Row(
                        children: [
                          Expanded(child: campo(e.parentesco, 'Parentesco')),
                          const SizedBox(width: Espacio.m),
                          Expanded(child: campo(e.telefono, 'Teléfono')),
                        ],
                      ),
                      campo(e.correo, 'Correo'),
                    ],
                  ),
                ),
              ),
            if (_editar) ...[
              const SizedBox(height: Espacio.s),
              FilledButton(onPressed: _guardando ? null : _guardar, child: const Text('Guardar ficha')),
            ],
            const SizedBox(height: Espacio.xl),
            Text('ACCESO DE LA FAMILIA', style: text.labelSmall),
            const SizedBox(height: Espacio.s),
            AccesoFamilia(alumnoId: d['id'] as String, nombre: d['nombre'] as String, editar: _editar),
            const SizedBox(height: Espacio.xl),
            Text('MATRÍCULAS', style: text.labelSmall),
            Wrap(
              children: [
                if (_editar && matriculas.any((m) => m['estado'] == 'activa'))
                  TextButton.icon(
                    onPressed: () => registrarExcusa(context, ref, alumno: {'id': d['id'], 'nombre': d['nombre']}),
                    icon: const Icon(Icons.event_busy_outlined),
                    label: const Text('Registrar excusa'),
                  ),
                if (_editar && matriculas.any((m) => m['estado'] == 'activa'))
                  TextButton.icon(
                    onPressed: () => registrarIncidencia(context, ref, alumno: {'id': d['id'], 'nombre': d['nombre']}),
                    icon: const Icon(Icons.report_outlined),
                    label: const Text('Incidencia'),
                  ),
                if (matriculas.any((m) => m['estado'] == 'activa'))
                  TextButton.icon(
                    onPressed: () => _constancia(matriculas.firstWhere((m) => m['estado'] == 'activa')),
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('Constancia de estudio'),
                  ),
              ],
            ),
            const SizedBox(height: Espacio.s),
            if (matriculas.isEmpty)
              Text('Sin matrículas.', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            for (final m in matriculas)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${m['anio']} · ${m['seccion']}'),
                subtitle: Text([
                  '${tiposMatricula[m['tipo']]} el ${fechaIso(m['fechaIngreso'] as String)}',
                  if (m['estado'] != 'activa')
                    '${estadosMatricula[m['estado']]} el ${fechaIso(m['fechaBaja'] as String?)}'
                        '${m['motivoBaja'] == null ? '' : ': ${m['motivoBaja']}'}',
                ].join('\n')),
              ),
          ],
        ),
      ),
    );
  }
}
