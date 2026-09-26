import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/sync/sync_controller.dart';
import 'core/theme.dart';

class ProfeApp extends ConsumerWidget {
  const ProfeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Escuchado en la raíz: la sincronización corre apenas hay sesión, esté donde esté el
    // docente. listen y no watch, para no reconstruir toda la app en cada cambio de estado.
    ref.listen(syncControllerProvider, (_, _) {});

    return MaterialApp.router(
      title: 'ProfeApp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: ref.watch(routerProvider),
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
