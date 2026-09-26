import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Se carga en main antes de arrancar, para que el router decida sin esperar.
final preferenciasProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('Se inyecta en main'));

/// Marcas del dispositivo que no viajan al servidor.
enum Bandera {
  /// Ya vio la introducción de la app.
  introVista('profeapp.intro_vista'),

  /// Ocultó la tarjeta de primeros pasos del inicio.
  primerosPasosOcultos('profeapp.primeros_pasos_ocultos');

  const Bandera(this.clave);
  final String clave;
}

class BanderaNotifier extends FamilyNotifier<bool, Bandera> {
  @override
  bool build(Bandera arg) => ref.watch(preferenciasProvider).getBool(arg.clave) ?? false;

  Future<void> poner(bool valor) async {
    state = valor;
    await ref.read(preferenciasProvider).setBool(arg.clave, valor);
  }
}

final banderaProvider = NotifierProvider.family<BanderaNotifier, bool, Bandera>(BanderaNotifier.new);
