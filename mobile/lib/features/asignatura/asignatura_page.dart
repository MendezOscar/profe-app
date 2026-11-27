import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/informes/compartir.dart';
import '../../core/informes/informes_pdf.dart';
import '../../core/planes/modelos.dart';
import '../../core/providers.dart';
import '../../ui/estado_vacio.dart';
import '../centro/carga_centro.dart';
import '../clases/eliminar_clase.dart';
import '../clases/horario_clase.dart';
import 'actividades_tab.dart';
import 'estadisticas_tab.dart';
import 'libro_tab.dart';
import 'plan_tab.dart';
import '../../ui/esqueleto.dart';
import '../../ui/estado_error.dart';
import '../../ui/selector_parcial.dart';

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
      loading: () => const EsqueletoPagina(),
      error: (error, _) => PaginaError(error: error, reintentar: () => ref.invalidate(parcialesProvider(widget.claseId))),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                    tooltip: 'Más opciones',
                    onSelected: (opcion) => switch (opcion) {
                      'equipos' => context.go('/inicio/asignaturas/${widget.claseId}/equipos'),
                      'horario' => editarHorario(context, ref, resumen),
                      'libro' => _imprimir(context, actual, asistencia: false),
                      'asistencia' => _imprimir(context, actual, asistencia: true),
                      _ => eliminarClase(context, ref, resumen),
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'horario',
                        child: ListTile(leading: Icon(Icons.schedule), title: Text('Horario y aula')),
                      ),
                      const PopupMenuItem(
                        value: 'equipos',
                        child: ListTile(leading: Icon(Icons.groups_outlined), title: Text('Equipos de trabajo')),
                      ),
                      if (actual != null) ...[
                        const PopupMenuItem(
                          value: 'libro',
                          child: ListTile(leading: Icon(Icons.picture_as_pdf_outlined), title: Text('Libro de notas en PDF')),
                        ),
                        const PopupMenuItem(
                          value: 'asistencia',
                          child: ListTile(leading: Icon(Icons.picture_as_pdf_outlined), title: Text('Asistencia en PDF')),
                        ),
                      ],
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'eliminar',
                        child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Eliminar asignatura')),
                      ),
                    ],
                  ),
              ],
              bottom: actual == null
                  ? null
                  : PreferredSize(
                      // Crece con la letra del sistema: con alto fijo se cortaban los parciales.
                      preferredSize: Size.fromHeight(
                          SelectorParcial.alto(context) + 48 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0)),
                      child: Column(
                        children: [
                          SelectorParcial(
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
                : Column(
                    children: [
                      AvisoListaCentro(claseId: widget.claseId),
                      Expanded(child: _Contenido(claseId: widget.claseId, parcial: actual, parciales: lista)),
                    ],
                  ),
          ),
        );
      },
    );
  }

  /// Libro de notas o lista de asistencia del parcial, en PDF para imprimir o compartir.
  Future<void> _imprimir(BuildContext context, Parcial? parcial, {required bool asistencia}) async {
    if (parcial == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final clase = await ref.read(claseProvider(widget.claseId).future);
      final plan = await ref.read(planProvider((widget.claseId, parcial.clave)).future);
      final docente = ref.read(sessionProvider)?.fullName ?? '';
      final bytes = asistencia
          ? await InformesPdf.listaAsistencia(clase: clase.resumen, docente: docente, plan: plan)
          : await InformesPdf.libroDeNotas(clase: clase.resumen, docente: docente, plan: plan);
      if (!context.mounted) return;
      await compartirPdf(
        context,
        bytes,
        nombreArchivo('${asistencia ? 'Asistencia' : 'Libro de notas'} ${clase.resumen.asignatura} '
            '${clase.resumen.gradoSeccion} ${parcial.titulo}'),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('No se pudo crear el PDF: $error')));
    }
  }

  Parcial? _elegido(List<Parcial> lista) {
    if (lista.isEmpty) return null;
    final clave = _parcial ?? widget.parcial;
    return lista.where((p) => p.clave == clave).firstOrNull ?? lista.first;
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
      loading: () => const EsqueletoLista(),
      error: (error, _) => EstadoError(error: error, reintentar: () => ref.invalidate(planProvider((claseId, parcial.clave)))),
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
