# ProfeApp — kit de marca

Azul #2B59C3 + blanco. Marino #14213D solo para texto. Tipografía Archivo (400 / 600 / 800). Sin esquinas redondeadas.

## Web (web/)
1. Copie todo web/ a la raíz pública del sitio.
2. Pegue head.html dentro de <head>.
3. Use las variables de tokens.css (--pa-primario, --pa-texto…).

## Flutter (flutter/ → carpeta mobile/ del repo)
- flutter/web/* reemplaza mobile/web/favicon.png, mobile/web/icons/* y mobile/web/manifest.json.
- flutter/lib/theme/profeapp_theme.dart → mobile/lib/theme/. En MaterialApp: theme: profeTheme(). Agregue google_fonts al pubspec.
- flutter/assets/ → declárelo en pubspec (assets: - assets/) para usar el logo en login/splash.

## Android (android/res/ → mobile/android/app/src/main/res/)
- Reemplace las carpetas mipmap-*, agregue mipmap-anydpi-v26, drawable/ic_launcher_foreground.xml y values/colors.xml (si ya existe colors.xml, copie solo los <color>).
- play-store-512.png es el ícono para Google Play.

## Logo (logo/)
- logo-azul sobre fondos claros · logo-blanco sobre azul o fondos oscuros.
- Espacio libre mínimo: ¼ del símbolo. Tamaño mínimo: símbolo 16 px, logo completo 96 px de ancho.
- No redondear, no cambiar colores, no rotar el cheque, no agregar sombras.
