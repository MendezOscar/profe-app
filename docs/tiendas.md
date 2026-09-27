# Publicar en App Store y Google Play

Todo lo que piden las tiendas ya está en el sitio y en la app. Esta guía junta las URL y
las respuestas de los formularios.

## URL que piden las tiendas

| Para | URL |
|---|---|
| Sitio / marketing | https://profe-app.pages.dev/ |
| Política de privacidad | https://profe-app.pages.dev/privacidad |
| Términos de uso | https://profe-app.pages.dev/terminos |
| Soporte | https://profe-app.pages.dev/soporte |
| Eliminación de cuenta (Google Play) | https://profe-app.pages.dev/eliminar-cuenta |
| Correo de contacto | cruzmendez.dev@gmail.com |

El sitio se arma con `scripts/cloudflare-build.sh`: `site/` va a la raíz y el panel Flutter
a `/app/`, enrutados por `site/_worker.js`.

## Qué cumple la app

- **Eliminar la cuenta desde la app**: Cuenta → Eliminar mi cuenta (pide la contraseña).
  Borra todo en el servidor (`POST /api/v1/auth/delete-account`) y la base del dispositivo.
  Lo exige Apple (5.1.1(v)) y Google Play.
- **Enlaces legales dentro de la app**: login y Cuenta (Privacidad, Términos, Ayuda).
- **Sin rastreo, publicidad ni SDK de terceros**: no hace falta App Tracking Transparency
  ni aviso de cookies (solo almacenamiento estrictamente necesario, ver `/cookies`).
- **Cifrado**: solo HTTPS. `ITSAppUsesNonExemptEncryption = false` en `Info.plist`, así
  App Store Connect no pregunta por exportación en cada versión.
- **No se crean cuentas desde la app**: las da el administrador. Para la revisión hace falta
  dar una cuenta de prueba (abajo).

## Cuenta para los revisores

Crear una cuenta dedicada con datos de ejemplo (un cuadro ficticio, como
`mobile/test/fixtures/cuadro_basica.xls`) y ponerla en *App Review Information* (Apple) y
*App access* (Google). No usar la cuenta demo pública con contraseña del README. Explicar:
"Las cuentas las crea el administrador para cada docente; esta es una cuenta de prueba".

Si el revisor la elimina, hay que volver a crearla antes del siguiente envío.

## App Store Connect — Privacidad de la app

- ¿Se recopilan datos? **Sí**.
- Tipos, todos **vinculados al usuario**, **sin rastreo**, finalidad **Funcionalidad de la app**:
  - Información de contacto → Nombre, Correo electrónico.
  - Contenido del usuario → Otro contenido del usuario (cuadros, notas, asistencia).
  - Identificadores → ID de usuario.
- Clasificación por edad: **4+**. Categoría: **Educación** (o Productividad).
- *Sign in with Apple*: no aplica (no hay inicio de sesión con terceros).

## Google Play Console — Seguridad de los datos

- ¿Recopila o comparte datos? Recopila: **Sí**. Comparte: **No**.
- Cifrado en tránsito: **Sí**. El usuario puede pedir que se borren: **Sí** (URL de arriba).
- Datos: Información personal → Nombre, Correo (obligatorio, funcionalidad y gestión de
  cuenta). Archivos y documentos / Otro contenido → cuadros y notas (funcionalidad).
- Público objetivo: **18 años o más** (docentes). La app no está dirigida a niños.
- Anuncios: **No**. Clasificación de contenido: cuestionario IARC → Todos.

## Antes de enviar

1. Cambiar la contraseña de la cuenta demo en producción (la del README es pública).
2. Crear la cuenta de revisión.
3. Android: keystore de release y `flutter build appbundle --dart-define-from-file=env/prod.json`
   (ver `docs/despliegue.md`). Decidir el `applicationId` definitivo antes del primer envío:
   no se puede cambiar después.
4. iOS: `flutter build ipa --dart-define-from-file=env/prod.json` y subir con Transporter o
   Xcode → Organizer. El equipo de firma ya es el de pago (3B4RXN8W7G).
5. Capturas: teléfono 6.7" y 5.5" (Apple), teléfono y tablet 7"/10" (Google).
