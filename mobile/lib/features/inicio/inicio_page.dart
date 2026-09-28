import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/planes/estadisticas.dart';
import '../../core/preferencias.dart';
import '../../core/providers.dart';
import '../../core/sync/sync_controller.dart';
import '../../ui/barra_puntos.dart';
import '../../ui/estado_vacio.dart';
import '../../ui/indicador_sync.dart';
import '../../ui/shell.dart';
import '../avisos/avisos_page.dart';
import '../clases/importar_cuadros.dart';

/// Tablero del periodo: una tarjeta por asignatura (un cuadro de SACE importado) con
/// su parcial en curso, cómo va el plan y qué falta calificar.
class InicioPage extends ConsumerWidget {
  const InicioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tablero = ref.watch(tableroProvider);
    final nombre = ref.watch(sessionProvider.select((s) => s?.fullName.split(' ').first)) ?? 'docente';
    final compacto = Ancho.de(context) == Ancho.compacto;
    final hayClases = tablero.valueOrNull?.isNotEmpty == true;

    return Scaffold(
      appBar: AppBar(
        title: Text('Hola, $nombre'),
        actions: [
          if (hayClases) const BotonAvisos(),
          if (compacto) const IndicadorSync(),
          if (hayClases && !compacto)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton.icon(
                onPressed: () => importarCuadros(context, ref),
                icon: const Icon(Icons.upload_file),
                label: const Text('Importar cuadros'),
              ),
            ),
        ],
      ),
      floatingActionButton: hayClases && compacto
          ? FloatingActionButton.extended(
              shape: const RoundedRectangleBorder(),
              onPressed: () => importarCuadros(context, ref),
              icon: const Icon(Icons.upload_file),
              label: const Text('Importar'),
            )
          : null,
      body: tablero.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('No se pudo abrir la base local: $error')),
        data: (avances) => avances.isEmpty
            ? EstadoVacio(
                icono: Icons.upload_file_outlined,
                titulo: 'Empieza con tus cuadros de SACE',
                mensaje: 'En SACE ve a Notas → Descargar Archivos Notas y baja el cuadro de cada asignatura. '
                    'Impórtalos aquí, todos a la vez: después trabajas sin internet.',
                accion: FilledButton.icon(
                  onPressed: () => importarCuadros(context, ref),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Importar cuadros de SACE'),
                ),
              )
            : RefreshIndicator(
                onRefresh: () => ref.read(syncControllerProvider.notifier).sincronizar(),
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _PrimerosPasos(avances: avances)),
                    SliverToBoxAdapter(child: _Resumen(avances: avances)),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      sliver: SliverGrid.builder(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 440,
                          mainAxisExtent: 236,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: avances.length,
                        itemBuilder: (context, i) => _TarjetaAsignatura(avance: avances[i]),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Guía de primeros pasos: lo básico de la app en orden, cada paso lleva a donde se hace.
/// Se oculta sola al completarla, o cuando el docente la cierra.
class _PrimerosPasos extends ConsumerWidget {
  const _PrimerosPasos({required this.avances});

  final List<AvanceClase> avances;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oculta = ref.watch(banderaProvider(Bandera.primerosPasosOcultos));
    final progreso = ref.watch(progresoProvider).valueOrNull;
    if (oculta || progreso == null) return const SizedBox.shrink();

    final primera = '/inicio/asignaturas/${avances.first.clase.id}';
    final pasos = [
      (true, 'Importa tus cuadros de SACE', 'Cada archivo es una asignatura.', null),
      (progreso.plan, 'Arma el plan de un parcial', 'Reparte los 100 puntos en rubros.', primera),
      (progreso.actividad, 'Crea tu primera actividad', 'Una tarea, un trabajo o un examen.', primera),
      (progreso.lista, 'Pasa lista', 'Marca solo a los que faltan.', '/asistencia/${avances.first.clase.id}'),
      (progreso.cierre, 'Cierra un parcial y exporta', 'Las notas pasan al cuadro de SACE.', primera),
    ];
    final hechos = pasos.where((p) => p.$1).length;
    if (hechos == pasos.length) return const SizedBox.shrink();

    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Card(
        color: scheme.surface,
        shape: RoundedRectangleBorder(side: BorderSide(color: scheme.primary, width: 2)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Primeros pasos', style: text.titleMedium)),
                  Text('$hechos de ${pasos.length}', style: text.labelLarge),
                  IconButton(
                    tooltip: 'Ocultar la guía',
                    onPressed: () => ref.read(banderaProvider(Bandera.primerosPasosOcultos).notifier).poner(true),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 4),
                child: LinearProgressIndicator(
                  value: hechos / pasos.length,
                  minHeight: 6,
                  backgroundColor: scheme.primaryContainer,
                ),
              ),
              for (final (hecho, titulo, detalle, ruta) in pasos)
                ListTile(
                  contentPadding: const EdgeInsets.only(right: 8),
                  leading: Icon(hecho ? Icons.check_box : Icons.check_box_outline_blank,
                      color: hecho ? scheme.primary : scheme.onSurfaceVariant),
                  title: Text(titulo,
                      style: TextStyle(
                        decoration: hecho ? TextDecoration.lineThrough : null,
                        color: hecho ? scheme.onSurfaceVariant : null,
                        fontWeight: hecho ? null : FontWeight.w600,
                      )),
                  subtitle: hecho ? null : Text(detalle),
                  trailing: hecho || ruta == null ? null : const Icon(Icons.chevron_right),
                  onTap: hecho || ruta == null ? null : () => context.go(ruta),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.avances});

  final List<AvanceClase> avances;

  @override
  Widget build(BuildContext context) {
    final alumnos = avances.fold(0, (s, a) => s + a.clase.alumnos);
    final porCalificar = avances.fold(0, (s, a) => s + (a.resultado?.actividadesIncompletas.length ?? 0));
    final sinPlan = avances.where((a) => a.plan != null && a.plan!.rubros.isEmpty).length;
    final enRiesgo = avances.fold(0, (s, a) => s + (a.plan == null ? 0 : calcularEstadisticas(a.plan!).enRiesgo.length));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _Dato(icono: Icons.menu_book_outlined, texto: '${avances.length} asignaturas'),
          _Dato(icono: Icons.groups_outlined, texto: '$alumnos alumnos'),
          if (porCalificar > 0) _Dato(icono: Icons.edit_note, texto: '$porCalificar por calificar', destacado: true),
          if (sinPlan > 0) _Dato(icono: Icons.warning_amber, texto: '$sinPlan sin plan', destacado: true),
          if (enRiesgo > 0) _Dato(icono: Icons.trending_down, texto: '$enRiesgo alumnos en riesgo', destacado: true),
        ],
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.icono, required this.texto, this.destacado = false});

  final IconData icono;
  final String texto;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: destacado ? scheme.primary : scheme.primaryContainer,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 18, color: destacado ? scheme.onPrimary : scheme.primary),
          const SizedBox(width: 6),
          Text(texto,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: destacado ? scheme.onPrimary : scheme.onPrimaryContainer, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _TarjetaAsignatura extends StatelessWidget {
  const _TarjetaAsignatura({required this.avance});

  final AvanceClase avance;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final clase = avance.clase;
    final plan = avance.plan;
    final resultado = avance.resultado;
    final sinPlan = plan != null && plan.rubros.isEmpty;
    final pendientes = resultado?.actividadesIncompletas.length ?? 0;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/inicio/asignaturas/${clase.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(clase.asignatura, style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(
                          [clase.gradoSeccion, clase.jornada, '${clase.alumnos} alumnos']
                              .where((t) => t.isNotEmpty)
                              .join(' · '),
                          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (plan != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      color: plan.cerrado ? scheme.secondary : scheme.primary,
                      child: Text(
                        plan.cerrado ? 'Cerrado' : plan.parcial.titulo,
                        style: text.labelSmall?.copyWith(color: scheme.onPrimary),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              if (plan == null)
                Text('La plantilla no trae parciales.', style: text.bodySmall)
              else if (sinPlan)
                Row(
                  children: [
                    Icon(Icons.warning_amber, size: 18, color: scheme.error),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Sin plan de calificación', style: text.bodyMedium)),
                  ],
                )
              else ...[
                BarraPuntos(valor: resultado!.asignado, total: resultado.totalPlan, etiqueta: 'Actividades del plan'),
                if (calcularEstadisticas(plan) case final e when e.promedio != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    [
                      'Promedio ${e.promedio!.toStringAsFixed(1)}${plan.cerrado ? '' : ' %'}',
                      if (e.enRiesgo.isNotEmpty) '${e.enRiesgo.length} en riesgo',
                    ].join(' · '),
                    style: text.bodySmall?.copyWith(
                        color: e.enRiesgo.isNotEmpty ? scheme.error : scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      sinPlan
                          ? 'Toca para armarlo'
                          : pendientes == 0
                              ? 'Todo calificado'
                              : '$pendientes ${pendientes == 1 ? 'actividad' : 'actividades'} por calificar',
                      style: text.bodySmall?.copyWith(
                          color: pendientes > 0 ? scheme.primary : scheme.onSurfaceVariant,
                          fontWeight: pendientes > 0 ? FontWeight.w600 : null),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => context.go('/asistencia/${clase.id}'),
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: const Text('Pasar lista'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
