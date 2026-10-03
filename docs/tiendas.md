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
  en la app ni en la ficha (ver la regla 3.1 en [app-store.md](app-store.md)). El aviso de plan
  por vencer o vencido solo informa; el texto «Cómo pagar» que se fija en la plataforma se ve
  únicamente en la web (`kIsWeb`), nunca en la app de las tiendas.
- **Aviso de independencia**: «no está afiliado ni respaldado por la Secretaría de Educación ni
  por SACE», en las dos descripciones y en el pie del sitio.

## Cuentas de revisión

Las dos tiendas entran con estas cuentas, **en producción** (a donde apunta el binario):

| Cuenta | Cómo se crea | Datos |
| --- | --- | --- |
| Docente de revisión (`docentetiendas@pruebas.hn`, plan personal sin vencimiento) | Plataforma → Nueva cuenta de docente | QUÍMICA 10-1, QUÍMICA 10-2 y FÍSICA 11-1: cuadros ficticios (alumnos inventados, identidades `9999…`) con tres parciales cerrados y el cuarto en curso |
| Administrador de centro (`institutotiendas@pruebas.com`, «Instituto de pruebas») | Plataforma → Nuevo centro | Tres docentes ficticios (`@pruebas.hn`) con sus secciones y avance; pagado hasta el 31-12-2026 |

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

En `docs/tiendas/capturas/`, tomadas con la **cuenta de revisión** (`docentetiendas@pruebas.hn`):
alumnos, identidades (prefijo `9999`) y centro son inventados.

| Carpeta | Medida | Para |
| --- | --- | --- |
| `iphone-6.9/` | 1320 × 2868 | App Store, iPhone |
| `ipad-13/` | 2064 × 2752 | App Store, iPad (obligatorio) |
| `android-telefono/` | 1080 × 2400 | Google Play |

Se toman del panel web en producción (la misma app Flutter) con Chrome a esas medidas y a 2× o
3×, entrando con la cuenta de revisión y navegando por las rutas de cada pantalla. No llevan barra de estado del
teléfono, que las tiendas no exigen.

## Estado (2 de octubre de 2026)

| Paso | Estado |
| --- | --- |
| Versión `1.0.0+1`, `.aab` y `.ipa` firmados | Recompilados el 2 de octubre con todo lo último |
| Fichas, notas para el revisor, privacidad, seguridad de los datos | Escritas en los dos documentos |
| Icono 512 y gráfico destacado de Play | En `docs/tiendas/play-store/` |
| Capturas de iPhone, iPad y Android | Hechas con la cuenta de revisión, datos ficticios |
| Contraseña de la cuenta demo cambiada | Hecho |
| Cuentas de revisión en producción | Hechas y con datos ficticios (credenciales en `CREDENCIALES.local.md`) |
| Video en el iPhone para Apple | **Falta** |
| Cuenta de Play Console y prueba cerrada de 14 días | **Falta** |
