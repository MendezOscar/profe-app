import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Carga de esqueleto: la forma de lo que viene, latiendo suave, en lugar de una pantalla
/// en blanco con un círculo. Con "reducir movimiento" activo no late.
class Esqueleto extends StatefulWidget {
  const Esqueleto({super.key, required this.child});

  final Widget child;

  @override
  State<Esqueleto> createState() => _EsqueletoState();
}

class _EsqueletoState extends State<Esqueleto> with SingleTickerProviderStateMixin {
  late final _pulso = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulso.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quieto = MediaQuery.of(context).disableAnimations;
    return Semantics(
      label: 'Cargando',
      liveRegion: true,
      excludeSemantics: true,
      child: quieto
          ? widget.child
          : FadeTransition(opacity: Tween(begin: 0.45, end: 1.0).animate(_pulso), child: widget.child),
    );
  }
}

/// Un bloque gris del esqueleto.
class Bloque extends StatelessWidget {
  const Bloque({super.key, this.ancho, this.alto = 14});

  final double? ancho;
  final double alto;

  @override
  Widget build(BuildContext context) =>
      Container(width: ancho, height: alto, color: ColoresEstado.of(context).esqueleto);
}

/// Filas como las de una lista: título y una línea debajo, con algo a la derecha.
class EsqueletoLista extends StatelessWidget {
  const EsqueletoLista({super.key, this.filas = 8, this.conTarjeta = false});

  final int filas;
  final bool conTarjeta;

  @override
  Widget build(BuildContext context) => Esqueleto(
        child: ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Espacio.l),
          itemCount: filas,
          separatorBuilder: (_, _) => const SizedBox(height: Espacio.m),
          itemBuilder: (context, i) {
            final fila = Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Anchos distintos para que no parezca una grilla.
                      FractionallySizedBox(widthFactor: const [0.7, 0.5, 0.6, 0.8][i % 4], child: const Bloque(alto: 16)),
                      const SizedBox(height: Espacio.s),
                      const FractionallySizedBox(widthFactor: 0.35, child: Bloque(alto: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: Espacio.l),
                const Bloque(ancho: 64, alto: 36),
              ],
            );
            return conTarjeta
                ? Container(
                    padding: const EdgeInsets.all(Espacio.l),
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    child: fila,
                  )
                : fila;
          },
        ),
      );
}

/// Tarjetas como las de las asignaturas del inicio.
class EsqueletoTarjetas extends StatelessWidget {
  const EsqueletoTarjetas({super.key, this.tarjetas = 4});

  final int tarjetas;

  @override
  Widget build(BuildContext context) => Esqueleto(
        child: Padding(
          padding: const EdgeInsets.all(Espacio.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Wrap(
                spacing: Espacio.s,
                children: [Bloque(ancho: 120, alto: 36), Bloque(ancho: 100, alto: 36), Bloque(ancho: 140, alto: 36)],
              ),
              const SizedBox(height: Espacio.l),
              Expanded(
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 440,
                    mainAxisExtent: 252,
                    crossAxisSpacing: Espacio.m,
                    mainAxisSpacing: Espacio.m,
                  ),
                  itemCount: tarjetas,
                  itemBuilder: (context, _) => Container(
                    padding: const EdgeInsets.all(Espacio.l),
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FractionallySizedBox(widthFactor: 0.6, child: Bloque(alto: 20)),
                        SizedBox(height: Espacio.s),
                        FractionallySizedBox(widthFactor: 0.8, child: Bloque(alto: 12)),
                        Spacer(),
                        Bloque(alto: 8),
                        SizedBox(height: Espacio.m),
                        FractionallySizedBox(widthFactor: 0.4, child: Bloque(alto: 12)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

/// Una pantalla de detalle completa (barra y lista) mientras carga su contenido.
class EsqueletoPagina extends StatelessWidget {
  const EsqueletoPagina({super.key, this.cuerpo = const EsqueletoLista()});

  final Widget cuerpo;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: true,
          title: const Esqueleto(child: SizedBox(width: 200, child: Bloque(alto: 20))),
        ),
        body: cuerpo,
      );
}
