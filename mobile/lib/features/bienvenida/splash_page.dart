import 'package:flutter/material.dart';

import '../../theme/profeapp_theme.dart';

/// Continúa el splash nativo (fondo azul) mientras se recupera la sesión, con una
/// entrada suave del logo. Si la red tarda, aparece un indicador para que no parezca trabado.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  late final _entrada = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
  late final _escala = Tween(begin: 0.9, end: 1.0).animate(CurvedAnimation(parent: _entrada, curve: Curves.easeOutCubic));
  var _demora = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _demora = true);
    });
  }

  @override
  void dispose() {
    _entrada.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ProfeColors.azul,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeTransition(
              opacity: _entrada,
              child: ScaleTransition(
                scale: _escala,
                child: Image.asset('assets/brand/logo-blanco.png', width: 200, semanticLabel: 'ProfeApp'),
              ),
            ),
            const SizedBox(height: 32),
            AnimatedOpacity(
              opacity: _demora ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: ProfeColors.blanco),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
