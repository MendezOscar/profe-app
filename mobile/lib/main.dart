import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Rutas sin '#' en web. En móvil es una llamada sin efecto.
  usePathUrlStrategy();
  runApp(const ProviderScope(child: ProfeApp()));
}
