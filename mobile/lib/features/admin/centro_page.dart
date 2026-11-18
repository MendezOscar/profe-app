import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/cobro.dart';
import '../../core/providers.dart';
import '../../ui/estado_vacio.dart';
import '../../ui/shell.dart';
import 'admin_comun.dart';
import 'centro/comun_centro.dart';
import 'centro/convivencia_tab.dart';
import 'centro/estadisticas_docentes_tab.dart';
import 'centro/estructura_tabs.dart';
import 'centro/familias_centro.dart';
import 'centro/horario_tab.dart';
import 'centro/matricula.dart';
import 'centro/personal_tab.dart';
import 'centro/reportes_tab.dart';
import 'centro/secciones_tab.dart';
import '../../theme/tokens.dart';
import '../../ui/esqueleto.dart';
import '../../ui/estado_error.dart';

final centroProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
    (ref) => ref.watch(apiClientProvider).get('/centro', parse: (d) => d as Map<String, dynamic>));

/// Panel del centro: licencia y avance de los docentes, y la organización académica (año
/// lectivo, grados, secciones, aulas y personal). No ve ni edita notas: sólo cuántas
/// asignaturas, actividades y parciales cerrados lleva cada docente.
class CentroPage extends ConsumerStatefulWidget {
  const CentroPage({super.key});

  @override
  ConsumerState<CentroPage> createState() => _CentroPageState();
}

class _CentroPageState extends ConsumerState<CentroPage> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 14, vsync: this)..addListener(() => setState(() {}));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final centro = ref.watch(centroProvider);
    final nombre = centro.valueOrNull?['institucion']?['nombre'] as String?;
    // Orientación sólo consulta.
    final puedeEditar = centro.valueOrNull?['puedeEditar'] != false;

    return Scaffold(
      appBar: AppBar(
        title: Text(nombre ?? 'Mi centro'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () {
              ref.invalidate(centroProvider);
              ref.invalidate(estructuraProvider);
              ref.invalidate(personalProvider);
              ref.invalidate(comunicadosCentroProvider);
              ref.invalidate(reportesProvider);
              ref.invalidate(excusasCentroProvider);
              ref.invalidate(incidenciasCentroProvider);
              ref.invalidate(estadisticasDocentesProvider);
            },
            icon: const Icon(Icons.refresh),
          ),
          const MenuCuentaAdmin(),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Docentes'),
            Tab(text: 'Año lectivo'),
            Tab(text: 'Grados'),
            Tab(text: 'Secciones'),
            Tab(text: 'Horario'),
            Tab(text: 'Asistencia'),
            Tab(text: 'Excusas'),
            Tab(text: 'Incidencias'),
            Tab(text: 'Alumnos'),
            Tab(text: 'Comunicados'),
            Tab(text: 'Reportes'),
            Tab(text: 'Estadísticas docentes'),
            Tab(text: 'Aulas'),
            Tab(text: 'Personal'),
          ],
        ),
      ),
      floatingActionButton: centro.hasValue && puedeEditar && _tabs.index == 0
          ? FloatingActionButton.extended(
              shape: const RoundedRectangleBorder(),
              onPressed: () => _agregar(context, ref),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Agregar docente'),
            )
          : null,
      body: TabBarView(
        controller: _tabs,
        children: [
          _docentes(centro, puedeEditar),
          const AniosTab(),
          const GradosTab(),
          const SeccionesTab(),
          const HorarioTab(),
          const AsistenciaDiaTab(),
          ExcusasTab(puedeEditar: puedeEditar),
          IncidenciasTab(puedeEditar: puedeEditar),
          const AlumnosTab(),
          ComunicadosTab(puedeEditar: puedeEditar),
          const ReportesTab(),
          const EstadisticasDocentesTab(),
          const AulasTab(),
          PersonalTab(puedeEditar: puedeEditar),
        ],
      ),
    );
  }

  Widget _docentes(AsyncValue<Map<String, dynamic>> centro, bool puedeEditar) => centro.when(
        loading: () => const EsqueletoLista(filas: 6, conTarjeta: true),
        error: (e, _) => EstadoError(error: e, reintentar: () => ref.invalidate(centroProvider)),
        data: (datos) {
          final institucion = datos['institucion'] as Map<String, dynamic>;
          final docentes = (datos['docentes'] as List).cast<Map<String, dynamic>>();
          return RefreshIndicator(
            onRefresh: () => ref.refresh(centroProvider.future),
            child: ContenidoCentrado(
              maxAncho: 1100,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.bajoBotonFlotante),
                children: [
                  _Licencia(institucion: institucion),
                  const SizedBox(height: Espacio.xl),
                  if (docentes.isEmpty)
                    const EstadoVacio(
                      icono: Icons.groups_outlined,
                      titulo: 'Agrega a tus docentes',
                      mensaje: 'Cada docente recibe una contraseña temporal para entrar a la app. '
                          'Aquí verás cómo avanza cada uno con sus parciales.',
                    )
                  else ...[
                    _Avance(docentes: docentes),
                    const SizedBox(height: Espacio.xl),
                    // Primero quien necesita atención: así la dirección lo ve sin buscar.
                    if (docentes.any(atrasado)) ...[
                      Text('NECESITAN ATENCIÓN', style: Theme.of(context).textTheme.labelSmall),
                      const SizedBox(height: Espacio.s),
                      for (final d in docentes.where(atrasado)) _Docente(docente: d, puedeEditar: puedeEditar),
                      const SizedBox(height: Espacio.l),
                    ],
                    if (docentes.any((d) => !atrasado(d))) ...[
                      Text(docentes.any(atrasado) ? 'AL DÍA' : 'DOCENTES', style: Theme.of(context).textTheme.labelSmall),
                      const SizedBox(height: Espacio.s),
                      for (final d in docentes.where((d) => !atrasado(d))) _Docente(docente: d, puedeEditar: puedeEditar),
                    ],
                  ],
                ],
              ),
            ),
          );
        },
      );

  Future<void> _agregar(BuildContext context, WidgetRef ref) async {
    final cuenta = await pedirNombreYCorreo(context, ref, titulo: 'Agregar docente', ruta: '/centro/docentes');
    if (cuenta == null || !context.mounted) return;
    ref.invalidate(centroProvider);
    ref.invalidate(estructuraProvider);
    await mostrarCuentaCreada(context, cuenta, titulo: 'Docente agregado');
  }
}

/// Días sin trabajo que vuelven "atrasado" a un docente: dos semanas sin respaldar nada.
const _diasAtraso = 14;

/// Días desde lo último que respaldó (nota, lista, actividad); null si nunca trabajó.
int? diasSinTrabajo(Map<String, dynamic> docente) => switch (docente['ultimoTrabajo']) {
      final String t => DateTime.now().difference(DateTime.parse(t)).inDays,
      _ => null,
    };

/// Activo y sin trabajo en dos semanas, o sin haber empezado.
bool atrasado(Map<String, dynamic> docente) {
  if (docente['activo'] != true) return false;
  final dias = diasSinTrabajo(docente);
  return dias == null || dias >= _diasAtraso;
}

/// Resumen para la dirección: cuántos van al día, cuántos cerraron algún parcial y cuántos
/// llevan dos semanas sin trabajar en la app.
class _Avance extends StatelessWidget {
  const _Avance({required this.docentes});

  final List<Map<String, dynamic>> docentes;

  @override
  Widget build(BuildContext context) {
    final activos = docentes.where((d) => d['activo'] == true).toList();
    final atrasados = activos.where(atrasado).length;
    final conCierre = activos.where((d) => (d['parcialesCerrados'] as int) > 0).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Espacio.l),
        child: Wrap(
          spacing: 32,
          runSpacing: 16,
          children: [
            _Dato(etiqueta: 'Al día', valor: '${activos.length - atrasados} de ${activos.length}'),
            _Dato(etiqueta: 'Con parcial cerrado', valor: '$conCierre de ${activos.length}'),
            _Dato(etiqueta: 'Sin trabajo en 2 semanas', valor: '$atrasados', alerta: atrasados > 0),
          ],
        ),
      ),
    );
  }
}

class _Licencia extends StatelessWidget {
  const _Licencia({required this.institucion});

  final Map<String, dynamic> institucion;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final usados = institucion['docentes'] as int;
    final cupo = institucion['maxDocentes'] as int;
    final cobro = Cobro.fromJson(institucion['cobro'] as Map<String, dynamic>);
    final lleno = usados >= cupo;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Espacio.l),
        child: Wrap(
          spacing: 32,
          runSpacing: 16,
          children: [
            _Dato(etiqueta: 'Plan', valor: planesCentro[institucion['plan']] ?? '${institucion['plan']}'),
            _Dato(etiqueta: 'Docentes', valor: '$usados de $cupo', alerta: lleno),
            _Dato(
              etiqueta: 'Pagado hasta',
              valor: cobro.pagadoHasta == null ? 'Sin vencimiento' : fechaCorta(cobro.pagadoHasta!.toIso8601String()),
              alerta: cobro.pideAtencion,
            ),
            if (cobro.pideAtencion)
              SizedBox(
                width: 320,
                child: Text(
                  [cobro.mensaje, if (kIsWeb && cobro.comoPagar != null) 'Cómo pagar: ${cobro.comoPagar}'].join('\n'),
                  style: text.bodySmall?.copyWith(color: scheme.error),
                ),
              ),
            if (lleno)
              SizedBox(
                width: 320,
                child: Text('El cupo está lleno. Desactiva a un docente o escríbenos para ampliar el plan.',
                    style: text.bodySmall?.copyWith(color: scheme.error)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.etiqueta, required this.valor, this.alerta = false});

  final String etiqueta;
  final String valor;
  final bool alerta;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(etiqueta.toUpperCase(), style: text.labelSmall),
        Text(valor,
            style: text.titleLarge?.copyWith(color: alerta ? Theme.of(context).colorScheme.error : null)),
      ],
    );
  }
}

class _Docente extends ConsumerWidget {
  const _Docente({required this.docente, required this.puedeEditar});

  final Map<String, dynamic> docente;
  final bool puedeEditar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final activo = docente['activo'] as bool;
    final id = docente['id'] as String;

    Future<void> accion(String opcion) async {
      final api = ref.read(apiClientProvider);
      final messenger = ScaffoldMessenger.of(context);
      try {
        if (opcion == 'clave') {
          final cuenta = await api.post('/centro/docentes/$id/restablecer-clave', parse: (d) => d as Map<String, dynamic>);
          if (context.mounted) await mostrarCuentaCreada(context, cuenta, titulo: 'Contraseña restablecida');
        } else {
          await api.post<void>('/centro/docentes/$id/${activo ? 'desactivar' : 'activar'}');
          messenger.showSnackBar(SnackBar(content: Text(activo ? 'Docente desactivado.' : 'Docente activado.')));
        }
        ref.invalidate(centroProvider);
      } on ApiException catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.isNetworkError ? 'Necesitas internet.' : e.message)));
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: Espacio.s),
      child: Card(
        color: activo ? null : scheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.m, Espacio.xs, Espacio.m),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text('${docente['nombre']}', style: text.titleMedium)),
                        if (!activo) ...[
                          const SizedBox(width: Espacio.s),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: Espacio.s, vertical: Espacio.xxs),
                            color: scheme.errorContainer,
                            child: Text('Inactivo', style: text.labelSmall?.copyWith(color: scheme.onErrorContainer)),
                          ),
                        ],
                      ],
                    ),
                    Text('${docente['email']} · último acceso: ${fechaCorta(docente['ultimoAcceso'] as String?)}',
                        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    Text(
                      switch (diasSinTrabajo(docente)) {
                        null => 'Todavía no ha trabajado en la app',
                        0 => 'Trabajó hoy',
                        1 => 'Trabajó ayer',
                        final d => 'Último trabajo hace $d días',
                      },
                      style: text.bodySmall?.copyWith(
                        color: atrasado(docente) ? scheme.error : scheme.onSurfaceVariant,
                        fontWeight: atrasado(docente) ? FontWeight.w700 : null,
                      ),
                    ),
                    const SizedBox(height: Espacio.s),
                    Wrap(
                      spacing: 16,
                      children: [
                        Text(_cuantos(docente['asignaturas'] as int, 'asignatura', 'asignaturas'), style: text.labelLarge),
                        Text(_cuantos(docente['actividades'] as int, 'actividad', 'actividades'), style: text.labelLarge),
                        Text(_cuantos(docente['parcialesCerrados'] as int, 'parcial cerrado', 'parciales cerrados'),
                            style: text.labelLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ],
                ),
              ),
              if (puedeEditar)
                PopupMenuButton<String>(
                  tooltip: 'Opciones',
                  onSelected: accion,
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'clave', child: Text('Restablecer contraseña')),
                    PopupMenuItem(value: 'estado', child: Text(activo ? 'Desactivar' : 'Activar')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _cuantos(int n, String uno, String varios) => '$n ${n == 1 ? uno : varios}';
