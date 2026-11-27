import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/informes/compartir.dart';
import '../../../core/providers.dart';
import '../../../theme/tokens.dart';
import '../../../ui/esqueleto.dart';
import '../../../ui/estado_error.dart';
import '../../../ui/estado_vacio.dart';
import 'comun_centro.dart';
import 'reportes_tab.dart';

final estadisticasDocentesProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) =>
    ref.watch(apiClientProvider).get('/centro/estadisticas-docentes', parse: (d) => d as Map<String, dynamic>));

enum _Orden { nombre, aprobacion, actividad }

int? _pct(int parte, int total) => total == 0 ? null : (100 * parte / total).round();

String _hace(String? iso) {
  if (iso == null) return 'nunca';
  final d = DateTime.now().difference(DateTime.parse(iso).toLocal());
  if (d.inMinutes < 60) return 'hace un momento';
  if (d.inHours < 24) return 'hace ${d.inHours} h';
  if (d.inDays == 1) return 'ayer';
  return 'hace ${d.inDays} días';
}

/// Estadísticas de cada docente en el año: carga, cuadros importados, parciales cerrados,
/// listas pasadas, lista del día (si es guía), conducta, incidencias y aprobación.
class EstadisticasDocentesTab extends ConsumerStatefulWidget {
  const EstadisticasDocentesTab({super.key});

  @override
  ConsumerState<EstadisticasDocentesTab> createState() => _EstadisticasDocentesTabState();
}

class _EstadisticasDocentesTabState extends ConsumerState<EstadisticasDocentesTab> {
  var _orden = _Orden.nombre;

  @override
  Widget build(BuildContext context) {
    final datos = ref.watch(estadisticasDocentesProvider);
    return datos.when(
      loading: () => const EsqueletoLista(filas: 5, conTarjeta: true),
      error: (e, _) => EstadoError(error: e, reintentar: () => ref.invalidate(estadisticasDocentesProvider)),
      data: (r) {
        final habiles = r['diasHabiles'] as int;
        final docentes = (r['docentes'] as List).cast<Map<String, dynamic>>().where((d) => d['activo'] == true).toList();
        int? aprobacion(Map<String, dynamic> d) => _pct(d['aprobados'] as int, d['evaluados'] as int);
        switch (_orden) {
          case _Orden.nombre:
            break;
          case _Orden.aprobacion:
            docentes.sort((a, b) => (aprobacion(a) ?? 101).compareTo(aprobacion(b) ?? 101));
          case _Orden.actividad:
            docentes.sort((a, b) => ((a['ultimoTrabajo'] as String?) ?? '').compareTo((b['ultimoTrabajo'] as String?) ?? ''));
        }
        return RefreshIndicator(
          onRefresh: () => ref.refresh(estadisticasDocentesProvider.future),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.xxxl),
                children: [
                  EncabezadoPestana(
                    titulo: 'Estadísticas de docentes${r['anio'] == null ? '' : ' ${r['anio']}'}',
                    ayuda: 'Con lo que cada docente respaldó en ProfeApp. La aprobación cuenta la final de cada alumno, '
                        'o el promedio de los parciales cerrados si aún no hay final.',
                    acciones: [
                      SegmentedButton<_Orden>(
                        segments: const [
                          ButtonSegment(value: _Orden.nombre, label: Text('Nombre')),
                          ButtonSegment(value: _Orden.aprobacion, label: Text('Aprobación')),
                          ButtonSegment(value: _Orden.actividad, label: Text('Sin actividad')),
                        ],
                        selected: {_orden},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) => setState(() => _orden = s.first),
                      ),
                      TextButton.icon(
                        onPressed: docentes.isEmpty ? null : () => _exportar(context, docentes, habiles),
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('CSV'),
                      ),
                    ],
                  ),
                  if (docentes.isEmpty)
                    const EstadoVacio(
                      icono: Icons.groups_outlined,
                      titulo: 'Sin docentes activos',
                      mensaje: 'Agrega docentes en la pestaña Docentes y asígnales carga en Secciones.',
                    ),
                  for (final d in docentes) _TarjetaDocente(d: d, habiles: habiles),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _exportar(BuildContext context, List<Map<String, dynamic>> docentes, int habiles) => compartirArchivo(
        context,
        csvBytes([
          [
            'Docente', 'Secciones', 'Asignaturas asignadas', 'Alumnos', 'Cuadros en la app', 'Parciales cerrados',
            'Actividades', 'Listas de clase (30 días)', 'Días con lista del día', 'Días hábiles', 'Conductas puestas',
            'Incidencias', 'Evaluados', 'Aprobados', 'Aprobación %', 'Promedio', 'Último acceso', 'Último trabajo',
          ],
          for (final d in docentes)
            [
              d['nombre'], d['secciones'], d['asignaturasCarga'], d['alumnos'], d['cuadrosEnApp'], d['parcialesCerrados'],
              d['actividades'], d['listasRecientes'], d['diasListaDelDia'] ?? '', d['seccionesGuia'] == 0 ? '' : habiles,
              d['conductasPuestas'], d['incidencias'], d['evaluados'], d['aprobados'],
              _pct(d['aprobados'] as int, d['evaluados'] as int) ?? '', d['promedio'] ?? '',
              d['ultimoAcceso'] == null ? '' : fechaIso(aIso(DateTime.parse(d['ultimoAcceso'] as String).toLocal())),
              d['ultimoTrabajo'] == null ? '' : fechaIso(aIso(DateTime.parse(d['ultimoTrabajo'] as String).toLocal())),
            ],
        ]),
        'Estadisticas de docentes.csv',
        'text/csv',
      );
}

class _TarjetaDocente extends StatelessWidget {
  const _TarjetaDocente({required this.d, required this.habiles});

  final Map<String, dynamic> d;
  final int habiles;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final carga = d['asignaturasCarga'] as int;
    final cuadros = d['cuadrosEnApp'] as int;
    final evaluados = d['evaluados'] as int;
    final aprobacion = _pct(d['aprobados'] as int, evaluados);
    final guias = d['seccionesGuia'] as int;
    // Días posibles: los hábiles por cada sección que guía.
    final listaDelDia = guias == 0 ? null : _pct(d['diasListaDelDia'] as int, habiles * guias);
    final sinTrabajo = d['ultimoTrabajo'] == null ||
        DateTime.now().difference(DateTime.parse(d['ultimoTrabajo'] as String)).inDays > 14;

    Widget dato(String etiqueta, String valor, {bool alerta = false}) => SizedBox(
          width: 150,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(etiqueta.toUpperCase(), style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
              Text(valor, style: text.titleMedium?.copyWith(color: alerta ? scheme.error : null)),
            ],
          ),
        );

    return Card(
      margin: const EdgeInsets.only(bottom: Espacio.m),
      child: Padding(
        padding: const EdgeInsets.all(Espacio.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${d['nombre']}', style: text.titleMedium),
            Text(
              'Último trabajo respaldado: ${_hace(d['ultimoTrabajo'] as String?)} · último acceso: ${_hace(d['ultimoAcceso'] as String?)}',
              style: text.bodySmall?.copyWith(color: sinTrabajo ? scheme.error : scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Espacio.m),
            Wrap(
              spacing: Espacio.l,
              runSpacing: Espacio.m,
              children: [
                dato('Carga', '$carga asig. · ${d['secciones']} secc.'),
                dato('Alumnos', '${d['alumnos']}'),
                dato('Cuadros en la app', carga == 0 ? '$cuadros' : '$cuadros de $carga', alerta: cuadros < carga),
                dato('Parciales cerrados', '${d['parcialesCerrados']}'),
                dato('Actividades', '${d['actividades']}'),
                dato('Listas (30 días)', '${d['listasRecientes']}', alerta: carga > 0 && d['listasRecientes'] == 0),
                if (guias > 0)
                  dato('Lista del día', listaDelDia == null ? '—' : '$listaDelDia %', alerta: (listaDelDia ?? 100) < 80),
                if (guias > 0) dato('Conducta', '${d['conductasPuestas']} notas'),
                dato('Incidencias', '${d['incidencias']}'),
                dato('Promedio', d['promedio'] == null ? '—' : '${d['promedio']}'),
              ],
            ),
            const SizedBox(height: Espacio.m),
            Wrap(
              spacing: Espacio.m,
              runSpacing: Espacio.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Aprobación', style: text.labelLarge),
                SizedBox(
                  width: 220,
                  child: LinearProgressIndicator(
                    value: aprobacion == null ? 0 : aprobacion / 100,
                    minHeight: 8,
                    color: (aprobacion ?? 100) < 70 ? scheme.error : scheme.primary,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
                Text(aprobacion == null ? 'sin notas cerradas' : '$aprobacion % de $evaluados', style: text.labelLarge),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
