# Publicar en las tiendas

- **App Store**: [app-store.md](app-store.md): ficha, notas para el revisor, privacidad, video.
- **Google Play**: [play-store.md](play-store.md): ficha, declaraciones, seguridad de los datos,
  prueba cerrada y acceso a producción.

Aquí va lo que comparten las dos.

## URL que piden las tiendas

| Para | URL |
| --- | --- |
| Sitio / marketing | https://profeapphn.com/ |
| Política de privacidad | https://profeapphn.com/privacidad |
| Términos de uso | https://profeapphn.com/terminos |
| Soporte | https://profeapphn.com/soporte |
| Eliminación de cuenta (Google Play) | https://profeapphn.com/eliminar-cuenta |
| Correo de contacto | soporte@profeapphn.com |

El sitio se arma con `scripts/cloudflare-build.sh`: `site/` va a la raíz y el panel Flutter a
`/app/`, enrutados por `site/_worker.js`. Son estáticas: abren aunque la API esté dormida.

## Qué cumple la app

- **Eliminar la cuenta desde la app**, en los dos tipos de cuenta que ve el revisor: docente
  (Cuenta → Eliminar mi cuenta) y administrador de centro (menú de la cuenta → Eliminar mi
  cuenta). Pide la contraseña y borra en el momento (`POST /api/v1/auth/delete-account`). La de
  plataforma no se elimina por esa vía: ve los datos de todos.
- **Privacidad, términos y ayuda dentro de la app**: en el login, en Cuenta y en el menú de los
  paneles de administración.
- **Sin rastreo, publicidad ni SDK de terceros**: no hace falta App Tracking Transparency.
- **Notificaciones locales, no push**: el recordatorio lo programa el teléfono; no hay
  Firebase ni APNs.
- **Cifrado**: solo HTTPS. `ITSAppUsesNonExemptEncryption = false` en `Info.plist`.
- **Sin registro público ni compras**: las cuentas las da ProfeApp o el centro. Nada que comprar
  en la app ni en la ficha (ver la regla 3.1 en [app-store.md](app-store.md)).
- **Aviso de independencia**: «no está afiliado ni respaldado por la Secretaría de Educación ni
  por SACE», en las dos descripciones y en el pie del sitio.

## Cuentas de revisión

Las dos tiendas entran con estas cuentas, **en producción** (a donde apunta el binario):

| Cuenta | Cómo se crea | Datos |
| --- | --- | --- |
| Docente de revisión | Plataforma → Nueva cuenta de docente | Un cuadro ficticio (`mobile/test/fixtures/cuadro_basica.xls`) con tres parciales cerrados y el cuarto en curso |
| Administrador de centro de revisión | Plataforma → Nuevo centro («Centro de Revisión», plan pequeño, sin vencimiento) | Con el docente de revisión dado de alta en su centro |

- **No usar la cuenta demo** (`docente@demo.hn`): la usa el equipo, y cualquier prueba suya
  cambia lo que ve el revisor.
- Al entrar por primera vez piden cambiar la contraseña temporal: cambiarla antes de dar las
  credenciales, o el revisor se topa con esa pantalla.
- Las contraseñas van en `CREDENCIALES.local.md` y en los formularios de las tiendas, nunca en el
  repositorio, que es público.
- **Si el revisor elimina una**, volver a crearla igual antes de responderle.
- El centro de revisión **sin fecha de vencimiento**, para que la licencia no se venza a media
  revisión.

## Capturas

En `docs/tiendas/capturas/`, **fuera del repositorio** (`.gitignore`): muestran nombres e
identidades de alumnos de la cuenta demo. Si esos datos son ficticios, se pueden versionar
quitando la línea del `.gitignore`; si no, hay que rehacerlas con la cuenta de revisión, que sí
usa el cuadro ficticio.

| Carpeta | Medida | Para |
| --- | --- | --- |
| `iphone-6.9/` | 1320 × 2868 | App Store, iPhone |
| `ipad-13/` | 2064 × 2752 | App Store, iPad (obligatorio) |
| `android-telefono/` | 1080 × 2400 | Google Play |

Se toman del panel web (la misma app Flutter) con Chrome a esas medidas y a 2× o 3×, entrando
con la cuenta y navegando por las rutas de cada pantalla. No llevan barra de estado del
teléfono, que las tiendas no exigen.

## Estado (30 de septiembre de 2026)

| Paso | Estado |
| --- | --- |
| Versión `1.0.0+1`, `.aab` y `.ipa` firmados | Hecho |
| Fichas, notas para el revisor, privacidad, seguridad de los datos | Escritas en los dos documentos |
| Icono 512 y gráfico destacado de Play | En `docs/tiendas/play-store/` |
| Capturas de iPhone, iPad y Android | Hechas con la cuenta demo (ver arriba) |
| Contraseña de la cuenta demo cambiada | Hecho |
| Cuentas de revisión en producción | **Falta**: necesita la cuenta de plataforma |
| Video en el iPhone para Apple | **Falta** |
| Cuenta de Play Console y prueba cerrada de 14 días | **Falta** |
