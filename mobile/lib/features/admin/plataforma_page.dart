import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/cobro.dart';
import '../../core/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/esqueleto.dart';
import '../../ui/estado_error.dart';
import '../../ui/estado_vacio.dart';
import '../../ui/shell.dart';
import 'admin_comun.dart';

final institucionesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) => ref
    .watch(apiClientProvider)
    .get('/plataforma/instituciones', parse: (d) => (d as List).cast<Map<String, dynamic>>()));

/// Docentes del plan personal, de a una página (pueden ser miles): se busca en el servidor.
class DocentesPlataforma {
  const DocentesPlataforma({this.lista = const [], this.total = 0, this.mas = false, this.pagina = 0, this.cargandoMas = false});

  final List<Map<String, dynamic>> lista;
  final int total;
  final bool mas;
  final int pagina;
  final bool cargandoMas;
}

final buscarDocenteProvider = StateProvider.autoDispose<String>((ref) => '');

class DocentesPlataformaNotifier extends AutoDisposeAsyncNotifier<DocentesPlataforma> {
  @override
  Future<DocentesPlataforma> build() => _pagina(0, const []);

  Future<DocentesPlataforma> _pagina(int pagina, List<Map<String, dynamic>> antes) async {
    final r = await ref.read(apiClientProvider).get('/plataforma/docentes',
        query: {'buscar': ref.watch(buscarDocenteProvider), 'pagina': pagina}, parse: (d) => d as Map<String, dynamic>);
    return DocentesPlataforma(
      lista: [...antes, ...(r['docentes'] as List).cast<Map<String, dynamic>>()],
      total: r['total'] as int,
      mas: r['mas'] as bool,
      pagina: pagina,
    );
  }

  Future<void> cargarMas() async {
    final actual = state.valueOrNull;
    if (actual == null || !actual.mas || actual.cargandoMas) return;
    state = AsyncData(DocentesPlataforma(
        lista: actual.lista, total: actual.total, mas: actual.mas, pagina: actual.pagina, cargandoMas: true));
    state = await AsyncValue.guard(() => _pagina(actual.pagina + 1, actual.lista));
  }
}

final docentesPlataformaProvider =
    AsyncNotifierProvider.autoDispose<DocentesPlataformaNotifier, DocentesPlataforma>(DocentesPlataformaNotifier.new);

/// El historial de pagos de una cuenta. Se pide sólo al abrir su hoja de pago.
final pagosProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, ruta) =>
    ref.watch(apiClientProvider).get('/plataforma/$ruta/pagos', parse: (d) => (d as List).cast<Map<String, dynamic>>()));

/// A quién se le cobra: un docente del plan personal o un centro. [ruta] es la de la API.
class _Cuenta {
  _Cuenta.docente(Map<String, dynamic> d)
      : ruta = 'docentes/${d['id']}',
        nombre = d['nombre'] as String,
        activa = d['activo'] as bool,
        esCentro = false,
        cobro = Cobro.fromJson(d['cobro'] as Map<String, dynamic>),
        datos = d;

  _Cuenta.centro(Map<String, dynamic> i)
      : ruta = 'instituciones/${i['id']}',
        nombre = i['nombre'] as String,
        activa = i['activa'] as bool,
        esCentro = true,
        cobro = Cobro.fromJson(i['cobro'] as Map<String, dynamic>),
        datos = i;

  final String ruta;
  final String nombre;
  final bool activa;
  final bool esCentro;
  final Cobro cobro;
  final Map<String, dynamic> datos;
}

/// Panel de quien opera ProfeApp: docentes del plan personal y centros con licencia, con
/// su cobro (pagos, plan y vencimiento), contraseñas y suspensión.
class PlataformaPage extends ConsumerWidget {
  const PlataformaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Plataforma'),
          actions: [
            IconButton(
              tooltip: 'Actualizar',
              onPressed: () => ref
                ..invalidate(docentesPlataformaProvider)
                ..invalidate(institucionesProvider),
              icon: const Icon(Icons.refresh),
            ),
            const MenuCuentaAdmin(),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Docentes'), Tab(text: 'Centros')]),
        ),
        body: const TabBarView(children: [_Docentes(), _Centros()]),
      ),
    );
  }
}

class _Docentes extends ConsumerStatefulWidget {
  const _Docentes();

  @override
  ConsumerState<_Docentes> createState() => _DocentesState();
}

class _DocentesState extends ConsumerState<_Docentes> {
  late final _buscar = TextEditingController(text: ref.read(buscarDocenteProvider));

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final docentes = ref.watch(docentesPlataformaProvider);
    final text = Theme.of(context).textTheme;

    return ContenidoCentrado(
      maxAncho: 1100,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.xxxl),
        children: [
          Wrap(
            spacing: Espacio.m,
            runSpacing: Espacio.m,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 360,
                child: TextField(
                  controller: _buscar,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Buscar por nombre o correo'),
                  onSubmitted: (v) => ref.read(buscarDocenteProvider.notifier).state = v.trim(),
                ),
              ),
              FilledButton.icon(
                onPressed: () async {
                  final cuenta = await pedirNombreYCorreo(context, ref,
                      titulo: 'Cuenta del plan docente', ruta: '/plataforma/docentes');
                  if (cuenta == null || !context.mounted) return;
                  ref.invalidate(docentesPlataformaProvider);
                  await mostrarCuentaCreada(context, cuenta);
                },
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Nueva cuenta de docente'),
              ),
            ],
          ),
          const SizedBox(height: Espacio.xl),
          docentes.when(
            loading: () => const SizedBox(height: 320, child: EsqueletoLista(filas: 4, conTarjeta: true)),
            error: (e, _) => SizedBox(
              height: 360,
              child: EstadoError(error: e, reintentar: () => ref.invalidate(docentesPlataformaProvider)),
            ),
            data: (d) => d.lista.isEmpty
                ? EstadoVacio(
                    icono: Icons.person_search_outlined,
                    titulo: ref.watch(buscarDocenteProvider).isEmpty ? 'Sin docentes todavía' : 'Nadie coincide',
                    mensaje: ref.watch(buscarDocenteProvider).isEmpty
                        ? 'Crea una cuenta cuando un docente contrate el plan personal. Recibe una contraseña temporal.'
                        : 'Prueba con otra parte del nombre o del correo.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${d.total} ${d.total == 1 ? 'DOCENTE' : 'DOCENTES'}', style: text.labelSmall),
                      const SizedBox(height: Espacio.s),
                      for (final docente in d.lista) _Fila(cuenta: _Cuenta.docente(docente)),
                      if (d.mas)
                        Center(
                          child: TextButton(
                            onPressed: d.cargandoMas
                                ? null
                                : () => ref.read(docentesPlataformaProvider.notifier).cargarMas(),
                            child: Text(d.cargandoMas ? 'Cargando…' : 'Ver más (${d.total - d.lista.length})'),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Centros extends ConsumerWidget {
  const _Centros();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instituciones = ref.watch(institucionesProvider);
    final text = Theme.of(context).textTheme;

    return ContenidoCentrado(
      maxAncho: 1100,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.xxxl),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () async {
                final creado = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _FormCentro());
                if (creado == null || !context.mounted) return;
                ref.invalidate(institucionesProvider);
                await mostrarCuentaCreada(context, creado['admin'] as Map<String, dynamic>,
                    titulo: 'Centro creado: administrador');
              },
              icon: const Icon(Icons.apartment),
              label: const Text('Nuevo centro'),
            ),
          ),
          const SizedBox(height: Espacio.xl),
          Text('CENTROS', style: text.labelSmall),
          const SizedBox(height: Espacio.s),
          instituciones.when(
            loading: () => const SizedBox(height: 320, child: EsqueletoLista(filas: 4, conTarjeta: true)),
            error: (e, _) => SizedBox(
              height: 360,
              child: EstadoError(error: e, reintentar: () => ref.invalidate(institucionesProvider)),
            ),
            data: (lista) => lista.isEmpty
                ? const EstadoVacio(
                    icono: Icons.apartment,
                    titulo: 'Sin centros todavía',
                    mensaje: 'Crea un centro cuando vendas una licencia institucional. Su administrador '
                        'recibe una contraseña temporal y da de alta a sus docentes.',
                  )
                : Column(children: [for (final i in lista) _Fila(cuenta: _Cuenta.centro(i))]),
          ),
        ],
      ),
    );
  }
}

/// Lo que se cobra y hasta cuándo está pagado, en una línea.
String _lineaPlan(Cobro c, {String? nivel}) {
  final nombre = c.planNombre ?? nivel ?? 'Sin plan';
  if (c.pagadoHasta == null) return '$nombre · sin vencimiento';
  final monto = c.monto > 0 ? '${_lempiras(c.monto)} · ' : '';
  return '$nombre · $monto'
      'pagado hasta ${_fecha(c.pagadoHasta!)}'
      '${c.diasGracia > 0 ? ' (+${c.diasGracia} de gracia)' : ''}';
}

String _fecha(DateTime d) => '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _lempiras(double monto) =>
    'L ${monto == monto.roundToDouble() ? monto.toStringAsFixed(0) : monto.toStringAsFixed(2)}';

double? _leerMonto(String texto) => double.tryParse(texto.replaceAll(',', '').trim());

class _Fila extends ConsumerWidget {
  const _Fila({required this.cuenta});

  final _Cuenta cuenta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final d = cuenta.datos;
    final c = cuenta.cobro;
    final ultimoPago = d['ultimoPago'] as String?;

    final lineas = cuenta.esCentro
        ? [
            d['adminEmail'] as String? ?? 'Sin administrador',
            '${planesCentro[d['plan']] ?? d['plan']} · ${d['docentes']} de ${d['maxDocentes']} docentes',
          ]
        : [
            d['email'] as String,
            () {
              final n = d['asignaturas'] as int;
              final tope = c.topeAsignaturas;
              return tope == null ? '$n ${n == 1 ? 'asignatura' : 'asignaturas'}' : '$n de $tope asignaturas';
            }(),
          ];
    final nivel = cuenta.esCentro ? null : nivelesDocente[c.nivel]?.$1;
    final alta = d['creadoEn'] as String?;
    final ingreso = d['ultimoAcceso'] as String?;

    return Padding(
      padding: const EdgeInsets.only(bottom: Espacio.s),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.m, Espacio.xs, Espacio.m),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: Espacio.s,
                      runSpacing: Espacio.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(cuenta.nombre, style: text.titleMedium),
                        if (!cuenta.activa)
                          _Chip(etiqueta: 'Suspendida', color: scheme.error, icono: Icons.block)
                        else if (c.pideAtencion)
                          _CobroChip(cobro: c),
                      ],
                    ),
                    const SizedBox(height: Espacio.xxs),
                    for (final l in lineas) Text(l, style: text.bodyMedium),
                    Text(
                      '${_lineaPlan(c, nivel: nivel == null ? null : 'Plan $nivel')}'
                      '${ultimoPago == null ? '' : ' · último pago ${fechaCorta(ultimoPago)}'}',
                      style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      [
                        if (alta != null) 'Alta ${fechaCorta(alta)}',
                        if (!cuenta.esCentro) ingreso == null ? 'nunca entró' : 'último ingreso ${fechaCorta(ingreso)}',
                      ].join(' · '),
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              _Menu(cuenta: cuenta),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.etiqueta, required this.color, required this.icono});

  final String etiqueta;
  final Color color;
  final IconData icono;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Espacio.s, vertical: Espacio.xxs),
        decoration: BoxDecoration(border: Border.all(color: color)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 14, color: color),
            const SizedBox(width: Espacio.xs),
            Text(etiqueta, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
          ],
        ),
      );
}

/// En qué anda el cobro. Sólo aparece cuando hay algo que mirar.
class _CobroChip extends StatelessWidget {
  const _CobroChip({required this.cobro});

  final Cobro cobro;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (etiqueta, color, icono) = switch (cobro.estado) {
      EstadoCobro.soloLectura => ('Solo lectura', scheme.error, Icons.lock_outline),
      EstadoCobro.gracia => ('En gracia', scheme.error, Icons.warning_amber_outlined),
      EstadoCobro.porVencer => ('Vence en ${cobro.diasRestantes} d', scheme.tertiary, Icons.schedule),
      EstadoCobro.alDia => ('Al día', scheme.outline, Icons.check),
    };
    return _Chip(etiqueta: etiqueta, color: color, icono: icono);
  }
}

class _Menu extends ConsumerWidget {
  const _Menu({required this.cuenta});

  final _Cuenta cuenta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    PopupMenuItem<String> item(String valor, IconData icono, String titulo) => PopupMenuItem(
          value: valor,
          child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(icono), title: Text(titulo)),
        );
    return PopupMenuButton<String>(
      tooltip: 'Acciones de ${cuenta.nombre}',
      onSelected: (accion) => _hacer(context, ref, accion),
      itemBuilder: (_) => [
        item('pago', Icons.payments_outlined, 'Registrar pago'),
        item('plan', Icons.card_membership_outlined, 'Plan y vencimiento'),
        if (cuenta.esCentro) item('licencia', Icons.groups_outlined, 'Plan y cupo de docentes'),
        item('clave', Icons.key_outlined, cuenta.esCentro ? 'Reponer contraseña del administrador' : 'Reponer contraseña'),
        cuenta.activa
            ? item('suspender', Icons.block, 'Suspender')
            : item('reactivar', Icons.play_circle_outline, 'Reactivar'),
      ],
    );
  }

  void _refrescar(WidgetRef ref) =>
      ref.invalidate(cuenta.esCentro ? institucionesProvider : docentesPlataformaProvider);

  Future<void> _hacer(BuildContext context, WidgetRef ref, String accion) async {
    final api = ref.read(apiClientProvider);
    final mensajero = ScaffoldMessenger.of(context);
    try {
      switch (accion) {
        case 'pago' || 'plan':
          final guardado = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            shape: const RoundedRectangleBorder(),
            builder: (_) => accion == 'pago' ? _HojaPago(cuenta: cuenta) : _HojaPlan(cuenta: cuenta),
          );
          if (guardado == true) _refrescar(ref);
        case 'licencia':
          final ok = await showDialog<bool>(context: context, builder: (_) => _FormCentro(institucion: cuenta.datos));
          if (ok == true) _refrescar(ref);
        case 'clave':
          if (!await _confirmar(context,
              titulo: '¿Reponer la contraseña?',
              mensaje: 'Se genera una contraseña temporal y se cierran sus sesiones abiertas.',
              accion: 'Reponer')) {
            return;
          }
          final cuentaNueva =
              await api.post('/plataforma/${cuenta.ruta}/reponer-clave', parse: (d) => d as Map<String, dynamic>);
          if (context.mounted) await mostrarCuentaCreada(context, cuentaNueva, titulo: 'Contraseña nueva de ${cuenta.nombre}');
        case 'suspender' || 'reactivar':
          final suspender = accion == 'suspender';
          if (suspender &&
              !await _confirmar(context,
                  titulo: '¿Suspender a ${cuenta.nombre}?',
                  mensaje: cuenta.esCentro
                      ? 'Ni la administración ni los docentes del centro podrán entrar, y se cierran sus sesiones. '
                          'Los datos quedan intactos.'
                      : 'No podrá entrar y se cierran sus sesiones. Sus datos quedan intactos.',
                  accion: 'Suspender')) {
            return;
          }
          await api.post<void>('/plataforma/${cuenta.ruta}/${suspender ? 'suspender' : 'reactivar'}');
          _refrescar(ref);
          mensajero.showSnackBar(SnackBar(
              content: Text(suspender ? '${cuenta.nombre} quedó suspendida.' : '${cuenta.nombre} volvió a estar activa.')));
      }
    } on ApiException catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text(e.isNetworkError ? 'Necesitas internet.' : e.message)));
    }
  }

  Future<bool> _confirmar(BuildContext context,
          {required String titulo, required String mensaje, required String accion}) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: const RoundedRectangleBorder(),
          title: Text(titulo),
          content: Text(mensaje),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(accion)),
          ],
        ),
      ) ==
      true;
}

/// Anotar el pago que entró: corre el vencimiento solo. Es el camino de todos los meses;
/// tocar el plan a mano queda para cuando cambian las condiciones.
class _HojaPago extends ConsumerStatefulWidget {
  const _HojaPago({required this.cuenta});

  final _Cuenta cuenta;

  @override
  ConsumerState<_HojaPago> createState() => _HojaPagoState();
}

class _HojaPagoState extends ConsumerState<_HojaPago> {
  late final _monto = TextEditingController(
      text: widget.cuenta.cobro.monto > 0 ? _lempiras(widget.cuenta.cobro.monto).substring(2) : '');
  final _referencia = TextEditingController();
  int _meses = 1;
  DateTime? _elegida;
  var _guardando = false;
  String? _error;

  @override
  void dispose() {
    _monto.dispose();
    _referencia.dispose();
    super.dispose();
  }

  /// Sobre el vencimiento que ya tenía, no sobre hoy: el día de cobro no se corre porque
  /// pagó tarde. El 31 más un mes cae al último día del mes siguiente, igual que en el servidor.
  DateTime get _calculado {
    final desde = widget.cuenta.cobro.pagadoHasta ?? DateTime.now();
    final corrido = desde.month + _meses;
    final anio = desde.year + (corrido - 1) ~/ 12;
    final mes = (corrido - 1) % 12 + 1;
    final ultimo = DateTime(anio, mes + 1, 0).day;
    return DateTime(anio, mes, desde.day > ultimo ? ultimo : desde.day);
  }

  DateTime get _hasta => _elegida ?? _calculado;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final cobro = widget.cuenta.cobro;

    return Padding(
      padding: EdgeInsets.fromLTRB(Espacio.l, 0, Espacio.l, MediaQuery.viewInsetsOf(context).bottom + Espacio.l),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pago de ${widget.cuenta.nombre}', style: text.titleLarge),
            const SizedBox(height: Espacio.xs),
            Text(
              cobro.pagadoHasta == null
                  ? 'Hoy no tiene vencimiento: el período se cuenta desde hoy.'
                  : 'Venía pagado hasta el ${_fecha(cobro.pagadoHasta!)}.',
              style: text.bodySmall,
            ),
            const SizedBox(height: Espacio.l),
            TextField(
              controller: _monto,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: const InputDecoration(labelText: 'Monto recibido', prefixText: 'L '),
            ),
            const SizedBox(height: Espacio.l),
            Text('Períodos pagados', style: text.labelLarge),
            const SizedBox(height: Espacio.s),
            Wrap(
              spacing: Espacio.s,
              runSpacing: Espacio.s,
              children: [
                for (final meses in [1, 3, 6, 10, 12])
                  ChoiceChip(
                    label: Text(meses == 1 ? '1 mes' : (meses == 10 ? 'Año lectivo (10)' : '$meses meses')),
                    selected: _meses == meses,
                    onSelected: (_) => setState(() {
                      _meses = meses;
                      _elegida = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: Espacio.m),
            Card(
              color: scheme.secondaryContainer,
              child: ListTile(
                textColor: scheme.onSecondaryContainer,
                iconColor: scheme.onSecondaryContainer,
                leading: const Icon(Icons.event_available_outlined),
                title: const Text('Queda pagado hasta'),
                subtitle: Text(_fecha(_hasta), style: text.titleMedium?.copyWith(color: scheme.onSecondaryContainer)),
                trailing: TextButton(
                  style: TextButton.styleFrom(foregroundColor: scheme.onSecondaryContainer),
                  onPressed: _elegirFecha,
                  child: const Text('Cambiar'),
                ),
              ),
            ),
            const SizedBox(height: Espacio.m),
            TextField(
              controller: _referencia,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Referencia (opcional)',
                hintText: 'Número de transferencia, banco, quién depositó',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: Espacio.s),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: Espacio.s),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _guardando ? null : _guardar,
                icon: const Icon(Icons.check),
                label: const Text('Registrar el pago'),
              ),
            ),
            const SizedBox(height: Espacio.l),
            Text('PAGOS ANTERIORES', style: text.labelSmall),
            _Historial(ruta: widget.cuenta.ruta),
          ],
        ),
      ),
    );
  }

  Future<void> _elegirFecha() async {
    final f = await showDatePicker(
      context: context,
      initialDate: _hasta,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (f != null) setState(() => _elegida = f);
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).post<void>('/plataforma/${widget.cuenta.ruta}/pagos', body: {
        'monto': _leerMonto(_monto.text) ?? 0,
        'periodos': _meses,
        // Sólo si se cambió a mano: si no, la cuenta la hace el servidor.
        'pagadoHasta': _elegida == null ? null : _iso(_elegida!),
        'referencia': _referencia.text.trim().isEmpty ? null : _referencia.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() {
        _guardando = false;
        _error = e.isNetworkError ? 'Necesitas internet.' : e.message;
      });
    }
  }
}

/// Lo que ya se cobró, para no anotar dos veces el mismo depósito.
class _Historial extends ConsumerWidget {
  const _Historial({required this.ruta});

  final String ruta;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(pagosProvider(ruta)).when(
        loading: () => const Padding(padding: EdgeInsets.all(Espacio.m), child: LinearProgressIndicator()),
        error: (e, _) => Padding(padding: const EdgeInsets.all(Espacio.m), child: Text('$e')),
        data: (pagos) => pagos.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: Espacio.m),
                child: Text('Todavía no se le registró ningún pago.'),
              )
            : Column(
                children: [
                  for (final p in pagos)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text('${_lempiras((p['monto'] as num).toDouble())} · ${fechaCorta(p['pagadoEl'] as String)}'),
                      subtitle: Text('dejó pagado hasta ${fechaCorta(p['cubreHasta'] as String)}'
                          '${p['referencia'] == null ? '' : ' · ${p['referencia']}'}'),
                    ),
                ],
              ),
      );
}

/// El plan que fija la plataforma: cuánto, hasta cuándo, cuántos días de gracia, cómo
/// paga y, en el docente personal, cuántas asignaturas cubre.
class _HojaPlan extends ConsumerStatefulWidget {
  const _HojaPlan({required this.cuenta});

  final _Cuenta cuenta;

  @override
  ConsumerState<_HojaPlan> createState() => _HojaPlanState();
}

class _HojaPlanState extends ConsumerState<_HojaPlan> {
  Cobro get _c => widget.cuenta.cobro;
  late final _nombre = TextEditingController(text: _c.planNombre ?? '');
  late final _monto = TextEditingController(text: _c.monto > 0 ? _lempiras(_c.monto).substring(2) : '');
  late final _comoPagar = TextEditingController(text: _c.comoPagar ?? '');
  late DateTime? _hasta = _c.pagadoHasta;
  late int _gracia = _c.diasGracia;
  late String? _nivel = _c.nivel;
  var _guardando = false;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    _monto.dispose();
    _comoPagar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final bloquea = _hasta?.add(Duration(days: _gracia + 1));

    return Padding(
      padding: EdgeInsets.fromLTRB(Espacio.l, 0, Espacio.l, MediaQuery.viewInsetsOf(context).bottom + Espacio.l),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Plan de ${widget.cuenta.nombre}', style: text.titleLarge),
            const SizedBox(height: Espacio.xs),
            Text('Sin fecha de vencimiento la cuenta nunca queda de solo lectura.', style: text.bodySmall),
            if (!widget.cuenta.esCentro) ...[
              const SizedBox(height: Espacio.l),
              Text('Asignaturas que cubre', style: text.labelLarge),
              const SizedBox(height: Espacio.s),
              Wrap(
                spacing: Espacio.s,
                runSpacing: Espacio.s,
                children: [
                  for (final e in nivelesDocente.entries)
                    ChoiceChip(
                      label: Text('${e.value.$1} · ${e.value.$2 == null ? 'ilimitadas' : 'hasta ${e.value.$2}'}'),
                      selected: _nivel == e.key,
                      onSelected: (_) => setState(() => _nivel = e.key),
                    ),
                  ChoiceChip(
                    label: const Text('Cortesía · sin tope'),
                    selected: _nivel == null,
                    onSelected: (_) => setState(() => _nivel = null),
                  ),
                ],
              ),
            ],
            const SizedBox(height: Espacio.l),
            TextField(
              controller: _nombre,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nombre del plan', hintText: 'Docente mensual, Año lectivo'),
            ),
            const SizedBox(height: Espacio.m),
            TextField(
              controller: _monto,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: const InputDecoration(labelText: 'Monto del período', prefixText: 'L '),
            ),
            const SizedBox(height: Espacio.m),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Pagado hasta'),
              subtitle: Text(_hasta == null ? 'Sin vencimiento' : _fecha(_hasta!)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_hasta != null)
                    IconButton(
                      tooltip: 'Quitar el vencimiento',
                      onPressed: () => setState(() => _hasta = null),
                      icon: const Icon(Icons.clear),
                    ),
                  TextButton(
                    onPressed: () async {
                      final f = await showDatePicker(
                        context: context,
                        initialDate: _hasta ?? DateTime.now(),
                        firstDate: DateTime(2024),
                        lastDate: DateTime(DateTime.now().year + 5),
                      );
                      if (f != null) setState(() => _hasta = f);
                    },
                    child: const Text('Elegir'),
                  ),
                ],
              ),
            ),
            Text('Días de gracia: $_gracia', style: text.bodyMedium),
            Slider(
              value: _gracia.toDouble(),
              max: 30,
              divisions: 30,
              label: '$_gracia',
              onChanged: (v) => setState(() => _gracia = v.round()),
            ),
            if (bloquea != null)
              Text('Queda de solo lectura el ${_fecha(bloquea)}.', style: text.bodySmall?.copyWith(color: scheme.error)),
            const SizedBox(height: Espacio.m),
            TextField(
              controller: _comoPagar,
              maxLines: 3,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Cómo pagar',
                hintText: 'Banco, cuenta y a nombre de quién. Se muestra sólo en la web.',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: Espacio.s),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: Espacio.m),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _guardando ? null : _guardar, child: const Text('Guardar el plan')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).put<void>('/plataforma/${widget.cuenta.ruta}/plan', body: {
        'planNombre': _nombre.text.trim(),
        'monto': _leerMonto(_monto.text) ?? 0,
        'pagadoHasta': _hasta == null ? null : _iso(_hasta!),
        'diasGracia': _gracia,
        'comoPagar': _comoPagar.text.trim(),
        if (!widget.cuenta.esCentro) 'nivel': _nivel,
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() {
        _guardando = false;
        _error = e.isNetworkError ? 'Necesitas internet.' : e.message;
      });
    }
  }
}

/// Alta de un centro (con su administrador) o cambio de su plan y cupo. El cobro va aparte.
class _FormCentro extends ConsumerStatefulWidget {
  const _FormCentro({this.institucion});

  final Map<String, dynamic>? institucion;

  @override
  ConsumerState<_FormCentro> createState() => _FormCentroState();
}

class _FormCentroState extends ConsumerState<_FormCentro> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.institucion?['nombre'] as String? ?? '');
  late final _cupo = TextEditingController(text: '${widget.institucion?['maxDocentes'] ?? 15}');
  final _adminNombre = TextEditingController();
  final _adminCorreo = TextEditingController();
  late String _plan = widget.institucion?['plan'] as String? ?? 'pequeno';
  DateTime? _pagadoHasta = DateTime(DateTime.now().year, 12, 31);
  var _guardando = false;
  String? _error;

  bool get _nuevo => widget.institucion == null;

  static const _cupoSugerido = {'pequeno': 15, 'mediano': 40, 'grande': 80, 'red': 200};

  @override
  void dispose() {
    for (final c in [_nombre, _cupo, _adminNombre, _adminCorreo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    final api = ref.read(apiClientProvider);
    try {
      if (_nuevo) {
        final creado = await api.post('/plataforma/instituciones',
            body: {
              'nombre': _nombre.text.trim(),
              'plan': _plan,
              'maxDocentes': int.parse(_cupo.text),
              'pagadoHasta': _pagadoHasta == null ? null : _iso(_pagadoHasta!),
              'adminEmail': _adminCorreo.text.trim(),
              'adminNombre': _adminNombre.text.trim(),
            },
            parse: (d) => d as Map<String, dynamic>);
        if (mounted) Navigator.pop(context, creado);
      } else {
        await api.put<void>('/plataforma/instituciones/${widget.institucion!['id']}',
            body: {'plan': _plan, 'maxDocentes': int.parse(_cupo.text)});
        if (mounted) Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      setState(() => _error = e.isNetworkError ? 'Necesitas internet.' : e.message);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: const RoundedRectangleBorder(),
      title: Text(_nuevo ? 'Nuevo centro' : 'Plan de ${widget.institucion!['nombre']}'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_nuevo) ...[
                  TextFormField(
                    controller: _nombre,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Nombre del centro'),
                    validator: (v) => (v?.trim().isEmpty ?? true) ? 'Escribe el nombre' : null,
                  ),
                  const SizedBox(height: Espacio.m),
                ],
                DropdownButtonFormField<String>(
                  initialValue: _plan,
                  decoration: const InputDecoration(labelText: 'Plan'),
                  items: [for (final e in planesCentro.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (p) => setState(() {
                    _plan = p!;
                    _cupo.text = '${_cupoSugerido[p]}';
                  }),
                ),
                const SizedBox(height: Espacio.m),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _cupo,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(labelText: 'Cupo de docentes'),
                        validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1 ? 'Mínimo 1' : null,
                      ),
                    ),
                    if (_nuevo) ...[
                      const SizedBox(width: Espacio.m),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final f = await showDatePicker(
                              context: context,
                              initialDate: _pagadoHasta ?? DateTime.now(),
                              firstDate: DateTime(2024),
                              lastDate: DateTime(2035),
                            );
                            if (f != null) setState(() => _pagadoHasta = f);
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Pagado hasta'),
                            child: Text(_pagadoHasta == null ? 'Sin fecha' : _fecha(_pagadoHasta!)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (_nuevo) ...[
                  const SizedBox(height: Espacio.xl),
                  Text('ADMINISTRADOR DEL CENTRO', style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: Espacio.s),
                  TextFormField(
                    controller: _adminNombre,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Nombre (director, coordinador…)'),
                    validator: (v) => (v?.trim().isEmpty ?? true) ? 'Escribe el nombre' : null,
                  ),
                  const SizedBox(height: Espacio.m),
                  TextFormField(
                    controller: _adminCorreo,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Correo'),
                    validator: (v) => (v == null || !v.contains('@')) ? 'Correo no válido' : null,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: Espacio.m),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _guardando ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _guardando ? null : _guardar, child: Text(_nuevo ? 'Crear centro' : 'Guardar')),
      ],
    );
  }
}
