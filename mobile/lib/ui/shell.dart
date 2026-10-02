import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/profeapp_theme.dart';
import 'aviso_cobro.dart';
import 'estado_error.dart';
import 'indicador_sync.dart';

/// Anchos de Material 3: compacto (teléfono), medio (tablet) y expandido (escritorio).
enum Ancho {
  compacto,
  medio,
  expandido;

  static Ancho de(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w < 600 ? compacto : (w < 1240 ? medio : expandido);
  }
}

class _Destino {
  const _Destino(this.ruta, this.icono, this.iconoActivo, this.etiqueta);

  final String ruta;
  final IconData icono;
  final IconData iconoActivo;
  final String etiqueta;
}

const _destinos = [
  _Destino('/inicio', Icons.dashboard_outlined, Icons.dashboard, 'Inicio'),
  _Destino('/asistencia', Icons.fact_check_outlined, Icons.fact_check, 'Asistencia'),
  _Destino('/plantillas', Icons.view_list_outlined, Icons.view_list, 'Rúbricas'),
  _Destino('/cuenta', Icons.person_outline, Icons.person, 'Cuenta'),
];

/// Marco de la app: barra inferior en el teléfono y riel lateral en tablet y web.
/// Las pantallas de detalle ocultan la barra inferior para dejar todo el alto al trabajo.
class ShellAdaptativo extends StatelessWidget {
  const ShellAdaptativo({super.key, required this.child, required this.ubicacion});

  final Widget child;
  final String ubicacion;

  int get _indice {
    final i = _destinos.indexWhere((d) => ubicacion.startsWith(d.ruta));
    // Las asignaturas cuelgan del inicio.
    return i < 0 ? 0 : i;
  }

  bool get _esRaiz => _destinos.any((d) => d.ruta == ubicacion);

  @override
  Widget build(BuildContext context) {
    final ancho = Ancho.de(context);
    void ir(int i) => context.go(_destinos[i].ruta);

    if (ancho == Ancho.compacto) {
      return Scaffold(
        body: Column(children: [const AvisoCobro(), Expanded(child: child), const AvisoSinConexion()]),
        bottomNavigationBar: _esRaiz
            ? NavigationBar(
                selectedIndex: _indice,
                onDestinationSelected: ir,
                destinations: [
                  for (final d in _destinos)
                    NavigationDestination(icon: Icon(d.icono), selectedIcon: Icon(d.iconoActivo), label: d.etiqueta),
                ],
              )
            : null,
      );
    }

    final extendido = ancho == Ancho.expandido;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: extendido,
            minExtendedWidth: 220,
            backgroundColor: ProfeColors.blanco,
            indicatorColor: ProfeColors.azulClaro,
            indicatorShape: const RoundedRectangleBorder(),
            selectedIndex: _indice,
            onDestinationSelected: ir,
            labelType: extendido ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: Espacio.l),
              child: extendido
                  ? Image.asset('assets/brand/logo-azul.png', height: 32, semanticLabel: 'ProfeApp')
                  : Image.asset('assets/brand/simbolo-1024.png', height: 40, semanticLabel: 'ProfeApp'),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: Espacio.l),
                  child: IndicadorSync(conTexto: extendido),
                ),
              ),
            ),
            destinations: [
              for (final d in _destinos)
                NavigationRailDestination(
                    icon: Icon(d.icono), selectedIcon: Icon(d.iconoActivo), label: Text(d.etiqueta)),
            ],
          ),
          const VerticalDivider(width: 2),
          Expanded(child: Column(children: [const AvisoCobro(), Expanded(child: child), const AvisoSinConexion()])),
        ],
      ),
    );
  }
}

/// Limita el ancho del contenido en pantallas grandes: líneas de más de ~900 px cansan.
class ContenidoCentrado extends StatelessWidget {
  const ContenidoCentrado({super.key, required this.child, this.maxAncho = 960});

  final Widget child;
  final double maxAncho;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxAncho), child: child),
      );
}
