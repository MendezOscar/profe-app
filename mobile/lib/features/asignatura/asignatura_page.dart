import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/planes/modelos.dart';
import '../../core/providers.dart';
import '../../ui/estado_vacio.dart';
import '../clases/eliminar_clase.dart';
import 'actividades_tab.dart';
import 'estadisticas_tab.dart';
import 'libro_tab.dart';
import 'plan_tab.dart';

/// Una asignatura (un cuadro de SACE) trabajada por parcial: el plan de puntos, las
/// actividades y el libro de notas. El cuadro original queda a un toque para exportar.
class AsignaturaPage extends ConsumerStatefulWidget {
  const AsignaturaPage({super.key, required this.claseId, this.parcial, this.pestana});

  final String claseId;

  /// Clave del parcial a abrir; si no viene, el primero sin cerrar.
  final String? parcial;

  /// Pestaña a abrir (0 Plan … 3 Estadísticas), por ejemplo desde un aviso.
  final int? pestana;

  @override
  ConsumerState<AsignaturaPage> createState() => _AsignaturaPageState();
}

class _AsignaturaPageState extends ConsumerState<AsignaturaPage> {
  String? _parcial;

  @override
  Widget build(BuildContext context) {
    final clase = ref.watch(claseProvider(widget.claseId));
    final parciales = ref.watch(parcialesProvider(widget.claseId));
    final resumen = clase.valueOrNull?.resumen;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return parciales.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(appBar: AppBar(), body: Center(child: Text('$error'))),
      data: (lista) {
        final actual = _elegido(lista);
        return DefaultTabController(
          length: 4,
          initialIndex: (widget.pestana ?? 0).clamp(0, 3),
          child: Scaffold(
            appBar: AppBar(
              leading: BackButton(onPressed: () => context.go('/inicio')),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(resumen?.asignatura ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (resumen != null)
                    Text(
                      [resumen.gradoSeccion, resumen.jornada].where((t) => t.isNotEmpty).join(' · '),
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Pasar lista',
                  onPressed: () => context.go('/asistencia/${widget.claseId}'),
                  icon: const Icon(Icons.fact_check_outlined),
                ),
                IconButton(
                  tooltip: 'Cuadro de SACE y exportar',
                  onPressed: () => context.go('/inicio/asignaturas/${widget.claseId}/cuadro'),
                  icon: const Icon(Icons.table_view_outlined),
                ),
                // onSelected y no onTap del ítem: el cierre del menú se llevaría el diálogo.
                if (resumen != null)
                  PopupMenuButton<String>(
                    onSelected: (_) => eliminarClase(context, ref, resumen),
                    itemBuilder: (context) => const [PopupMenuItem(value: 'eliminar', child: Text('Eliminar asignatura'))],
                  ),
              ],
              bottom: actual == null
                  ? null
                  : PreferredSize(
                      preferredSize: const Size.fromHeight(112),
                      child: Column(
                        children: [
                          _SelectorParcial(
                            parciales: lista,
                            actual: actual,
                            onCambio: (p) => setState(() => _parcial = p.clave),
                          ),
                          const TabBar(
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            tabs: [Tab(text: 'Plan'), Tab(text: 'Actividades'), Tab(text: 'Notas'), Tab(text: 'Estadísticas')],
                          ),
                        ],
                      ),
                    ),
            ),
            body: actual == null
                ? EstadoVacio(
                    icono: Icons.table_view_outlined,
                    titulo: 'Este cuadro no trae parciales',
                    mensaje: 'Puedes capturar sus columnas directamente en el cuadro de SACE.',
                    accion: FilledButton(
                      onPressed: () => context.go('/inicio/asignaturas/${widget.claseId}/cuadro'),
                      child: const Text('Abrir cuadro'),
                    ),
                  )
                : _Contenido(claseId: widget.claseId, parcial: actual, parciales: lista),
          ),
        );
      },
    );
  }

  Parcial? _elegido(List<Parcial> lista) {
    if (lista.isEmpty) return null;
    final clave = _parcial ?? widget.parcial;
    return lista.where((p) => p.clave == clave).firstOrNull ?? lista.first;
  }
}

class _SelectorParcial extends StatelessWidget {
  const _SelectorParcial({required this.parciales, required this.actual, required this.onCambio});

  final List<Parcial> parciales;
  final Parcial actual;
  final ValueChanged<Parcial> onCambio;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          for (final p in parciales)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(p.titulo),
                selected: p.clave == actual.clave,
                onSelected: (_) => onCambio(p),
              ),
            ),
        ],
      ),
    );
  }
}

class _Contenido extends ConsumerWidget {
  const _Contenido({required this.claseId, required this.parcial, required this.parciales});

  final String claseId;
  final Parcial parcial;
  final List<Parcial> parciales;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(planProvider((claseId, parcial.clave)));
    return plan.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (plan) => TabBarView(
        children: [
          PlanTab(plan: plan, parciales: parciales),
          ActividadesTab(plan: plan),
          LibroTab(plan: plan),
          EstadisticasTab(plan: plan),
        ],
      ),
    );
  }
}
