import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_page.dart';
import '../features/home/home_page.dart';
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
      if (path == '/login' || path == '/') return '/clases';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(path: '/clases', builder: (context, state) => const HomePage()),
    ],
  );
});
