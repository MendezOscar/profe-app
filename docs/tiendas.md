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

## Notificaciones

El recordatorio de las 5 p. m. es una **notificación local**: la programa el teléfono con lo
que ya tiene guardado, no pasa por un servidor ni usa push de Apple o Firebase.

- No cambia las respuestas de privacidad: no se recopila nada nuevo.
- iOS: no hace falta el *capability* de Push Notifications. El permiso se pide sólo cuando el
  docente activa el recordatorio en Avisos.
- Android: declara `POST_NOTIFICATIONS` (Android 13+, se pide en el mismo momento) y
  `RECEIVE_BOOT_COMPLETED` (para que el recordatorio siga programado tras reiniciar). No usa
  alarmas exactas, así que no hay que llenar la declaración de `SCHEDULE_EXACT_ALARM`.

## Ficha de la tienda (español, Latinoamérica)

- **Nombre**: ProfeApp
- **Subtítulo (Apple, 30)**: Notas y asistencia para SACE
- **Descripción corta (Google, 80)**: Califica, pasa lista y llena tu cuadro de SACE, aunque no tengas internet.
- **Palabras clave (Apple, 100)**: sace,notas,calificaciones,asistencia,docente,maestro,honduras,cuadro,rubrica,parcial
- **Categoría**: Educación. Secundaria (Apple): Productividad.
- **Texto promocional (Apple, 170)**: Importa tus cuadros de SACE, califica por puntos con tu rúbrica, pasa lista y exporta el cuadro listo para subir. Funciona sin internet.

**Descripción**:

> ProfeApp es la libreta de notas del docente hondureño, hecha para trabajar con los cuadros
> de SACE.
>
> • Importa los cuadros de SACE de todas tus asignaturas a la vez.
> • Arma una rúbrica de evaluación por puntos (tareas, trabajos, proyectos, exámenes) y
>   reutilízala en todas tus secciones.
> • Califica alumno por alumno con el teclado numérico, o varias actividades de una sola vez.
> • Pasa lista en segundos: todos presentes y marcas sólo a los que faltan.
> • Cierra el parcial: ProfeApp suma los puntos y las faltas y llena NOTA TOTAL e
>   INASISTENCIAS en el cuadro, listo para cargarlo en SACE.
> • Estadísticas por parcial: promedio, alumnos en riesgo, rendimiento por rubro, entregas,
>   asistencia y evolución de parcial a parcial.
> • Avisos de lo pendiente: lo que falta calificar, la lista de hoy, el parcial por cerrar
>   y el cuadro por exportar, con un recordatorio diario opcional.
> • Funciona sin internet. Cuando hay señal, respalda todo y lo sincroniza con la web y tus
>   otros dispositivos.
>
> Las cuentas las entrega ProfeApp o la administración de tu centro educativo. Planes y
> contacto en profe-app.pages.dev.

**Novedades de la versión 1.0.0**: Primera versión.

## Estado del envío

Hecho:

- Versión `1.0.0+1` en `mobile/pubspec.yaml`. Identificador `hn.profeapp.profeapp` en las dos
  tiendas (queda fijo con el primer envío).
- Android: llave de subida en `~/profeapp-upload.jks`, clave en `CREDENCIALES.local.md` y
  `mobile/android/key.properties` (ninguno se sube al repo). **Respaldar el `.jks` fuera de
  la Mac.** Con *Play App Signing* (lo propone Google al crear la app), si se pierde la llave
  de subida se puede pedir otra a Google; sin él, no.
- Compilados: `flutter build appbundle --release --dart-define-from-file=env/prod.json` →
  `build/app/outputs/bundle/release/app-release.aab`, y
  `flutter build ipa --release --dart-define-from-file=env/prod.json` → `build/ios/ipa/profeapp.ipa`.

Falta (en las consolas, con la cuenta de cada tienda):

1. Cambiar la contraseña de la cuenta demo en producción (la del README es pública).
2. Crear la cuenta de revisión desde el panel de plataforma y cargarle datos de ejemplo.
3. Apple: crear la app en App Store Connect con el bundle `hn.profeapp.profeapp`, subir el
   `.ipa` con Transporter, llenar privacidad, ficha y cuenta de revisión, y enviar.
4. Google: crear la app en Play Console, aceptar Play App Signing, subir el `.aab` a
   *Prueba interna* primero, llenar Seguridad de los datos, clasificación, público objetivo,
   acceso a la app (cuenta de revisión) y la ficha. Las cuentas personales nuevas de Google
   Play deben hacer una prueba cerrada con 12 testers durante 14 días antes de producción.
5. Capturas:
   - Apple: iPhone 6.9" (1320×2868) e iPad 13" (2064×2752): la app también corre en iPad.
   - Google: teléfono (mínimo 2) y, opcional, tablet 7" y 10". Ícono 512×512 y gráfico de
     funciones 1024×500.
