import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/centro/mi_carga.dart';
import '../../core/providers.dart';
import '../../theme/tokens.dart';
import '../clases/importar_cuadros.dart';
import 'lista_diaria_page.dart';

final _identidadesProvider = FutureProvider<Map<String, Set<String>>>((ref) async {
  await ref.watch(clasesProvider.future);
  return ref.watch(clasesRepositoryProvider).identidadesPorClase();
});

/// En Inicio: lo que el centro le asignó al docente y qué cuadros de SACE le faltan.
/// No aparece sin centro o sin internet.
class TarjetaCargaCentro extends ConsumerWidget {
  const TarjetaCargaCentro({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final carga = ref.watch(miCargaProvider).valueOrNull;
    final clases = ref.watch(clasesProvider).valueOrNull;
    final identidades = ref.watch(_identidadesProvider).valueOrNull;
    if (carga == null || carga.secciones.isEmpty || clases == null || identidades == null) return const SizedBox.shrink();

    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final pendientes = [
      for (final s in carga.secciones)
        for (final a in s.asignaturas)
          if (!tieneCuadro(s, a, clases, identidades)) (s, a),
    ];
    final total = carga.secciones.fold(0, (n, s) => n + s.asignaturas.length);

    return Padding(
      padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, 0),
      child: Card(
        margin: EdgeInsets.zero,
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Icon(Icons.apartment_outlined, color: pendientes.isEmpty ? scheme.primary : scheme.error),
          title: Text('Tu carga en ${carga.centro}', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          subtitle: Text(
            pendientes.isEmpty
                ? '$total ${total == 1 ? 'asignatura' : 'asignaturas'}, todas con su cuadro en la app'
                : '${pendientes.length} de $total sin su cuadro de SACE en la app',
            style: text.bodySmall?.copyWith(color: pendientes.isEmpty ? null : scheme.error),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(Espacio.l, 0, Espacio.l, Espacio.m),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in carga.secciones) ...[
              const SizedBox(height: Espacio.s),
              Text('${s.titulo}${s.esGuia ? ' · eres guía' : ''} · ${s.alumnos.where((a) => a.activo).length} alumnos',
                  style: text.labelLarge),
              if (s.esGuia)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => ListaDiariaPage(seccionId: s.id, titulo: '${s.grado} ${s.nombre}'),
                    )),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Pasar lista del día'),
                  ),
                ),
              for (final a in s.asignaturas)
                Padding(
                  padding: const EdgeInsets.only(top: Espacio.xxs),
                  child: Row(
                    children: [
                      Icon(
                        tieneCuadro(s, a, clases, identidades) ? Icons.check_circle_outline : Icons.error_outline,
                        size: 18,
                        color: tieneCuadro(s, a, clases, identidades) ? scheme.primary : scheme.error,
                      ),
                      const SizedBox(width: Espacio.s),
                      Expanded(
                        child: Text(
                          tieneCuadro(s, a, clases, identidades) ? a : '$a — falta importar su cuadro',
                          style: text.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (pendientes.isNotEmpty) ...[
              const SizedBox(height: Espacio.m),
              Text('Descarga esos cuadros en SACE (Notas → Descargar Archivos Notas) e impórtalos.',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: Espacio.s),
              FilledButton.icon(
                onPressed: () => importarCuadros(context, ref),
                icon: const Icon(Icons.upload_file),
                label: const Text('Importar cuadros'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// En Inicio: las clases de hoy según el horario del centro. No aparece sin clases hoy.
class TarjetaHoyCentro extends ConsumerWidget {
  const TarjetaHoyCentro({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final carga = ref.watch(miCargaProvider).valueOrNull;
    final hoy = carga?.delDia(DateTime.now().weekday) ?? const <ClaseHorario>[];
    if (hoy.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final ahora = TimeOfDay.now();
    final minutos = ahora.hour * 60 + ahora.minute;
    int enMinutos(String t) => int.parse(t.substring(0, 2)) * 60 + int.parse(t.substring(3, 5));

    return Padding(
      padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, 0),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(Espacio.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TUS CLASES DE HOY', style: text.labelSmall),
              const SizedBox(height: Espacio.s),
              for (final c in hoy)
                Padding(
                  padding: const EdgeInsets.only(bottom: Espacio.xs),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 96,
                        child: Text('${ClaseHorario.hora(c.inicio)}–${ClaseHorario.hora(c.fin)}',
                            style: text.labelLarge?.copyWith(
                              color: minutos >= enMinutos(c.inicio) && minutos < enMinutos(c.fin) ? scheme.primary : null,
                              fontWeight: minutos >= enMinutos(c.inicio) && minutos < enMinutos(c.fin) ? FontWeight.w800 : null,
                            )),
                      ),
                      Expanded(
                        child: Text('${c.asignatura} · ${c.seccion}${c.aula == null ? '' : ' · ${c.aula}'}',
                            style: text.bodyMedium?.copyWith(
                                color: minutos >= enMinutos(c.fin) ? scheme.onSurfaceVariant : null)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// En una asignatura: diferencias entre su cuadro de SACE y la matrícula del centro
/// (retirados que siguen en el cuadro, nuevos que aún no están).
class AvisoListaCentro extends ConsumerWidget {
  const AvisoListaCentro({super.key, required this.claseId});

  final String claseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final carga = ref.watch(miCargaProvider).valueOrNull;
    final clase = ref.watch(claseProvider(claseId)).valueOrNull;
    if (carga == null || clase == null) return const SizedBox.shrink();
    final cotejo = cotejar(clase.alumnos, carga.secciones);
    if (cotejo == null || !cotejo.hayDiferencias) return const SizedBox.shrink();

    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final partes = [
      if (cotejo.retirados.isNotEmpty)
        '${cotejo.retirados.length} ${cotejo.retirados.length == 1 ? 'retirado o trasladado' : 'retirados o trasladados'}',
      if (cotejo.faltan.isNotEmpty)
        '${cotejo.faltan.length} ${cotejo.faltan.length == 1 ? 'nuevo que no está' : 'nuevos que no están'} en tu cuadro',
    ];
    return Material(
      color: scheme.surfaceContainerLowest,
      child: InkWell(
        onTap: () => _detalle(context, cotejo),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(border: Border(left: BorderSide(color: scheme.error, width: 4))),
          padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.s, Espacio.s, Espacio.s),
          child: Row(
            children: [
              Icon(Icons.apartment_outlined, color: scheme.error),
              const SizedBox(width: Espacio.m),
              Expanded(child: Text('Según la matrícula del centro: ${partes.join(' y ')}.', style: text.bodySmall)),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _detalle(BuildContext context, Cotejo cotejo) => showDialog<void>(
        context: context,
        builder: (context) {
          final text = Theme.of(context).textTheme;
          return AlertDialog(
            shape: const RoundedRectangleBorder(),
            title: Text('Lista de ${cotejo.seccion.titulo}'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (cotejo.retirados.isNotEmpty) ...[
                      Text('RETIRADOS O TRASLADADOS', style: text.labelSmall),
                      const SizedBox(height: Espacio.xs),
                      for (final a in cotejo.retirados)
                        Text('• ${a.nombre} (${a.estado == 'trasladada' ? 'trasladado' : 'retirado'})'),
                      const SizedBox(height: Espacio.m),
                    ],
                    if (cotejo.faltan.isNotEmpty) ...[
                      Text('MATRICULADOS QUE NO ESTÁN EN TU CUADRO', style: text.labelSmall),
                      const SizedBox(height: Espacio.xs),
                      for (final a in cotejo.faltan) Text('• ${a.nombre}'),
                      const SizedBox(height: Espacio.m),
                    ],
                    const Text('Para actualizar la lista, descarga de nuevo el cuadro en SACE e impórtalo: '
                        'lo que ya capturaste se conserva.'),
                  ],
                ),
              ),
            ),
            actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
          );
        },
      );
}
