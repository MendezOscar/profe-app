import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/planes/modelos.dart';
import '../../core/providers.dart';
import '../../ui/estado_vacio.dart';
import '../../ui/shell.dart';

/// Elegir la asignatura para pasar lista.
class AsistenciaPage extends ConsumerWidget {
  const AsistenciaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clases = ref.watch(clasesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Pasar lista')),
      body: clases.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (lista) => lista.isEmpty
            ? EstadoVacio(
                icono: Icons.fact_check_outlined,
                titulo: 'Sin asignaturas',
                mensaje: 'Importa tus cuadros de SACE desde Inicio para tener las listas de alumnos.',
                accion: FilledButton(onPressed: () => context.go('/inicio'), child: const Text('Ir a Inicio')),
              )
            : ContenidoCentrado(
                maxAncho: 720,
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: lista.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final c = lista[i];
                    return Card(
                      child: ListTile(
                        onTap: () => context.go('/asistencia/${c.id}'),
                        title: Text(c.asignatura),
                        subtitle: Text([c.gradoSeccion, c.jornada, '${c.alumnos} alumnos']
                            .where((t) => t.isNotEmpty)
                            .join(' · ')),
                        trailing: const Icon(Icons.chevron_right),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

/// Lista de un día. Todos empiezan presentes; tocar a un alumno cambia su estado
/// (presente → ausente → tarde → justificada). Sólo las ausencias van a SACE.
class PasarListaPage extends ConsumerStatefulWidget {
  const PasarListaPage({super.key, required this.claseId});

  final String claseId;

  @override
  ConsumerState<PasarListaPage> createState() => _PasarListaPageState();
}

class _PasarListaPageState extends ConsumerState<PasarListaPage> {
  DateTime _fecha = DateUtils.dateOnly(DateTime.now());
  String? _parcial;

  @override
  Widget build(BuildContext context) {
    final clase = ref.watch(claseProvider(widget.claseId)).valueOrNull?.resumen;
    final parciales = ref.watch(parcialesProvider(widget.claseId));
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/asistencia')),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pasar lista'),
            if (clase != null)
              Text(
                [clase.asignatura, clase.gradoSeccion].where((t) => t.isNotEmpty).join(' · '),
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
      body: parciales.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (lista) {
          if (lista.isEmpty) {
            return const EstadoVacio(
              icono: Icons.fact_check_outlined,
              titulo: 'El cuadro no trae parciales',
              mensaje: 'La asistencia se cuenta por parcial para llenar INASISTENCIAS.',
            );
          }
          final parcial = lista.where((p) => p.clave == _parcial).firstOrNull ?? lista.first;
          final plan = ref.watch(planProvider((widget.claseId, parcial.clave)));
          return plan.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('$error')),
            data: (plan) {
              // Al entrar, el parcial en curso: el primero sin cerrar.
              if (_parcial == null && plan.cerrado && lista.length > 1) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _saltarAbierto(lista));
              }
              return ContenidoCentrado(
                maxAncho: 720,
                child: _Lista(
                  plan: plan,
                  parciales: lista,
                  fecha: _fecha,
                  onFecha: (f) => setState(() => _fecha = f),
                  onParcial: (p) => setState(() => _parcial = p.clave),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _saltarAbierto(List<Parcial> lista) async {
    for (final p in lista) {
      final plan = await ref.read(planProvider((widget.claseId, p.clave)).future);
      if (!plan.cerrado) {
        if (mounted) setState(() => _parcial = p.clave);
        return;
      }
    }
    if (mounted) setState(() => _parcial = lista.last.clave);
  }
}

class _Lista extends ConsumerWidget {
  const _Lista({
    required this.plan,
    required this.parciales,
    required this.fecha,
    required this.onFecha,
    required this.onParcial,
  });

  final PlanParcial plan;
  final List<Parcial> parciales;
  final DateTime fecha;
  final ValueChanged<DateTime> onFecha;
  final ValueChanged<Parcial> onParcial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final repo = ref.read(planesRepositoryProvider);
    final sesion = plan.sesiones.where((s) => DateUtils.isSameDay(s.fecha, fecha)).firstOrNull;
    final estados = sesion == null ? const <String, EstadoAsistencia>{} : plan.asistencias[sesion.id] ?? const {};
    final conteo = {for (final e in EstadoAsistencia.values) e: 0};
    for (final a in plan.alumnos) {
      final e = estados[a.id] ?? EstadoAsistencia.presente;
      conteo[e] = conteo[e]! + 1;
    }
    void cambiado() => planCambiado(ref, plan.claseId, plan.parcial.clave);

    Future<void> marcar(AlumnoPlan alumno, EstadoAsistencia estado) async {
      final id = sesion?.id ?? await repo.sesion(plan.claseId, plan.parcial.clave, fecha);
      await repo.marcarAsistencia(id, alumno.id, estado);
      cambiado();
    }

    Future<void> tomarLista() async {
      await repo.sesion(plan.claseId, plan.parcial.clave, fecha);
      cambiado();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (parciales.length > 1)
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              children: [
                for (final p in parciales)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(p.titulo),
                      selected: p.clave == plan.parcial.clave,
                      onSelected: (_) => onParcial(p),
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Día anterior',
                onPressed: () => onFecha(fecha.subtract(const Duration(days: 1))),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () async {
                    final elegida = await showDatePicker(
                      context: context,
                      initialDate: fecha,
                      firstDate: DateTime(fecha.year - 1),
                      lastDate: DateTime.now(),
                    );
                    if (elegida != null) onFecha(elegida);
                  },
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(
                    DateUtils.isSameDay(fecha, DateTime.now())
                        ? 'Hoy, ${DateFormat.MMMMd('es').format(fecha)}'
                        : DateFormat.yMMMMEEEEd('es').format(fecha),
                    style: text.titleMedium,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Día siguiente',
                onPressed: DateUtils.isSameDay(fecha, DateTime.now())
                    ? null
                    : () => onFecha(fecha.add(const Duration(days: 1))),
                icon: const Icon(Icons.chevron_right),
              ),
              IconButton(
                tooltip: 'Listas anteriores',
                onPressed: plan.sesiones.isEmpty ? null : () => _historial(context, ref),
                icon: const Icon(Icons.history),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in EstadoAsistencia.values)
                _ChipConteo(estado: e, cantidad: conteo[e]!),
            ],
          ),
        ),
        const Divider(height: 2),
        if (sesion == null && !plan.cerrado)
          Container(
            color: scheme.primaryContainer,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text('Todavía no pasas lista este día. Marca solo a los que faltan.',
                      style: TextStyle(color: scheme.onPrimaryContainer)),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: tomarLista, child: const Text('Todos presentes')),
              ],
            ),
          ),
        if (plan.cerrado)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('${plan.parcial.titulo} está cerrado. Reábrelo para cambiar la asistencia.',
                style: text.bodySmall?.copyWith(color: scheme.error)),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 48),
            itemCount: plan.alumnos.length,
            itemBuilder: (context, i) {
              final alumno = plan.alumnos[i];
              final estado = estados[alumno.id] ?? EstadoAsistencia.presente;
              return ListTile(
                enabled: !plan.cerrado,
                leading: Text('${i + 1}', style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                minLeadingWidth: 24,
                title: Text(alumno.nombre, maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: _ChipEstado(estado: estado),
                onTap: () => marcar(alumno, estado.siguiente),
                onLongPress: () async {
                  final elegido = await showModalBottomSheet<EstadoAsistencia>(
                    context: context,
                    showDragHandle: true,
                    shape: const RoundedRectangleBorder(),
                    builder: (context) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final e in EstadoAsistencia.values)
                            ListTile(
                              leading: _ChipEstado(estado: e),
                              title: Text(e.etiqueta),
                              selected: e == estado,
                              onTap: () => Navigator.pop(context, e),
                            ),
                        ],
                      ),
                    ),
                  );
                  if (elegido != null) await marcar(alumno, elegido);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _historial(BuildContext context, WidgetRef ref) async {
    final elegida = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(),
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Listas de ${plan.parcial.titulo}', style: Theme.of(context).textTheme.titleLarge),
              ),
              for (final s in plan.sesiones)
                ListTile(
                  title: Text(DateFormat.yMMMMEEEEd('es').format(s.fecha)),
                  subtitle: Text(
                      '${(plan.asistencias[s.id] ?? const {}).values.where((e) => e == EstadoAsistencia.ausente).length} ausentes'),
                  trailing: plan.cerrado
                      ? null
                      : IconButton(
                          tooltip: 'Borrar esta lista',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await ref.read(planesRepositoryProvider).eliminarSesion(s.id);
                            planCambiado(ref, plan.claseId, plan.parcial.clave);
                            if (context.mounted) Navigator.pop(context);
                          },
                        ),
                  onTap: () => Navigator.pop(context, s.fecha),
                ),
            ],
          ),
        ),
      ),
    );
    if (elegida != null) onFecha(elegida);
  }
}

class _ChipEstado extends StatelessWidget {
  const _ChipEstado({required this.estado});

  final EstadoAsistencia estado;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (fondo, texto) = switch (estado) {
      EstadoAsistencia.presente => (scheme.primaryContainer, scheme.onPrimaryContainer),
      EstadoAsistencia.ausente => (scheme.error, scheme.onError),
      EstadoAsistencia.tarde => (const Color(0xFFFFE08A), scheme.onSurface),
      EstadoAsistencia.justificada => (scheme.secondary, scheme.onSecondary),
    };
    return Semantics(
      label: estado.etiqueta,
      excludeSemantics: true,
      child: Container(
        width: 104,
        padding: const EdgeInsets.symmetric(vertical: 8),
        color: fondo,
        alignment: Alignment.center,
        child: Text(estado.etiqueta, style: TextStyle(color: texto, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _ChipConteo extends StatelessWidget {
  const _ChipConteo({required this.estado, required this.cantidad});

  final EstadoAsistencia estado;
  final int cantidad;

  @override
  Widget build(BuildContext context) => Text(
        '${estado.etiqueta}: $cantidad',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: estado == EstadoAsistencia.ausente && cantidad > 0 ? FontWeight.w800 : FontWeight.w600,
              color: estado == EstadoAsistencia.ausente && cantidad > 0 ? Theme.of(context).colorScheme.error : null,
            ),
      );
}
