import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import 'api/api_client.dart';
import 'auth/auth_controller.dart';
import 'local/clases_repository.dart';
import 'local/local_db.dart';
import 'models/clase.dart';
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

/// Base local del usuario en sesión. Sólo cambia al cambiar de usuario, no al renovar el token.
final localDbProvider = Provider<Future<Database>>((ref) {
  final userId = ref.watch(sessionProvider.select((s) => s?.userId));
  final db = LocalDb.open(userId ?? 'sin-sesion');
  ref.onDispose(() async => (await db).close());
  return db;
});

final clasesRepositoryProvider = Provider((ref) => ClasesRepository(ref.watch(localDbProvider)));

final clasesProvider = FutureProvider<List<ClaseResumen>>((ref) => ref.watch(clasesRepositoryProvider).listar());

final claseProvider =
    FutureProvider.family<ClaseDetalle, String>((ref, id) => ref.watch(clasesRepositoryProvider).detalle(id));
