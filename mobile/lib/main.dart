import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/avisos/push.dart';
import 'core/preferencias.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Rutas sin '#' en web. En móvil es una llamada sin efecto.
  usePathUrlStrategy();
  await Push.iniciar();
  final preferencias = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [preferenciasProvider.overrideWithValue(preferencias)],
    child: const ProfeApp(),
  ));
}
