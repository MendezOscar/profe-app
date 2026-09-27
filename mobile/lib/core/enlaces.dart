import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Páginas del sitio público: la landing y lo legal que piden las tiendas.
class Enlaces {
  static const _sitio = String.fromEnvironment('SITE_URL', defaultValue: 'https://profe-app.pages.dev');

  /// En la web, el mismo sitio donde corre el panel (sirve igual en local y en producción).
  static Uri get sitio => kIsWeb ? Uri.base.resolve('/') : Uri.parse(_sitio);

  static Uri get privacidad => sitio.resolve('privacidad');
  static Uri get terminos => sitio.resolve('terminos');
  static Uri get soporte => sitio.resolve('soporte');
  static Uri get eliminarCuenta => sitio.resolve('eliminar-cuenta');

  static Future<void> abrir(Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);

  /// Al cerrar sesión en la web se vuelve a la landing, en la misma pestaña.
  static Future<void> volverAlSitio() => launchUrl(sitio, webOnlyWindowName: '_self');
}
