import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/asignatura/asignatura_page.dart';
import '../features/asignatura/calificar_page.dart';
import '../features/asistencia/asistencia_page.dart';
import '../features/auth/login_page.dart';
import '../features/clases/clase_page.dart';
import '../features/cuenta/cuenta_page.dart';
import '../features/inicio/inicio_page.dart';
import '../features/planes/plantillas_page.dart';
import '../ui/shell.dart';
import 'auth/auth_controller.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ValueNotifier<AuthState>(ref.read(authControllerProvider));
  ref.listen(authControllerProvider, (_, next) => notifier.value = next);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: notifier,
    redirect: (context, state) {
      final auth = notifier.value;
      if (auth.isRestoring) return null;

      final path = state.uri.path;
      if (!auth.isAuthenticated) return path == '/login' ? null : '/login';
      if (path == '/login' || path == '/' || path.startsWith('/clases')) return '/inicio';
      return null;
    },
    routes: [
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
