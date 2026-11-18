import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/enlaces.dart';
import '../../core/planes/calculo_parcial.dart';
import '../../core/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/esqueleto.dart';
import '../../ui/estado_error.dart';
import '../../ui/estado_vacio.dart';
import '../auth/cambiar_clave_dialog.dart';
import '../cuenta/eliminar_cuenta_dialog.dart';

final hijosProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) =>
    ref.watch(apiClientProvider).get('/padres/hijos', parse: (d) => (d as List).cast<Map<String, dynamic>>()));

final resumenHijoProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) =>
    ref.watch(apiClientProvider).get('/padres/hijos/$id', parse: (d) => d as Map<String, dynamic>));

final comunicadosFamiliaProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) => ref
    .watch(apiClientProvider)
    .get('/padres/comunicados', parse: (d) => (d as List).cast<Map<String, dynamic>>()));

String _fecha(String? iso) {
  if (iso == null) return 'Sin fecha';
  final d = DateTime.parse(iso).toLocal();
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String _pts(Object? valor) => formatoPuntos((valor as num).toDouble());

/// Casa del padre o la madre: sus hijos y los comunicados del centro.
class FamiliaPage extends ConsumerStatefulWidget {
  const FamiliaPage({super.key});

  @override
  ConsumerState<FamiliaPage> createState() => _FamiliaPageState();
}

class _FamiliaPageState extends ConsumerState<FamiliaPage> {
  var _pestana = 0;

  @override
  Widget build(BuildContext context) {
    final sinLeer = ref.watch(comunicadosFamiliaProvider).valueOrNull?.where((c) => c['leido'] != true).length ?? 0;
    final nombre = ref.watch(sessionProvider.select((s) => s?.fullName.split(' ').first)) ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text('Hola, $nombre'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () {
              ref.invalidate(hijosProvider);
              ref.invalidate(comunicadosFamiliaProvider);
            },
            icon: const Icon(Icons.refresh),
          ),
          _MenuFamilia(alAgregar: () => ref.invalidate(hijosProvider)),
        ],
      ),
      body: IndexedStack(
        index: _pestana,
        children: const [_Hijos(), _Comunicados()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _pestana,
        onDestinationSelected: (i) => setState(() => _pestana = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.family_restroom_outlined), label: 'Mis hijos'),
          NavigationDestination(
            icon: Badge(isLabelVisible: sinLeer > 0, label: Text('$sinLeer'), child: const Icon(Icons.campaign_outlined)),
            label: 'Comunicados',
          ),
        ],
      ),
    );
  }
}

class _MenuFamilia extends ConsumerWidget {
  const _MenuFamilia({required this.alAgregar});

  final VoidCallback alAgregar;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
        tooltip: 'Cuenta',
        icon: const Icon(Icons.account_circle_outlined),
        onSelected: (o) async {
          switch (o) {
            case 'codigo':
              if (await agregarHijo(context, ref)) alAgregar();
            case 'clave':
              await mostrarCambiarClave(context);
            case 'ayuda':
              await Enlaces.abrir(Enlaces.soporte);
            case 'privacidad':
              await Enlaces.abrir(Enlaces.privacidad);
            case 'eliminar':
              await mostrarEliminarCuenta(context);
            case 'salir':
              await ref.read(authControllerProvider.notifier).logout();
              if (kIsWeb) await Enlaces.volverAlSitio();
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'codigo', child: Text('Agregar otro hijo (código)')),
          PopupMenuItem(value: 'clave', child: Text('Cambiar contraseña')),
          PopupMenuItem(value: 'ayuda', child: Text('Ayuda')),
          PopupMenuItem(value: 'privacidad', child: Text('Privacidad')),
          PopupMenuItem(value: 'salir', child: Text('Cerrar sesión')),
          PopupMenuItem(value: 'eliminar', child: Text('Eliminar mi cuenta')),
        ],
      );
}

/// Pide un código de familia y vincula al hijo. Devuelve si se agregó.
Future<bool> agregarHijo(BuildContext context, WidgetRef ref) async {
  final codigo = TextEditingController();
  final agregado = await showDialog<bool>(
    context: context,
    builder: (dialogo) {
      String? error;
      var enviando = false;
      return StatefulBuilder(
        builder: (dialogo, setState) => AlertDialog(
          shape: const RoundedRectangleBorder(),
          title: const Text('Agregar otro hijo'),
          content: SizedBox(
            width: 400,
            child: TextField(
              controller: codigo,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: 'Código del centro', hintText: 'ABCD-2345', errorText: error),
            ),
          ),
          actions: [
            TextButton(onPressed: enviando ? null : () => Navigator.pop(dialogo, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: enviando
                  ? null
                  : () async {
                      setState(() => enviando = true);
                      try {
                        await ref.read(apiClientProvider).post<void>('/padres/vincular', body: {'codigo': codigo.text});
                        if (dialogo.mounted) Navigator.pop(dialogo, true);
                      } on ApiException catch (e) {
                        setState(() {
                          enviando = false;
                          error = e.isNetworkError ? 'Necesitas internet.' : e.message;
                        });
                      }
                    },
              child: const Text('Agregar'),
            ),
          ],
        ),
      );
    },
  );
  return agregado == true;
}

class _Hijos extends ConsumerWidget {
  const _Hijos();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hijos = ref.watch(hijosProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return hijos.when(
      loading: () => const EsqueletoLista(filas: 2, conTarjeta: true),
      error: (e, _) => EstadoError(error: e, reintentar: () => ref.invalidate(hijosProvider)),
      data: (lista) => lista.isEmpty
          ? EstadoVacio(
              icono: Icons.family_restroom_outlined,
              titulo: 'Sin hijos vinculados',
              mensaje: 'Pide al centro el código de familia de tu hijo o hija y agrégalo aquí.',
              accion: FilledButton(
                onPressed: () async {
                  if (await agregarHijo(context, ref)) ref.invalidate(hijosProvider);
                },
                child: const Text('Agregar con código'),
              ),
            )
          : RefreshIndicator(
              onRefresh: () => ref.refresh(hijosProvider.future),
              child: ListView(
                padding: const EdgeInsets.all(Espacio.l),
                children: [
                  for (final h in lista)
                    Card(
                      margin: const EdgeInsets.only(bottom: Espacio.s),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: Espacio.l, vertical: Espacio.s),
                        leading: CircleAvatar(child: Text('${h['nombre']}'.characters.first)),
                        title: Text('${h['nombre']}', style: text.titleMedium),
                        subtitle: Text([h['seccion'] ?? 'Sin matrícula este año', h['centro']].join(' · '),
                            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => HijoPage(alumnoId: h['alumnoId'] as String, nombre: h['nombre'] as String),
                        )),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _Comunicados extends ConsumerWidget {
  const _Comunicados();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comunicados = ref.watch(comunicadosFamiliaProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return comunicados.when(
      loading: () => const EsqueletoLista(filas: 3, conTarjeta: true),
      error: (e, _) => EstadoError(error: e, reintentar: () => ref.invalidate(comunicadosFamiliaProvider)),
      data: (lista) => lista.isEmpty
          ? const EstadoVacio(
              icono: Icons.campaign_outlined,
              titulo: 'Sin comunicados',
              mensaje: 'Aquí verás los avisos que el centro envíe a las familias.',
            )
          : RefreshIndicator(
              onRefresh: () => ref.refresh(comunicadosFamiliaProvider.future),
              child: ListView(
                padding: const EdgeInsets.all(Espacio.l),
                children: [
                  for (final c in lista)
                    Card(
                      margin: const EdgeInsets.only(bottom: Espacio.s),
                      child: ExpansionTile(
                        shape: const Border(),
                        collapsedShape: const Border(),
                        leading: Icon(c['leido'] == true ? Icons.drafts_outlined : Icons.mark_email_unread_outlined,
                            color: c['leido'] == true ? scheme.onSurfaceVariant : scheme.primary),
                        title: Text('${c['titulo']}',
                            style: text.titleSmall?.copyWith(fontWeight: c['leido'] == true ? null : FontWeight.w800)),
                        subtitle: Text('${c['centro']} · ${_fecha(c['publicadoEn'] as String)}', style: text.bodySmall),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        childrenPadding: const EdgeInsets.fromLTRB(Espacio.l, 0, Espacio.l, Espacio.l),
                        onExpansionChanged: (abierto) async {
                          if (!abierto || c['leido'] == true) return;
                          try {
                            await ref.read(apiClientProvider).post<void>('/padres/comunicados/${c['id']}/leido');
                            ref.invalidate(comunicadosFamiliaProvider);
                          } on ApiException {
                            // Sin internet: se marcará la próxima vez.
                          }
                        },
                        children: [SelectableText('${c['cuerpo']}')],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

const _dias = ['', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'];

String _hora(String t) {
  final p = t.split(':');
  return '${int.parse(p[0])}:${p[1]}';
}

class _Horario extends StatelessWidget {
  const _Horario(this.r);

  final Map<String, dynamic> r;

  @override
  Widget build(BuildContext context) {
    final clases = ((r['horario'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final text = Theme.of(context).textTheme;
    if (clases.isEmpty) {
      return const EstadoVacio(
        icono: Icons.schedule,
        titulo: 'Sin horario',
        mensaje: 'Aparece cuando el centro arma el horario de la sección.',
      );
    }
    final hoy = DateTime.now().weekday;
    return ListView(
      padding: const EdgeInsets.all(Espacio.l),
      children: [
        for (final d in {for (final c in clases) c['dia'] as int}) ...[
          const SizedBox(height: Espacio.s),
          Text('${_dias[d].toUpperCase()}${d == hoy ? ' · HOY' : ''}', style: text.labelSmall),
          for (final c in clases.where((c) => c['dia'] == d))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: SizedBox(
                width: 88,
                child: Text('${_hora(c['inicio'] as String)}–${_hora(c['fin'] as String)}', style: text.labelLarge),
              ),
              title: Text('${c['asignatura']}'),
              subtitle: c['aula'] == null ? null : Text('${c['aula']}'),
            ),
        ],
      ],
    );
  }
}

/// Lo de un hijo: notas por asignatura y parcial, asistencia y próximas entregas.
class HijoPage extends ConsumerWidget {
  const HijoPage({super.key, required this.alumnoId, required this.nombre});

  final String alumnoId;
  final String nombre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumen = ref.watch(resumenHijoProvider(alumnoId));
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(nombre),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [Tab(text: 'Notas'), Tab(text: 'Asistencia'), Tab(text: 'Próximas'), Tab(text: 'Horario')],
          ),
        ),
        body: resumen.when(
          loading: () => const EsqueletoLista(filas: 4, conTarjeta: true),
          error: (e, _) => EstadoError(error: e, reintentar: () => ref.invalidate(resumenHijoProvider(alumnoId))),
          data: (r) => TabBarView(children: [_Notas(r), _Asistencia(r), _Proximas(r), _Horario(r)]),
        ),
      ),
    );
  }
}

class _Notas extends StatelessWidget {
  const _Notas(this.r);

  final Map<String, dynamic> r;

  @override
  Widget build(BuildContext context) {
    final asignaturas = (r['asignaturas'] as List).cast<Map<String, dynamic>>();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (asignaturas.isEmpty) {
      return const EstadoVacio(
        icono: Icons.menu_book_outlined,
        titulo: 'Todavía sin notas',
        mensaje: 'Aparecen cuando los docentes del centro empiezan a calificar en ProfeApp.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(Espacio.l),
      children: [
        for (final a in asignaturas)
          Card(
            margin: const EdgeInsets.only(bottom: Espacio.s),
            child: ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text('${a['asignatura']}', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              subtitle: Text('${a['docente']}', style: text.bodySmall),
              childrenPadding: const EdgeInsets.fromLTRB(Espacio.l, 0, Espacio.l, Espacio.m),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final p in (a['parciales'] as List).cast<Map<String, dynamic>>()) ...[
                  const SizedBox(height: Espacio.s),
                  Row(
                    children: [
                      Expanded(child: Text('${p['parcial']}${p['cerrado'] == true ? ' · cerrado' : ''}', style: text.labelLarge)),
                      Text(
                        (p['calificados'] as num) == 0
                            ? 'Sin calificar'
                            : '${_pts(p['obtenidos'])} de ${_pts(p['calificados'])} pts',
                        style: text.labelLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  for (final act in (p['actividades'] as List).cast<Map<String, dynamic>>())
                    Padding(
                      padding: const EdgeInsets.only(top: Espacio.xs),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${act['titulo']}${act['fecha'] == null ? '' : ' · ${_fecha(act['fecha'] as String)}'}',
                              style: text.bodyMedium,
                            ),
                          ),
                          Text(
                            act['nota'] == null
                                ? '— / ${_pts(act['puntos'])}'
                                : '${_pts(act['nota'])} / ${_pts(act['puntos'])}',
                            style: text.bodyMedium?.copyWith(color: act['nota'] == null ? scheme.onSurfaceVariant : null),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _Asistencia extends StatelessWidget {
  const _Asistencia(this.r);

  final Map<String, dynamic> r;

  @override
  Widget build(BuildContext context) {
    final diaria = r['asistenciaDiaria'] as Map<String, dynamic>?;
    return ListView(
      padding: const EdgeInsets.all(Espacio.l),
      children: [
        if (diaria != null && (diaria['sesiones'] as int) > 0) ...[
          _BloqueAsistencia(
            titulo: 'LISTA DEL DÍA (MAESTRO GUÍA)',
            a: diaria,
            etiquetaTotal: 'Días con lista',
          ),
          const SizedBox(height: Espacio.xl),
        ],
        _BloqueAsistencia(titulo: 'EN CADA CLASE', a: r['asistencia'] as Map<String, dynamic>, etiquetaTotal: 'Clases registradas'),
      ],
    );
  }
}

class _BloqueAsistencia extends StatelessWidget {
  const _BloqueAsistencia({required this.titulo, required this.a, required this.etiquetaTotal});

  final String titulo;
  final Map<String, dynamic> a;
  final String etiquetaTotal;

  @override
  Widget build(BuildContext context) {
    final recientes = (a['recientes'] as List).cast<Map<String, dynamic>>();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    const etiquetas = {'ausente': 'Ausente', 'tarde': 'Tarde', 'justificada': 'Ausencia justificada'};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(titulo, style: text.labelSmall),
        const SizedBox(height: Espacio.s),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(Espacio.l),
            child: Wrap(
              spacing: 32,
              runSpacing: 16,
              children: [
                for (final (etiqueta, valor, alerta) in [
                  (etiquetaTotal, a['sesiones'], false),
                  ('Ausencias', a['ausencias'], (a['ausencias'] as int) > 0),
                  ('Llegadas tarde', a['tardes'], false),
                  ('Justificadas', a['justificadas'], false),
                ])
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(etiqueta.toUpperCase(), style: text.labelSmall),
                      Text('$valor', style: text.titleLarge?.copyWith(color: alerta ? scheme.error : null)),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Espacio.l),
        Text('ÚLTIMAS FALTAS', style: text.labelSmall),
        const SizedBox(height: Espacio.s),
        if (recientes.isEmpty)
          Text('Sin faltas registradas.', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        for (final f in recientes)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(f['estado'] == 'tarde' ? Icons.schedule : Icons.event_busy_outlined,
                color: f['estado'] == 'ausente' ? scheme.error : scheme.onSurfaceVariant),
            title: Text('${etiquetas[f['estado']]} · ${f['asignatura']}'),
            subtitle: Text(_fecha(f['fecha'] as String)),
          ),
      ],
    );
  }
}

class _Proximas extends StatelessWidget {
  const _Proximas(this.r);

  final Map<String, dynamic> r;

  @override
  Widget build(BuildContext context) {
    final proximas = (r['proximas'] as List).cast<Map<String, dynamic>>();
    if (proximas.isEmpty) {
      return const EstadoVacio(
        icono: Icons.event_available_outlined,
        titulo: 'Nada pendiente',
        mensaje: 'Aquí aparecen las tareas y exámenes de las próximas dos semanas.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(Espacio.l),
      children: [
        for (final p in proximas)
          Card(
            margin: const EdgeInsets.only(bottom: Espacio.s),
            child: ListTile(
              leading: const Icon(Icons.assignment_outlined),
              title: Text('${p['titulo']}'),
              subtitle: Text('${p['asignatura']} · ${_pts(p['puntos'])} pts'),
              trailing: Text(_fecha(p['fecha'] as String), style: Theme.of(context).textTheme.labelLarge),
            ),
          ),
      ],
    );
  }
}
