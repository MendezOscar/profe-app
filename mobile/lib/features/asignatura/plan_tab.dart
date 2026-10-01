import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/planes/calculo_parcial.dart';
import '../../core/planes/modelos.dart';
import '../../core/providers.dart';
import '../../ui/barra_puntos.dart';
import '../../ui/estado_vacio.dart';
import '../../ui/shell.dart';
import '../clases/importar_cuadros.dart';
import 'parcial_cerrado.dart';
import '../../theme/tokens.dart';

/// El plan del parcial: rubros con sus puntos, que deberían sumar 100. Se puede cambiar
/// en cualquier momento; las actividades ya calificadas no se tocan.
class PlanTab extends ConsumerWidget {
  const PlanTab({super.key, required this.plan, required this.parciales});

  final PlanParcial plan;
  final List<Parcial> parciales;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultado = calcularParcial(plan);
    final repo = ref.read(planesRepositoryProvider);
    void cambiado() => planCambiado(ref, plan.claseId, plan.parcial.clave);

    if (plan.rubros.isEmpty) {
      return _SinPlan(plan: plan, parciales: parciales);
    }

    return ContenidoCentrado(
      maxAncho: 720,
      child: CustomScrollView(
        slivers: [
          if (plan.cerrado) SliverToBoxAdapter(child: ParcialCerrado(plan: plan)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.s),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BarraPuntos(valor: resultado.totalPlan, etiqueta: 'Total del plan', alto: 12),
                  if (resultado.totalPlan != 100)
                    Padding(
                      padding: const EdgeInsets.only(top: Espacio.s),
                      child: Text(
                        resultado.totalPlan < 100
                            ? 'Faltan ${formatoPuntos(100 - resultado.totalPlan)} puntos para llegar a 100.'
                            : 'El plan se pasa por ${formatoPuntos(resultado.totalPlan - 100)} puntos.',
                        style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverReorderableList(
            itemCount: plan.rubros.length,
            onReorder: (desde, hacia) async {
              final ids = plan.rubros.map((r) => r.id).toList();
              final id = ids.removeAt(desde);
              ids.insert(hacia > desde ? hacia - 1 : hacia, id);
              await repo.ordenarRubros(ids);
              cambiado();
            },
            itemBuilder: (context, i) {
              final rubro = plan.rubros[i];
              final asignado = resultado.asignadoPorRubro[rubro.id] ?? 0;
              final actividades = plan.actividades.where((a) => a.rubroId == rubro.id).length;
              return Padding(
                key: ValueKey(rubro.id),
                padding: const EdgeInsets.fromLTRB(Espacio.l, 0, Espacio.l, Espacio.s),
                child: Card(
                  child: InkWell(
                    onTap: plan.cerrado ? null : () => editarRubro(context, ref, plan, rubro: rubro),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(Espacio.xs, Espacio.m, Espacio.l, Espacio.m),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: i,
                            enabled: !plan.cerrado,
                            child: const Padding(
                              padding: EdgeInsets.all(Espacio.s),
                              child: Icon(Icons.drag_indicator, semanticLabel: 'Arrastrar para ordenar'),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                        child: Text(rubro.nombre, style: Theme.of(context).textTheme.titleMedium)),
                                    Text('${formatoPuntos(rubro.puntos)} pts',
                                        style: Theme.of(context).textTheme.titleMedium),
                                  ],
                                ),
                                const SizedBox(height: Espacio.s),
                                BarraPuntos(
                                  valor: asignado,
                                  total: rubro.puntos,
                                  alto: 6,
                                  etiqueta: actividades == 0
                                      ? 'Sin actividades'
                                      : '$actividades ${actividades == 1 ? 'actividad' : 'actividades'}',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          if (!plan.cerrado)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.s, Espacio.l, Espacio.xxl),
              sliver: SliverToBoxAdapter(
                child: OutlinedButton.icon(
                  onPressed: () => editarRubro(context, ref, plan),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar rubro'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SinPlan extends ConsumerWidget {
  const _SinPlan({required this.plan, required this.parciales});

  final PlanParcial plan;
  final List<Parcial> parciales;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(planesRepositoryProvider);
    final otros = parciales.where((p) => p.clave != plan.parcial.clave).toList();

    Future<void> usarPlantilla() async {
      final elegida = await elegirPlantilla(context, ref,
          mensaje: 'Se copia a ${plan.parcial.titulo}. Después puedes ajustar rubros y puntos.');
      if (elegida == null) return;
      await repo.aplicarPlantilla(plan.claseId, [plan.parcial.clave], elegida.rubros);
      planCambiado(ref, plan.claseId, plan.parcial.clave);
    }

    Future<void> copiarDe(Parcial desde) async {
      final ok = await repo.copiarPlan(plan.claseId, desde: desde.clave, hacia: plan.parcial.clave);
      if (!context.mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${desde.titulo} todavía no tiene plan.')));
      }
      planCambiado(ref, plan.claseId, plan.parcial.clave);
    }

    return EstadoVacio(
      icono: Icons.view_list_outlined,
      titulo: 'Arma el plan de ${plan.parcial.titulo}',
      mensaje: 'Reparte los 100 puntos del parcial en rubros: tareas, trabajos, exámenes… '
          'Cada actividad que crees después sumará puntos a su rubro.',
      accion: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: usarPlantilla,
            icon: const Icon(Icons.view_list),
            label: const Text('Usar una rúbrica'),
          ),
          for (final p in otros) ...[
            const SizedBox(height: Espacio.s),
            OutlinedButton.icon(
              onPressed: () => copiarDe(p),
              icon: const Icon(Icons.copy_outlined),
              label: Text('Copiar el plan de ${p.titulo}'),
            ),
          ],
          const SizedBox(height: Espacio.s),
          TextButton.icon(
            onPressed: () => editarRubro(context, ref, plan),
            icon: const Icon(Icons.add),
            label: const Text('Empezar desde cero'),
          ),
        ],
      ),
    );
  }
}

/// Alta o edición de un rubro. Borrar sólo se ofrece si no tiene actividades.
Future<void> editarRubro(BuildContext context, WidgetRef ref, PlanParcial plan, {Rubro? rubro}) async {
  final nombre = TextEditingController(text: rubro?.nombre ?? '');
  final libres = 100.0 - plan.rubros.where((r) => r.id != rubro?.id).fold(0.0, (s, r) => s + r.puntos);
  final puntos = TextEditingController(
      text: rubro != null ? formatoPuntos(rubro.puntos) : (libres > 0 ? formatoPuntos(libres) : ''));
  final form = GlobalKey<FormState>();
  final tieneActividades = rubro != null && plan.actividades.any((a) => a.rubroId == rubro.id);

  final accion = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      shape: const RoundedRectangleBorder(),
      title: Text(rubro == null ? 'Nuevo rubro' : 'Editar rubro'),
      content: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: nombre,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Tareas, Examen…'),
              validator: (v) => (v?.trim().isEmpty ?? true) ? 'Escribe un nombre' : null,
            ),
            const SizedBox(height: Espacio.l),
            TextFormField(
              controller: puntos,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(
                labelText: 'Puntos',
                suffixText: 'pts',
                helperText: 'Quedan ${formatoPuntos(libres < 0 ? 0 : libres)} de 100',
              ),
              validator: (v) {
                final n = leerPuntos(v);
                return n == null || n <= 0 || n > 100 ? 'Entre 0 y 100' : null;
              },
            ),
          ],
        ),
      ),
      actions: [
        if (rubro != null)
          TextButton(
            onPressed: tieneActividades ? null : () => Navigator.pop(context, 'eliminar'),
            child: Text(tieneActividades ? 'Tiene actividades' : 'Eliminar'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) Navigator.pop(context, 'guardar');
          },
          child: const Text('Guardar'),
        ),
      ],
    ),
  );

  final repo = ref.read(planesRepositoryProvider);
  if (accion == 'guardar') {
    await repo.guardarRubro(plan.claseId, plan.parcial.clave,
        id: rubro?.id, nombre: nombre.text, puntos: leerPuntos(puntos.text)!, orden: rubro?.orden);
  } else if (accion == 'eliminar') {
    await repo.eliminarRubro(rubro!.id);
  } else {
    return;
  }
  planCambiado(ref, plan.claseId, plan.parcial.clave);
}

/// Acepta coma o punto decimal, como se escriba en el teclado del teléfono.
double? leerPuntos(String? texto) => double.tryParse((texto ?? '').trim().replaceAll(',', '.'));
