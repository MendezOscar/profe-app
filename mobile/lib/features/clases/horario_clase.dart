import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/clase.dart';
import '../../core/planes/modelos.dart';
import '../../core/providers.dart';
import '../../core/sync/sync_controller.dart';
import '../../theme/tokens.dart';

const _cortos = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const _largos = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];

/// «7:00 a. m.» desde '07:00', con el formato del teléfono.
String horaTexto(BuildContext context, String hhmm) {
  final t = _hora(hhmm);
  return t == null ? '' : t.format(context);
}

TimeOfDay? _hora(String hhmm) {
  final partes = hhmm.split(':');
  if (partes.length != 2) return null;
  final h = int.tryParse(partes[0]), m = int.tryParse(partes[1]);
  return h == null || m == null ? null : TimeOfDay(hour: h, minute: m);
}

String _texto(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// «Lun, Mié · 7:00 a. m. · Aula 12»: la hora sólo si es la misma todos los días.
String resumenHorario(BuildContext context, Horario h) {
  final horas = {for (final d in h.dias) d.inicio};
  return [
    if (h.dias.isNotEmpty) h.dias.map((d) => _cortos[d.dia - 1]).join(', '),
    if (horas.length == 1) horaTexto(context, horas.first),
    if (h.lugar.isNotEmpty) h.lugar,
  ].join(' · ');
}

/// Pide o cambia el horario de una clase. Devuelve false si el docente lo dejó para después.
/// [paso]: «1 de 3» cuando se piden varios seguidos al importar.
Future<bool> editarHorario(BuildContext context, WidgetRef ref, ClaseResumen clase, {String? paso}) async {
  final actual = (await ref.read(horariosProvider.future))[clase.id];
  if (!context.mounted) return false;
  final nuevo = await showModalBottomSheet<Horario>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(),
    builder: (context) => _EditorHorario(clase: clase, inicial: actual ?? const Horario(), paso: paso),
  );
  if (nuevo == null) return false;
  await ref.read(planesRepositoryProvider).guardarHorario(clase.id, nuevo);
  ref.invalidate(horariosProvider);
  ref.read(syncControllerProvider.notifier).programar();
  return true;
}

/// Al importar: el horario de cada asignatura nueva, una tras otra. «Ahora no» deja las demás.
Future<void> pedirHorarios(BuildContext context, WidgetRef ref, List<String> claseIds) async {
  final clases = {for (final c in await ref.read(clasesProvider.future)) c.id: c};
  for (final (i, id) in claseIds.indexed) {
    final clase = clases[id];
    if (clase == null || !context.mounted) continue;
    final guardado = await editarHorario(
      context,
      ref,
      clase,
      paso: claseIds.length > 1 ? '${i + 1} de ${claseIds.length}' : '',
    );
    if (!guardado) return;
  }
}

class _EditorHorario extends StatefulWidget {
  const _EditorHorario({required this.clase, required this.inicial, this.paso});

  final ClaseResumen clase;
  final Horario inicial;

  /// No nulo al importar (vacío si es una sola asignatura): el botón dice «Ahora no».
  final String? paso;

  @override
  State<_EditorHorario> createState() => _EditorHorarioState();
}

class _EditorHorarioState extends State<_EditorHorario> {
  late final Map<int, (TimeOfDay, TimeOfDay)> _dias = {
    for (final d in widget.inicial.dias)
      d.dia: (
        _hora(d.inicio) ?? const TimeOfDay(hour: 7, minute: 0),
        _hora(d.fin) ?? const TimeOfDay(hour: 7, minute: 45),
      ),
  };
  late final _aula = TextEditingController(text: widget.inicial.aula);
  late final _edificio = TextEditingController(text: widget.inicial.edificio);
  int? _ultimo;

  @override
  void dispose() {
    _aula.dispose();
    _edificio.dispose();
    super.dispose();
  }

  static int _minutos(TimeOfDay t) => t.hour * 60 + t.minute;

  void _alternar(int dia) => setState(() {
    if (_dias.remove(dia) != null) return;
    // Un día nuevo copia la hora del último que se tocó: casi siempre es la misma.
    final base = _dias[_ultimo] ?? _dias.values.lastOrNull;
    _dias[dia] = base ?? (const TimeOfDay(hour: 7, minute: 0), const TimeOfDay(hour: 7, minute: 45));
    _ultimo = dia;
  });

  Future<void> _elegir(int dia, {required bool inicio}) async {
    final (a, b) = _dias[dia]!;
    final t = await showTimePicker(context: context, initialTime: inicio ? a : b);
    if (t == null) return;
    setState(() {
      if (inicio) {
        // Mover la entrada arrastra la salida: la clase conserva lo que dura.
        final dura = _minutos(b) - _minutos(a);
        final fin = (_minutos(t) + (dura > 0 ? dura : 45)).clamp(0, 23 * 60 + 59);
        _dias[dia] = (t, TimeOfDay(hour: fin ~/ 60, minute: fin % 60));
      } else {
        _dias[dia] = (a, t);
      }
      _ultimo = dia;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final dias = _dias.keys.toList()..sort();
    final malos = [
      for (final d in dias)
        if (_minutos(_dias[d]!.$2) <= _minutos(_dias[d]!.$1)) d,
    ];
    final importando = widget.paso != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(Espacio.l, 0, Espacio.l, Espacio.l),
            children: [
              Row(
                children: [
                  Expanded(child: Text('¿Cuándo das esta clase?', style: text.titleLarge)),
                  if (widget.paso?.isNotEmpty ?? false) Text(widget.paso!, style: text.labelLarge),
                ],
              ),
              const SizedBox(height: Espacio.xs),
              Text(
                [widget.clase.asignatura, widget.clase.gradoSeccion].where((t) => t.isNotEmpty).join(' · '),
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: Espacio.l),
              Text('Días', style: text.titleSmall),
              const SizedBox(height: Espacio.s),
              Wrap(
                spacing: Espacio.s,
                runSpacing: Espacio.s,
                children: [
                  for (var d = 1; d <= 7; d++)
                    FilterChip(
                      label: Text(_cortos[d - 1]),
                      selected: _dias.containsKey(d),
                      onSelected: (_) => _alternar(d),
                    ),
                ],
              ),
              if (dias.isNotEmpty) ...[
                const SizedBox(height: Espacio.m),
                for (final d in dias)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Espacio.xs),
                    child: Row(
                      children: [
                        Expanded(child: Text(_largos[d - 1], style: text.bodyLarge)),
                        OutlinedButton(
                          onPressed: () => _elegir(d, inicio: true),
                          child: Text(_dias[d]!.$1.format(context)),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: Espacio.xs),
                          child: Text('a'),
                        ),
                        OutlinedButton(
                          onPressed: () => _elegir(d, inicio: false),
                          child: Text(_dias[d]!.$2.format(context)),
                        ),
                      ],
                    ),
                  ),
                if (malos.isNotEmpty)
                  Text(
                    'La hora de salida debe ser después de la de entrada.',
                    style: text.bodySmall?.copyWith(color: scheme.error),
                  ),
              ],
              const SizedBox(height: Espacio.l),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _aula,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Aula (opcional)'),
                    ),
                  ),
                  const SizedBox(width: Espacio.m),
                  Expanded(
                    child: TextField(
                      controller: _edificio,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Edificio (opcional)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Espacio.s),
              Text(
                'Con los días, la app te recuerda pasar lista solo cuando tienes esta clase.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: Espacio.l),
              FilledButton(
                onPressed: malos.isNotEmpty
                    ? null
                    : () => Navigator.pop(
                        context,
                        Horario(
                          dias: [
                            for (final d in dias)
                              DiaClase(dia: d, inicio: _texto(_dias[d]!.$1), fin: _texto(_dias[d]!.$2)),
                          ],
                          aula: _aula.text.trim(),
                          edificio: _edificio.text.trim(),
                        ),
                      ),
                child: const Text('Guardar'),
              ),
              const SizedBox(height: Espacio.s),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: Text(importando ? 'Ahora no, lo pongo después' : 'Cancelar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inicio: las clases de hoy según el horario, por hora, con su lista a un toque.
class TarjetaHoyClases extends ConsumerWidget {
  const TarjetaHoyClases({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final horarios = ref.watch(horariosProvider).valueOrNull ?? const {};
    final avances = ref.watch(tableroProvider).valueOrNull ?? const [];
    final hoy = DateUtils.dateOnly(DateTime.now());
    final deHoy = [
      for (final a in avances)
        if (horarios[a.clase.id]?.de(hoy) case final dia?) (avance: a, dia: dia, horario: horarios[a.clase.id]!),
    ]..sort((x, y) => x.dia.inicio.compareTo(y.dia.inicio));
    if (deHoy.isEmpty) return const SizedBox.shrink();

    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Espacio.s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.xs, Espacio.l, Espacio.xs),
                child: Text('Tus clases de hoy', style: text.titleMedium),
              ),
              for (final c in deHoy)
                Builder(
                  builder: (context) {
                    final clase = c.avance.clase;
                    final tomada = c.avance.plan?.sesiones.any((s) => DateUtils.isSameDay(s.fecha, hoy)) ?? false;
                    return ListTile(
                      onTap: () => context.go('/asistencia/${clase.id}'),
                      leading: SizedBox(
                        width: 64,
                        child: Text(horaTexto(context, c.dia.inicio), style: text.labelLarge),
                      ),
                      title: Text(clase.asignatura, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text([clase.gradoSeccion, c.horario.lugar].where((t) => t.isNotEmpty).join(' · ')),
                      trailing: tomada
                          ? Tooltip(
                              message: 'Ya pasaste lista',
                              child: Icon(Icons.check_circle, color: scheme.primary),
                            )
                          : const Text('Pasar lista'),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
