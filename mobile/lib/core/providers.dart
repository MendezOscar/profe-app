import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'auth/auth_controller.dart';
import 'models/session.dart';

/// Cliente HTTP atado a la sesión vigente: al renovarse el token se recrea.
final apiClientProvider = Provider<ApiClient>((ref) {
  final auth = ref.watch(authControllerProvider);
  final controller = ref.read(authControllerProvider.notifier);
  return ApiClient(
    session: auth.session,
    onRefresh: (expired) => controller.refresh(expired),
  );
});

final sessionProvider = Provider<Session?>((ref) => ref.watch(authControllerProvider).session);
