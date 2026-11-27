import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../theme/tokens.dart';
import '../../../ui/esqueleto.dart';
import '../../../ui/estado_error.dart';
import 'comun_centro.dart';
import 'convivencia_tab.dart';

final tableroCentroProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
    (ref) => ref.watch(apiClientProvider).get('/centro/tablero', parse: (d) => d as Map<String, dynamic>));

/// Pestañas del panel a las que lleva el tablero.
enum DestinoTablero { asistencia, excusas, incidencias, comunicados, reportes, estadisticas }

String _hace(String? iso) {
  if (iso == null) return 'nunca ha respaldado';
  final dias = DateTime.now().difference(DateTime.parse(iso).toLocal()).inDays;
  return 'sin actividad hace $dias días';
}

/// Primera pantalla del panel: lo de hoy, la tendencia de la lista del día y lo pendiente.
class TableroTab extends ConsumerWidget {
  const TableroTab({super.key, required this.ir, required this.puedeEditar});

  final ValueChanged<DestinoTablero> ir;
  final bool puedeEditar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tablero = ref.watch(tableroCentroProvider);
    return tablero.when(
      loading: () => const EsqueletoLista(filas: 5, conTarjeta: true),
      error: (e, _) => EstadoError(error: e, reintentar: () => ref.invalidate(tableroCentroProvider)),
      data: (t) {
        final hoy = t['hoy'] as Map<String, dynamic>;
        return RefreshIndicator(
          onRefresh: () => ref.refresh(tableroCentroProvider.future),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.xxxl),
                children: [
                  EncabezadoPestana(
                    titulo: t['anio'] == null ? 'Inicio' : 'Año lectivo ${t['anio']}',
                    ayuda: t['anio'] == null
                        ? 'Crea el año lectivo en la pestaña Año lectivo para empezar.'
                        : 'Día hábil ${t['diasHabilesTranscurridos']} de ${t['diasHabilesAnio']}.',
                    acciones: [
                      if (puedeEditar) ...[
                        OutlinedButton.icon(
                          onPressed: () => registrarExcusa(context, ref).then((_) => ref.invalidate(tableroCentroProvider)),
                          icon: const Icon(Icons.event_busy_outlined),
                          label: const Text('Excusa'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => registrarIncidencia(context, ref).then((_) => ref.invalidate(tableroCentroProvider)),
                          icon: const Icon(Icons.report_outlined),
                          label: const Text('Incidencia'),
                        ),
                      ],
                    ],
                  ),
                  _Cifras(t: t),
                  const SizedBox(height: Espacio.l),
                  _Hoy(hoy: hoy, ir: ir),
                  const SizedBox(height: Espacio.l),
                  _Tendencia(dias: (t['tendencia'] as List).cast<Map<String, dynamic>>(), ir: ir),
                  const SizedBox(height: Espacio.l),
                  _Pendientes(t: t, ir: ir),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Cifras extends StatelessWidget {
  const _Cifras({required this.t});

  final Map<String, dynamic> t;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final alumnos = t['alumnos'] as int;
    final familias = t['familiasConCuenta'] as int;
    Widget cifra(String valor, String etiqueta, {String? detalle}) => SizedBox(
          width: 160,
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(Espacio.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(valor, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                  Text(etiqueta, style: text.labelLarge),
                  if (detalle != null) Text(detalle, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        );
    return Wrap(
      spacing: Espacio.m,
      runSpacing: Espacio.m,
      children: [
        cifra('$alumnos', 'Alumnos activos', detalle: '${t['secciones']} secciones'),
        cifra('${t['docentes']}', 'Docentes', detalle: 'de ${t['maxDocentes']} de la licencia'),
        cifra(alumnos == 0 ? '—' : '${(100 * familias / alumnos).round()} %', 'Familias con cuenta',
            detalle: '$familias de $alumnos alumnos'),
        cifra('${t['comunicadosMes']}', 'Comunicados', detalle: 'últimos 30 días'),
      ],
    );
  }
}

class _Hoy extends StatelessWidget {
  const _Hoy({required this.hoy, required this.ir});

  final Map<String, dynamic> hoy;
  final ValueChanged<DestinoTablero> ir;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final conGuia = hoy['seccionesConGuia'] as int;
    final conLista = hoy['seccionesConLista'] as int;
    final faltas = (hoy['faltas'] as List).cast<Map<String, dynamic>>();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Espacio.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('HOY · ${fechaIso(hoy['fecha'] as String)}', style: text.labelSmall)),
                TextButton(onPressed: () => ir(DestinoTablero.asistencia), child: const Text('Ver asistencia')),
              ],
            ),
            Text(
              conGuia == 0
                  ? 'Ninguna sección tiene maestro guía: asígnalo en Secciones para que pase la lista del día.'
                  : '$conLista de $conGuia secciones pasaron la lista del día',
              style: text.titleMedium,
            ),
            if (conGuia > 0) ...[
              const SizedBox(height: Espacio.s),
              LinearProgressIndicator(
                value: conLista / conGuia,
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ],
            const SizedBox(height: Espacio.m),
            Wrap(
              spacing: Espacio.l,
              runSpacing: Espacio.s,
              children: [
                Text('${hoy['ausentes']} ausentes', style: text.labelLarge?.copyWith(color: (hoy['ausentes'] as int) > 0 ? scheme.error : null)),
                Text('${hoy['tardes']} ${hoy['tardes'] == 1 ? 'llegada tarde' : 'llegadas tarde'}', style: text.labelLarge),
                InkWell(
                  onTap: () => ir(DestinoTablero.excusas),
                  child: Text('${hoy['excusas']} con excusa o permiso', style: text.labelLarge?.copyWith(color: scheme.primary)),
                ),
              ],
            ),
            if (faltas.isNotEmpty) ...[
              const SizedBox(height: Espacio.s),
              for (final f in faltas.take(8))
                Padding(
                  padding: const EdgeInsets.only(top: Espacio.xxs),
                  child: Text('${f['estado'] == 'A' ? 'Ausente' : 'Tarde'} · ${f['nombre']} · ${f['seccion']}', style: text.bodyMedium),
                ),
              if (faltas.length > 8)
                Text('y ${faltas.length - 8} más', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Barras de la asistencia de la lista del día en los últimos días con lista (una sola serie).
class _Tendencia extends StatelessWidget {
  const _Tendencia({required this.dias, required this.ir});

  final List<Map<String, dynamic>> dias;
  final ValueChanged<DestinoTablero> ir;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    const alto = 120.0;
    // La escala empieza en 50 % para que se vean las diferencias; por debajo, la barra queda mínima.
    double altura(num p) => ((p - 50).clamp(0, 50) / 50) * alto;
    final ultimo = dias.isEmpty ? null : dias.last;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Espacio.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('ASISTENCIA DE LA LISTA DEL DÍA', style: text.labelSmall)),
                TextButton(onPressed: () => ir(DestinoTablero.reportes), child: const Text('Reportes')),
              ],
            ),
            if (dias.isEmpty)
              Text('Aún no hay listas del día en el último mes.', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))
            else ...[
              Text('${ultimo!['porcentaje']} % el ${fechaIso(ultimo['fecha'] as String)}', style: text.titleMedium),
              const SizedBox(height: Espacio.m),
              Semantics(
                label: 'Asistencia por día: ${dias.map((d) => '${fechaIso(d['fecha'] as String)} ${d['porcentaje']} %').join(', ')}',
                child: ExcludeSemantics(
                  child: SizedBox(
                    height: alto + 20,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final d in dias)
                          Expanded(
                            child: Tooltip(
                              message: '${fechaIso(d['fecha'] as String)}: ${d['porcentaje']} % '
                                  '(${d['secciones']} ${d['secciones'] == 1 ? 'sección' : 'secciones'})',
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 1),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Container(
                                      height: altura(d['porcentaje'] as num) + 2,
                                      constraints: const BoxConstraints(maxWidth: 28),
                                      decoration: BoxDecoration(
                                        color: scheme.primary,
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text('${DateTime.parse(d['fecha'] as String).day}',
                                        style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Text('Escala de 50 % a 100 %. Toca una barra para ver el día.',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pendientes extends StatelessWidget {
  const _Pendientes({required this.t, required this.ir});

  final Map<String, dynamic> t;
  final ValueChanged<DestinoTablero> ir;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final incidencias = (t['incidenciasRecientes'] as List).cast<Map<String, dynamic>>();
    final inactivos = (t['docentesSinActividad'] as List).cast<Map<String, dynamic>>();

    Widget tarjeta(String titulo, String accion, DestinoTablero destino, List<Widget> hijos) => SizedBox(
          width: 520,
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(Espacio.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(titulo, style: text.labelSmall)),
                      TextButton(onPressed: () => ir(destino), child: Text(accion)),
                    ],
                  ),
                  ...hijos,
                ],
              ),
            ),
          ),
        );

    return Wrap(
      spacing: Espacio.l,
      runSpacing: Espacio.l,
      children: [
        tarjeta('INCIDENCIAS · ${t['incidenciasAbiertas']} ABIERTAS', 'Ver todas', DestinoTablero.incidencias, [
          if (incidencias.isEmpty)
            Text('Sin incidencias este año.', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          for (final i in incidencias)
            Padding(
              padding: const EdgeInsets.only(top: Espacio.xs),
              child: Text.rich(TextSpan(children: [
                TextSpan(
                  text: 'Falta ${gravedades[i['gravedad']]!.toLowerCase()} ',
                  style: TextStyle(color: colorGravedad(context, i['gravedad'] as String), fontWeight: FontWeight.w700),
                ),
                TextSpan(text: '· ${i['alumno']} · ${fechaIso(i['fecha'] as String)}'),
              ])),
            ),
        ]),
        tarjeta('DOCENTES SIN ACTIVIDAD (14 DÍAS)', 'Estadísticas', DestinoTablero.estadisticas, [
          if (inactivos.isEmpty)
            Text('Todos los docentes han respaldado trabajo en las últimas dos semanas.',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          for (final d in inactivos.take(6))
            Padding(
              padding: const EdgeInsets.only(top: Espacio.xs),
              child: Text('${d['nombre']} · ${_hace(d['ultimoTrabajo'] as String?)}', style: text.bodyMedium),
            ),
          if (inactivos.length > 6)
            Text('y ${inactivos.length - 6} más', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ]),
      ],
    );
  }
}
