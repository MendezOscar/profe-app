import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/preferencias.dart';
import '../../core/providers.dart';
import '../../theme/profeapp_theme.dart';

class _Paso {
  const _Paso(this.icono, this.titulo, this.texto);

  final IconData icono;
  final String titulo;
  final String texto;
}

const _pasos = [
  _Paso(
    Icons.upload_file,
    'Tus cuadros de SACE, en tu bolsillo',
    'Importa el cuadro de cada asignatura tal como lo descargas de SACE. '
        'Tus alumnos quedan listos y trabajas aunque no haya internet.',
  ),
  _Paso(
    Icons.view_list,
    'Un plan por puntos, a tu manera',
    'Reparte los 100 puntos del parcial en tareas, trabajos y exámenes. '
        'Si el parcial cambia, cambias el plan.',
  ),
  _Paso(
    Icons.fact_check,
    'Califica y pasa lista en segundos',
    'Escribe las notas alumno por alumno con el teclado numérico y marca solo a los que faltan.',
  ),
  _Paso(
    Icons.task_alt,
    'Cierra el parcial y súbelo a SACE',
    'ProfeApp suma puntos y faltas, llena el cuadro y te lo entrega listo para cargarlo en SACE.',
  ),
];

/// Introducción de la primera vez: qué hace la app en cuatro pantallas. Se puede saltar
/// y volver a ver desde Cuenta.
class BienvenidaPage extends ConsumerStatefulWidget {
  const BienvenidaPage({super.key});

  @override
  ConsumerState<BienvenidaPage> createState() => _BienvenidaPageState();
}

class _BienvenidaPageState extends ConsumerState<BienvenidaPage> {
  final _paginas = PageController();
  var _actual = 0;

  bool get _ultima => _actual == _pasos.length - 1;

  @override
  void dispose() {
    _paginas.dispose();
    super.dispose();
  }

  Future<void> _terminar() async {
    await ref.read(banderaProvider(Bandera.introVista).notifier).poner(true);
    // Con sesión (vista desde Cuenta) vuelve al inicio; sin sesión, al login.
    if (mounted) context.go(ref.read(sessionProvider) != null ? '/inicio' : '/login');
  }

  void _ir(int pagina) =>
      _paginas.animateToPage(pagina, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return CallbackShortcuts(
      // En la web también con el teclado.
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _ultima ? _terminar() : _ir(_actual + 1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _actual > 0 ? _ir(_actual - 1) : null,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Espacio.xl, Espacio.l, Espacio.s, 0),
                      child: Row(
                        children: [
                          Image.asset('assets/brand/logo-azul.png', height: 28, semanticLabel: 'ProfeApp'),
                          const Spacer(),
                          if (!_ultima) TextButton(onPressed: _terminar, child: const Text('Saltar')),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: _paginas,
                        itemCount: _pasos.length,
                        onPageChanged: (i) => setState(() => _actual = i),
                        itemBuilder: (context, i) => _Pagina(paso: _pasos[i], numero: i + 1),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Espacio.xl, 0, Espacio.xl, Espacio.xl),
                      child: Row(
                        children: [
                          Semantics(
                            label: 'Paso ${_actual + 1} de ${_pasos.length}',
                            child: Row(
                              children: [
                                for (var i = 0; i < _pasos.length; i++)
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    margin: const EdgeInsets.only(right: Espacio.s),
                                    width: i == _actual ? 24 : 8,
                                    height: 8,
                                    color: i == _actual ? scheme.primary : scheme.primaryContainer,
                                  ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: _ultima ? _terminar : () => _ir(_actual + 1),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_ultima ? 'Empezar' : 'Siguiente', style: text.labelLarge?.copyWith(
                                    color: scheme.onPrimary, fontWeight: FontWeight.w800)),
                                const SizedBox(width: Espacio.s),
                                Icon(_ultima ? Icons.check : Icons.arrow_forward, size: 20),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pagina extends StatelessWidget {
  const _Pagina({required this.paso, required this.numero});

  final _Paso paso;
  final int numero;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: Espacio.xl, vertical: Espacio.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: Espacio.xl),
          // Ilustración con piezas de la marca: bloque azul, ícono blanco y el número del paso.
          AspectRatio(
            aspectRatio: 1.4,
            child: Container(
              color: ProfeColors.azulClaro,
              child: Stack(
                children: [
                  Positioned(
                    left: 24,
                    top: 20,
                    child: Text('0$numero',
                        style: text.displayMedium?.copyWith(fontWeight: FontWeight.w800, color: ProfeColors.azul.withValues(alpha: 0.25))),
                  ),
                  Center(
                    child: Container(
                      width: 128,
                      height: 128,
                      color: ProfeColors.azul,
                      child: Icon(paso.icono, size: 64, color: ProfeColors.blanco),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Espacio.xxl),
          Text(paso.titulo, style: text.headlineMedium),
          const SizedBox(height: Espacio.m),
          Text(paso.texto, style: text.bodyLarge?.copyWith(color: ProfeColors.textoSuave, height: 1.45)),
        ],
      ),
    );
  }
}
