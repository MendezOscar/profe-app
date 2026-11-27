import 'package:cupertino_ui/cupertino_ui.dart';
// Los delegados de idioma de Material y Cupertino se mudaron con sus bibliotecas, y
// flutter_localizations todavía exporta los suyos: se esconden los viejos para que no haya
// dos nombres iguales. De aquí sale solo el de widgets, que no se mudó.
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalCupertinoLocalizations, GlobalMaterialLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/avisos/push.dart';

import 'core/router.dart';
import 'core/sync/sync_controller.dart';
import 'theme/profeapp_theme.dart';

class ProfeApp extends ConsumerWidget {
  const ProfeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Escuchado en la raíz: la sincronización corre apenas hay sesión, esté donde esté el
    // docente. listen y no watch, para no reconstruir toda la app en cada cambio de estado.
    ref.listen(syncControllerProvider, (_, _) {});
    // Avisos al teléfono de la familia (registra el dispositivo al iniciar sesión).
    ref.watch(pushProvider);

    return MaterialApp.router(
      title: 'ProfeApp',
      debugShowCheckedModeBanner: false,
      // Claro u oscuro según el modo del teléfono.
      theme: profeTheme(),
      darkTheme: profeTheme(oscuro: true),
      routerConfig: ref.watch(routerProvider),
      // En el teléfono, tocar fuera de un campo cierra el teclado.
      builder: (context, child) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child,
      ),
      locale: const Locale('es', 'HN'),
      supportedLocales: const [Locale('es', 'HN'), Locale('es'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
