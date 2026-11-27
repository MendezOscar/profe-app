import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/planes/modelos.dart';
import '../../core/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/estado_error.dart';
import '../../ui/shell.dart';
import '../../core/planes/calculo_parcial.dart';

/// Las entregas y exámenes de la semana en todas las secciones, día por día. Tocar una
/// actividad abre su captura de notas.
class CalendarioPage extends ConsumerStatefulWidget {
  const CalendarioPage({super.key});

  @override
  ConsumerState<CalendarioPage> createState() => _CalendarioPageState();
}

class _CalendarioPageState extends ConsumerState<CalendarioPage> {
  static DateTime _lunesDe(DateTime d) => DateUtils.dateOnly(d).subtract(Duration(days: d.weekday - 1));

  late DateTime _lunes = _lunesDe(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final semana = ref.watch(calendarioProvider(_lunes));
    final domingo = _lunes.add(const Duration(days: 6));
    final esEsta = _lunes == _lunesDe(DateTime.now());
    final rango = _lunes.month == domingo.month
        ? '${_lunes.day}–${DateFormat.yMMMMd('es').format(domingo)}'
        : '${DateFormat.MMMd('es').format(_lunes)} – ${DateFormat.yMMMd('es').format(domingo)}';

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/inicio')),
        title: const Text('Calendario'),
      ),
      body: ContenidoCentrado(
        maxAncho: Medida.lectura,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Espacio.s, Espacio.s, Espacio.s, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Semana anterior',
                    onPressed: () => setState(() => _lunes = _lunes.subtract(const Duration(days: 7))),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(child: Text(rango, textAlign: TextAlign.center, style: text.titleMedium)),
                  IconButton(
                    tooltip: 'Semana siguiente',
                    onPressed: () => setState(() => _lunes = _lunes.add(const Duration(days: 7))),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
            if (!esEsta)
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _lunes = _lunesDe(DateTime.now())),
                  child: const Text('Ir a esta semana'),
                ),
              ),
            const Divider(height: 2),
            Expanded(
              child: semana.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => PaginaError(error: error, reintentar: () => ref.invalidate(calendarioProvider(_lunes))),
                data: (actividades) => _Semana(lunes: _lunes, actividades: actividades),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Semana extends StatelessWidget {
  const _Semana({required this.lunes, required this.actividades});

  final DateTime lunes;
  final List<ActividadCalendario> actividades;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final hoy = DateUtils.dateOnly(DateTime.now());
    return ListView(
      padding: const EdgeInsets.only(bottom: Espacio.xxxl),
      children: [
        if (actividades.isEmpty)
          Padding(
            padding: const EdgeInsets.all(Espacio.xl),
            child: Text('Sin entregas ni exámenes esta semana. Las actividades aparecen aquí según su fecha.',
                textAlign: TextAlign.center, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        for (var i = 0; i < 7; i++)
          () {
            final dia = lunes.add(Duration(days: i));
            final delDia = actividades.where((a) => DateUtils.isSameDay(a.fecha, dia)).toList();
            // Sábado y domingo sólo si tienen algo.
            if (delDia.isEmpty && (i >= 5 || actividades.isEmpty)) return const SizedBox.shrink();
            final esHoy = dia == hoy;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: esHoy ? scheme.primaryContainer : null,
                  padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.m, Espacio.l, Espacio.xs),
                  child: Text(
                    '${toBeginningOfSentenceCase(DateFormat.EEEE('es').format(dia))} ${dia.day}${esHoy ? ' · hoy' : ''}',
                    style: text.titleSmall?.copyWith(color: esHoy ? scheme.onPrimaryContainer : null),
                  ),
                ),
                if (delDia.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.xs, Espacio.l, Espacio.s),
                    child: Text('Nada programado', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                for (final a in delDia)
                  ListTile(
                    title: Text(a.titulo, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${a.asignatura} · ${a.gradoSeccion} · ${formatoPuntos(a.puntos)} pts',
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: a.calificada
                        ? Icon(Icons.check_circle_outline, color: scheme.primary, semanticLabel: 'Calificada')
                        : Text('${a.calificados}/${a.alumnos}', style: text.labelLarge),
                    onTap: () => context.go('/inicio/asignaturas/${a.claseId}/actividades/${a.id}'
                        '?parcial=${Uri.encodeComponent(a.parcial)}'),
                  ),
                const Divider(height: 1),
              ],
            );
          }(),
      ],
    );
  }
}
