import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import 'api/api_client.dart';
import 'auth/auth_controller.dart';
import 'local/clases_repository.dart';
import 'local/local_db.dart';
import 'local/sync_repository.dart';
import 'models/clase.dart';
import 'models/session.dart';
import 'planes/calculo_parcial.dart';
import 'planes/modelos.dart';
import 'planes/planes_repository.dart';
import 'sace/exportador_cuadro.dart';
import 'sync/sync_controller.dart';

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

final planesRepositoryProvider =
    Provider((ref) => PlanesRepository(ref.watch(localDbProvider), ref.watch(clasesRepositoryProvider)));

final syncRepositoryProvider = Provider((ref) => SyncRepository(ref.watch(localDbProvider)));

final exportadorCuadroProvider = Provider((ref) => ExportadorCuadro(ref.watch(apiClientProvider)));

final clasesProvider = FutureProvider<List<ClaseResumen>>((ref) => ref.watch(clasesRepositoryProvider).listar());

final claseProvider =
    FutureProvider.family<ClaseDetalle, String>((ref, id) => ref.watch(clasesRepositoryProvider).detalle(id));

final parcialesProvider =
    FutureProvider.family<List<Parcial>, String>((ref, claseId) => ref.watch(planesRepositoryProvider).parciales(claseId));

/// Plan, notas y asistencia de una clase en un parcial (por su clave).
final planProvider = FutureProvider.family<PlanParcial, (String, String)>((ref, clave) async {
  final (claseId, parcialClave) = clave;
  final parciales = await ref.watch(parcialesProvider(claseId).future);
  final parcial = parciales.firstWhere((p) => p.clave == parcialClave);
  return ref.watch(planesRepositoryProvider).plan(claseId, parcial);
});

/// Todos los parciales de una clase, para ver cómo cambió de uno a otro.
final planesClaseProvider = FutureProvider.family<List<PlanParcial>, String>((ref, claseId) async {
  final parciales = await ref.watch(parcialesProvider(claseId).future);
  return ref.watch(planesRepositoryProvider).planes([for (final p in parciales) (claseId, p)]);
});

final plantillasProvider = FutureProvider<List<Plantilla>>((ref) => ref.watch(planesRepositoryProvider).plantillas());

/// Cómo va cada asignatura en su parcial en curso (el primero sin cerrar).
class AvanceClase {
  const AvanceClase({required this.clase, this.plan, this.resultado});

  final ClaseResumen clase;
  final PlanParcial? plan;
  final ResultadoParcial? resultado;
}

final tableroProvider = FutureProvider<List<AvanceClase>>((ref) async {
  final clases = await ref.watch(clasesProvider.future);
  final repo = ref.watch(planesRepositoryProvider);
  final ids = [for (final c in clases) c.id];
  final parciales = await repo.parcialesDe(ids);
  final cerrados = await repo.cerradosDe(ids);
  // Un solo plan por clase: el del primer parcial abierto (o el último, si están todos cerrados).
  final pedidos = [
    for (final id in ids)
      if (parciales[id] case final ps? when ps.isNotEmpty)
        (id, ps.where((p) => !(cerrados[id]?.contains(p.clave) ?? false)).firstOrNull ?? ps.last),
  ];
  final planes = {for (final plan in await repo.planes(pedidos)) plan.claseId: plan};
  return [
    for (final clase in clases)
      if (planes[clase.id] case final plan?)
        AvanceClase(clase: clase, plan: plan, resultado: calcularParcial(plan))
      else
        AvanceClase(clase: clase),
  ];
});

/// Se recalcula junto con el tablero.
final progresoProvider = FutureProvider((ref) async {
  await ref.watch(tableroProvider.future);
  return ref.watch(planesRepositoryProvider).progreso();
});

/// Tras un cambio en el plan de una clase: refresca lo que lo muestra y agenda el respaldo.
void planCambiado(WidgetRef ref, String claseId, String parcial) {
  ref.invalidate(planProvider((claseId, parcial)));
  ref.invalidate(tableroProvider);
  ref.invalidate(planesClaseProvider(claseId));
  ref.read(syncControllerProvider.notifier).programar();
}
