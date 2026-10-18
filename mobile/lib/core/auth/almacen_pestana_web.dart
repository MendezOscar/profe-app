// sessionStorage: dura lo que la pestaña. Para el panel abierto en una computadora compartida.
import 'package:web/web.dart' as web;

String? leerDePestana(String clave) => web.window.sessionStorage.getItem(clave);
void guardarEnPestana(String clave, String valor) => web.window.sessionStorage.setItem(clave, valor);
void borrarDePestana(String clave) => web.window.sessionStorage.removeItem(clave);
