import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/informes/compartir.dart';
import '../../core/informes/informes_pdf.dart';
import '../../core/planes/modelos.dart';
import '../../core/providers.dart';
import '../../core/sync/sync_controller.dart';
import '../../theme/tokens.dart';
import '../../ui/esqueleto.dart';
import '../../ui/shell.dart';

/// Ajustes donde se guarda lo que escribe el docente (ámbito vacío: son suyos, no de una clase).
const _claveDatos = 'portafolio';
const _claveIntroduccion = 'portafolio-introduccion';
const _claveObjetivos = 'portafolio-objetivos';

/// Cuántos alumnos tienen el sexo marcado en cada clase.
final _sexosMarcadosProvider = FutureProvider<Map<String, int>>((ref) async {
  final clases = await ref.watch(clasesProvider.future);
  final repo = ref.watch(planesRepositoryProvider);
  return {for (final c in clases) c.id: (await repo.sexos(c.id)).length};
});

/// Portafolio docente con el formato departamental 2026: el docente completa sus datos una vez
/// y la app arma el PDF con lo que ya tiene (matrícula, horario, rúbricas, notas…).
class PortafolioPage extends ConsumerStatefulWidget {
  const PortafolioPage({super.key});

  @override
  ConsumerState<PortafolioPage> createState() => _PortafolioPageState();
}

class _PortafolioPageState extends ConsumerState<PortafolioPage> {
  static const _campos = [
    ('dni', 'DNI', TextInputType.number),
    ('titulos', 'Títulos obtenidos', TextInputType.text),
    ('aniosServicio', 'Años de servicio', TextInputType.number),
    ('telefono', 'Teléfono', TextInputType.phone),
    ('correo', 'Correo electrónico', TextInputType.emailAddress),
    ('centro', 'Nombre del centro educativo', TextInputType.text),
    ('codigoCentro', 'Código del centro educativo', TextInputType.text),
    ('director', 'Director(a) del centro', TextInputType.name),
    ('telefonoDirector', 'Teléfono del director(a)', TextInputType.phone),
    ('lugar', 'Lugar (aldea, colonia o barrio)', TextInputType.text),
    ('municipio', 'Municipio', TextInputType.text),
    ('departamento', 'Departamento', TextInputType.text),
  ];

  final _textos = <String, TextEditingController>{};
  final _introduccion = TextEditingController();
  final _objetivos = TextEditingController();
  final _anio = TextEditingController();
  String _tipo = '';
  String _zona = '';
  bool? _media;
  bool _cargado = false;
  bool _generando = false;
  Timer? _guardado;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    if (_guardado?.isActive ?? false) {
      _guardado!.cancel();
      _guardar();
    }
    for (final c in [..._textos.values, _introduccion, _objetivos, _anio]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    final repo = ref.read(planesRepositoryProvider);
    final datos = await repo.ajuste('', _claveDatos);
    final introduccion = await repo.ajuste('', _claveIntroduccion);
    final objetivos = await repo.ajuste('', _claveObjetivos);
    final centro = await repo.centroPrincipal();
    final clases = await ref.read(clasesProvider.future);
    final sesion = ref.read(sessionProvider);
    final ahora = DateTime.now();
    if (!mounted) return;
    setState(() {
      // Lo que ya sabe la app va de entrada; lo que el docente escribió, manda.
      final previos = {
        'correo': sesion?.email ?? '',
        'centro': centro.centro,
        'codigoCentro': centro.codigo,
        ...datos.map((k, v) => MapEntry(k, '$v')),
      };
      for (final (clave, _, _) in _campos) {
        _textos[clave] = TextEditingController(text: previos[clave] ?? '');
      }
      _tipo = datos['tipoAdministracion'] as String? ?? '';
      _zona = datos['zona'] as String? ?? '';
      _media = datos['media'] as bool? ?? clases.any((c) => (gradoDe(c.gradoSeccion) ?? 0) >= 10);
      // En noviembre y diciembre se prepara el del año que viene.
      _anio.text = '${datos['anio'] ?? (ahora.month >= 11 ? ahora.year + 1 : ahora.year)}';
      _introduccion.text = introduccion['texto'] as String? ?? '';
      _objetivos.text = objetivos['texto'] as String? ?? '';
      _cargado = true;
    });
  }

  void _cambio() {
    _guardado?.cancel();
    _guardado = Timer(const Duration(milliseconds: 800), _guardar);
  }

  Future<void> _guardar() async {
    final repo = ref.read(planesRepositoryProvider);
    await repo.guardarAjuste('', _claveDatos, {
      for (final MapEntry(key: k, value: c) in _textos.entries) k: c.text.trim(),
      'tipoAdministracion': _tipo,
      'zona': _zona,
      'media': _media,
      'anio': int.tryParse(_anio.text.trim()),
    });
    await repo.guardarAjuste('', _claveIntroduccion, {'texto': _introduccion.text.trim()});
    await repo.guardarAjuste('', _claveObjetivos, {'texto': _objetivos.text.trim()});
    ref.read(syncControllerProvider.notifier).programar();
  }

  Future<void> _generar() async {
    setState(() => _generando = true);
    try {
      _guardado?.cancel();
      await _guardar();
      final repo = ref.read(planesRepositoryProvider);
      final api = ref.read(apiClientProvider);
      final clases = await ref.read(clasesProvider.future);
      final horarios = await ref.read(horariosProvider.future);
      final portafolio = <ClasePortafolio>[];
      for (final c in clases) {
        final parciales = await ref.read(parcialesProvider(c.id).future);
        final detalle = await ref.read(claseProvider(c.id).future);
        Map<String, dynamic>? programa;
        try {
          programa = await api.get('/ia/programa',
              query: {'modalidad': detalle.modalidad, 'grado': c.gradoSeccion, 'asignatura': c.asignatura},
              parse: (d) => d is Map<String, dynamic> ? d : null);
        } on ApiException {
          programa = null; // sin internet, la sección de contenidos queda para agregar
        }
        portafolio.add(ClasePortafolio(
          clase: c,
          planes: await repo.planes([for (final p in parciales) (c.id, p)]),
          sexos: await repo.sexos(c.id),
          horario: horarios[c.id],
          programa: programa,
        ));
      }
      final datos = DatosPortafolio(
        docente: ref.read(sessionProvider)?.fullName ?? '',
        campos: {
          for (final MapEntry(key: k, value: c) in _textos.entries) k: c.text,
          'tipoAdministracion': _tipo,
          'zona': _zona,
        },
        media: _media ?? false,
        anio: int.tryParse(_anio.text.trim()) ?? DateTime.now().year,
        introduccion: _introduccion.text,
        objetivos: _objetivos.text,
      );
      final bytes = await PortafolioPdf.generar(datos, portafolio);
      if (mounted) await compartirPdf(context, bytes, nombreArchivo('Portafolio docente ${datos.anio} ${datos.docente}'));
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final clases = ref.watch(clasesProvider).valueOrNull ?? const [];
    final marcados = ref.watch(_sexosMarcadosProvider).valueOrNull ?? const {};

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/cuenta')),
        title: const Text('Portafolio docente'),
      ),
      body: !_cargado
          ? const EsqueletoLista()
          : ContenidoCentrado(
              maxAncho: 720,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.xxxl),
                children: [
                  Text(
                    'Con el formato departamental 2026. Completa tus datos una vez: la matrícula, el horario, las '
                    'rúbricas, las tareas, las notas y la nivelación salen de lo que ya tienes en la app. Al final de '
                    'cada sección se listan los documentos que agregas tú.',
                    style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: Espacio.l),
                  Text('Nivel', style: text.titleMedium),
                  const SizedBox(height: Espacio.s),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Básica')),
                      ButtonSegment(value: true, label: Text('Media')),
                    ],
                    selected: {_media ?? false},
                    onSelectionChanged: (s) {
                      setState(() => _media = s.first);
                      _cambio();
                    },
                  ),
                  const SizedBox(height: Espacio.l),
                  TextField(
                    controller: _anio,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                    decoration: const InputDecoration(labelText: 'Año del portafolio'),
                    onChanged: (_) => _cambio(),
                  ),
                  const SizedBox(height: Espacio.xl),
                  Text('I. Datos generales', style: text.titleMedium),
                  for (final (clave, etiqueta, teclado) in _campos)
                    Padding(
                      padding: const EdgeInsets.only(top: Espacio.m),
                      child: TextField(
                        controller: _textos[clave],
                        keyboardType: teclado,
                        textCapitalization: teclado == TextInputType.text || teclado == TextInputType.name
                            ? TextCapitalization.words
                            : TextCapitalization.none,
                        decoration: InputDecoration(labelText: etiqueta),
                        onChanged: (_) => _cambio(),
                      ),
                    ),
                  const SizedBox(height: Espacio.l),
                  Text('Tipo de administración', style: text.bodyMedium),
                  const SizedBox(height: Espacio.xs),
                  Wrap(spacing: Espacio.s, children: [
                    for (final t in ['Gubernamental', 'No gubernamental'])
                      ChoiceChip(
                        label: Text(t),
                        selected: _tipo == t,
                        onSelected: (_) {
                          setState(() => _tipo = t);
                          _cambio();
                        },
                      ),
                  ]),
                  const SizedBox(height: Espacio.m),
                  Text('Zona', style: text.bodyMedium),
                  const SizedBox(height: Espacio.xs),
                  Wrap(spacing: Espacio.s, children: [
                    for (final z in ['Urbana', 'Rural'])
                      ChoiceChip(
                        label: Text(z),
                        selected: _zona == z,
                        onSelected: (_) {
                          setState(() => _zona = z);
                          _cambio();
                        },
                      ),
                  ]),
                  const SizedBox(height: Espacio.xl),
                  Text('II. Presentación', style: text.titleMedium),
                  const SizedBox(height: Espacio.m),
                  TextField(
                    controller: _introduccion,
                    minLines: 3,
                    maxLines: 10,
                    maxLength: 3500,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Introducción', alignLabelWithHint: true),
                    onChanged: (_) => _cambio(),
                  ),
                  TextField(
                    controller: _objetivos,
                    minLines: 3,
                    maxLines: 10,
                    maxLength: 3500,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Objetivos',
                      hintText: 'Uno por línea',
                      alignLabelWithHint: true,
                    ),
                    onChanged: (_) => _cambio(),
                  ),
                  const SizedBox(height: Espacio.l),
                  Text('Sexo de los alumnos', style: text.titleMedium),
                  const SizedBox(height: Espacio.xs),
                  Text('Para la matrícula por edad y sexo. Se marca una vez por clase.',
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: Espacio.s),
                  for (final c in clases)
                    Card(
                      child: ListTile(
                        title: Text(c.asignatura),
                        subtitle: Text('${c.gradoSeccion} · ${marcados[c.id] ?? 0} de ${c.alumnos} marcados'),
                        trailing: Icon((marcados[c.id] ?? 0) >= c.alumnos ? Icons.check_circle : Icons.chevron_right,
                            color: (marcados[c.id] ?? 0) >= c.alumnos ? scheme.primary : null),
                        onTap: () => context.go('/cuenta/portafolio/sexo/${c.id}'),
                      ),
                    ),
                  const SizedBox(height: Espacio.xl),
                  FilledButton.icon(
                    onPressed: _generando || clases.isEmpty ? null : _generar,
                    icon: _generando
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(_generando ? 'Armando el portafolio…' : 'Generar portafolio en PDF'),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Marcar el sexo de cada alumno de una clase (F o M). Se guarda al tocar.
class SexoAlumnosPage extends ConsumerStatefulWidget {
  const SexoAlumnosPage({super.key, required this.claseId});

  final String claseId;

  @override
  ConsumerState<SexoAlumnosPage> createState() => _SexoAlumnosPageState();
}

class _SexoAlumnosPageState extends ConsumerState<SexoAlumnosPage> {
  Map<String, String>? _sexos;

  @override
  void initState() {
    super.initState();
    ref.read(planesRepositoryProvider).sexos(widget.claseId).then((s) {
      if (mounted) setState(() => _sexos = s);
    });
  }

  Future<void> _poner(String alumnoId, String? sexo) async {
    setState(() => sexo == null ? _sexos!.remove(alumnoId) : _sexos![alumnoId] = sexo);
    await ref.read(planesRepositoryProvider).guardarSexos(widget.claseId, _sexos!);
    ref.invalidate(_sexosMarcadosProvider);
    ref.read(syncControllerProvider.notifier).programar();
  }

  @override
  Widget build(BuildContext context) {
    final clase = ref.watch(claseProvider(widget.claseId)).valueOrNull;
    final sexos = _sexos;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/cuenta/portafolio')),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sexo de los alumnos'),
            if (clase != null)
              Text('${clase.resumen.asignatura} · ${clase.resumen.gradoSeccion}',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
      body: clase == null || sexos == null
          ? const EsqueletoLista()
          : ContenidoCentrado(
              maxAncho: 720,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.s, Espacio.l, Espacio.xxxl),
                itemCount: clase.alumnos.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final a = clase.alumnos[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(a.nombre, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: SegmentedButton<String>(
                      showSelectedIcon: false,
                      emptySelectionAllowed: true,
                      segments: const [
                        ButtonSegment(value: 'F', label: Text('F'), tooltip: 'Femenino'),
                        ButtonSegment(value: 'M', label: Text('M'), tooltip: 'Masculino'),
                      ],
                      selected: {?sexos[a.id]},
                      onSelectionChanged: (s) => _poner(a.id, s.firstOrNull),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
