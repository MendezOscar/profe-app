import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/asignatura/asignatura_page.dart';
import '../features/asignatura/calificar_page.dart';
import '../features/asignatura/calificar_varias_page.dart';
import '../features/asistencia/asistencia_page.dart';
import '../features/auth/login_page.dart';
import '../features/bienvenida/bienvenida_page.dart';
import '../features/bienvenida/splash_page.dart';
import '../features/clases/clase_page.dart';
import '../features/cuenta/cuenta_page.dart';
import '../features/inicio/inicio_page.dart';
import '../features/planes/plantillas_page.dart';
import '../ui/shell.dart';
import 'auth/auth_controller.dart';
import 'preferencias.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // El router se reevalúa cuando cambia la sesión o se termina la introducción.
  final refresco = ValueNotifier(0);
  ref.listen(authControllerProvider, (_, _) => refresco.value++);
  ref.listen(banderaProvider(Bandera.introVista), (_, _) => refresco.value++);
  ref.onDispose(refresco.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresco,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final path = state.uri.path;
      // Mientras se recupera la sesión, el splash; se recuerda a dónde iba (enlaces en web).
      if (auth.isRestoring) {
        if (path == '/splash') return null;
        return Uri(path: '/splash', queryParameters: path == '/' ? null : {'desde': state.uri.toString()}).toString();
      }
      final desde = state.uri.queryParameters['desde'];

      if (!auth.isAuthenticated) {
        if (!ref.read(banderaProvider(Bandera.introVista))) return path == '/bienvenida' ? null : '/bienvenida';
        return path == '/login' || path == '/bienvenida' ? null : '/login';
      }
      // La introducción se puede volver a ver desde Cuenta.
      if (path == '/splash' || path == '/login' || path == '/' || path.startsWith('/clases')) {
        return desde != null && desde.startsWith('/') && !desde.startsWith('/splash') ? desde : '/inicio';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashPage()),
      GoRoute(path: '/bienvenida', builder: (context, state) => const BienvenidaPage()),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      // Rutas anidadas: el detalle se apila sobre su lista y "atrás" vuelve a ella.
      ShellRoute(
        builder: (context, state, child) => ShellAdaptativo(ubicacion: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/inicio',
            builder: (context, state) => const InicioPage(),
            routes: [
              GoRoute(
                path: 'asignaturas/:id',
                builder: (context, state) => AsignaturaPage(
                  claseId: state.pathParameters['id']!,
                  parcial: state.uri.queryParameters['parcial'],
                ),
                routes: [
                  GoRoute(
                    path: 'cuadro',
                    builder: (context, state) => ClasePage(claseId: state.pathParameters['id']!),
                  ),
                  GoRoute(
                    path: 'calificar',
                    builder: (context, state) => CalificarVariasPage(
                      claseId: state.pathParameters['id']!,
                      parcial: state.uri.queryParameters['parcial'] ?? '',
                      actividadIds: (state.uri.queryParameters['actividades'] ?? '').split(',').where((id) => id.isNotEmpty).toList(),
                    ),
                  ),
                  GoRoute(
                    path: 'actividades/:actividadId',
                    builder: (context, state) => CalificarPage(
                      claseId: state.pathParameters['id']!,
                      parcial: state.uri.queryParameters['parcial'] ?? '',
                      actividadId: state.pathParameters['actividadId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/asistencia',
            builder: (context, state) => const AsistenciaPage(),
            routes: [
              GoRoute(
                path: ':claseId',
                builder: (context, state) => PasarListaPage(claseId: state.pathParameters['claseId']!),
              ),
            ],
          ),
          GoRoute(path: '/plantillas', builder: (context, state) => const PlantillasPage()),
          GoRoute(path: '/cuenta', builder: (context, state) => const CuentaPage()),
        ],
      ),
    ],
  );
});
