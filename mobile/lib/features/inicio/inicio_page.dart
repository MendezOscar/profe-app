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
import '../../core/avisos/avisos.dart';
import '../avisos/avisos_page.dart';
import '../clases/importar_cuadros.dart';
import '../../theme/tokens.dart';
import '../../ui/esqueleto.dart';
import '../../ui/estado_error.dart';

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
              padding: const EdgeInsets.only(right: Espacio.l),
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
        loading: () => const EsqueletoTarjetas(),
        error: (error, _) => EstadoError(error: error, reintentar: () => ref.invalidate(tableroProvider)),
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
                    const SliverToBoxAdapter(child: _LoUrgente()),
                    SliverToBoxAdapter(child: _PrimerosPasos(avances: avances)),
                    SliverToBoxAdapter(child: _Resumen(avances: avances)),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.s, Espacio.l, Espacio.bajoBotonFlotante),
                      sliver: SliverGrid.builder(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 440,
                          mainAxisExtent: 252,
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
      padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, 0),
      child: Card(
        color: scheme.surface,
        shape: RoundedRectangleBorder(side: BorderSide(color: scheme.primary, width: 2)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.m, Espacio.s, Espacio.s),
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
                padding: const EdgeInsets.only(right: Espacio.s, bottom: Espacio.xs),
                child: LinearProgressIndicator(
                  value: hechos / pasos.length,
                  minHeight: 6,
                  backgroundColor: scheme.primaryContainer,
                ),
              ),
              for (final (hecho, titulo, detalle, ruta) in pasos)
                ListTile(
                  contentPadding: const EdgeInsets.only(right: Espacio.s),
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
    final enRiesgo = avances.fold(0, (s, a) => s + (a.estadisticas?.enRiesgo.length ?? 0));
    return Padding(
      padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.s),
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
      padding: const EdgeInsets.symmetric(horizontal: Espacio.m, vertical: Espacio.s),
      color: destacado ? scheme.primary : scheme.primaryContainer,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 18, color: destacado ? scheme.onPrimary : scheme.primary),
          const SizedBox(width: Espacio.s),
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
          padding: const EdgeInsets.all(Espacio.l),
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
                        const SizedBox(height: Espacio.xxs),
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
                      padding: const EdgeInsets.symmetric(horizontal: Espacio.s, vertical: Espacio.xs),
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
                    const SizedBox(width: Espacio.s),
                    Expanded(child: Text('Sin plan de calificación', style: text.bodyMedium)),
                  ],
                )
              else ...[
                // Lo primero que se lee: cómo va el grupo. El avance del plan, debajo y más chico.
                if (avance.estadisticas case final e? when e.promedio != null)
                  Row(
                    children: [
                      _Cifra(
                        valor: e.promedio!.toStringAsFixed(plan.cerrado ? 1 : 0) + (plan.cerrado ? '' : ' %'),
                        etiqueta: 'Promedio',
                        alerta: e.promedio! < notaMinima,
                      ),
                      const SizedBox(width: Espacio.xl),
                      _Cifra(valor: '${e.enRiesgo.length}', etiqueta: 'En riesgo', alerta: e.enRiesgo.isNotEmpty),
                    ],
                  ),
                const SizedBox(height: Espacio.m),
                BarraPuntos(valor: resultado!.asignado, total: resultado.totalPlan, etiqueta: 'Plan', alto: 6),
              ],
              const SizedBox(height: Espacio.m),
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        if (pendientes > 0 && !sinPlan) ...[
                          Icon(Icons.edit_note, size: 20, color: scheme.primary),
                          const SizedBox(width: Espacio.xs),
                        ],
                        Flexible(
                          child: Text(
                            sinPlan
                                ? 'Toca para armarlo'
                                : pendientes == 0
                                    ? 'Todo calificado'
                                    : '$pendientes por calificar',
                            style: (pendientes > 0 ? text.labelLarge : text.bodySmall)?.copyWith(
                                color: pendientes > 0 ? scheme.primary : scheme.onSurfaceVariant,
                                fontWeight: pendientes > 0 ? FontWeight.w700 : null),
                          ),
                        ),
                      ],
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

/// Un número grande con su etiqueta: lo que el docente busca al mirar la tarjeta.
class _Cifra extends StatelessWidget {
  const _Cifra({required this.valor, required this.etiqueta, this.alerta = false});

  final String valor;
  final String etiqueta;
  final bool alerta;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '$etiqueta: $valor',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(valor,
              style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800, color: alerta ? scheme.error : scheme.onSurface, height: 1.1)),
          Text(etiqueta, style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Lo primero de la pantalla: el aviso más importante, para resolverlo de un toque.
/// El resto queda en la campana.
class _LoUrgente extends ConsumerWidget {
  const _LoUrgente();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avisos = ref.watch(avisosProvider).valueOrNull ?? const <Aviso>[];
    if (avisos.isEmpty) return const SizedBox.shrink();
    final aviso = avisos.first;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final acento = aviso.urgente ? scheme.error : scheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, 0),
      child: Material(
        color: scheme.surfaceContainerLowest,
        child: InkWell(
          onTap: () => context.go(aviso.ruta ?? '/inicio/avisos'),
          child: Container(
            decoration: BoxDecoration(border: Border(left: BorderSide(color: acento, width: 4))),
            padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.m, Espacio.s, Espacio.m),
            child: Row(
              children: [
                Icon(aviso.tipo.icono, color: acento),
                const SizedBox(width: Espacio.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(aviso.titulo, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: Espacio.xxs),
                      Text(aviso.detalle, style: text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                if (avisos.length > 1)
                  Tooltip(
                    message: 'Ver los ${avisos.length} avisos',
                    child: TextButton(
                      onPressed: () => context.go('/inicio/avisos'),
                      child: Text('+${avisos.length - 1}'),
                    ),
                  )
                else
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
