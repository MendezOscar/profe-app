# Despliegue: Render + Aiven + Cloudflare Pages + APK

Todo con planes gratis, sin servidor propio:

| Pieza | Servicio | Límite del plan gratis |
|---|---|---|
| API (.NET) | **Render** | 512 MB; se duerme tras 15 min sin tráfico |
| PostgreSQL | **Aiven** | 1 GB, 1 CPU; no se suspende, pero puede apagarse tras mucho tiempo sin uso |
| App web (Flutter) | **Cloudflare Pages** | ancho de banda ilimitado; 500 builds al mes |
| App Android | **APK firmado** | se reparte a mano mientras no haya cuenta de Play Store |

Cómo encaja el sueño de Render con el uso: la app funciona sin servidor. Capturar, importar y guardar pasa en el teléfono; lo único que necesita la API es la sincronización (se reintenta sola) y la exportación. Si la API está dormida, la primera petición tarda de 30 a 60 segundos en despertarla y después responde normal.

## 1. Aiven (PostgreSQL)

1. Crear una cuenta en [aiven.io](https://aiven.io) → *Create service* → **PostgreSQL**, plan **Free**.
2. Elegir la región gratuita más cercana a Render (Virginia, US East). Si el plan gratis no ofrece esa región, tomar otra de EE. UU.: cada consulta paga la distancia.
3. Cuando el servicio esté *Running*, copiar de *Overview → Connection information* el **host, puerto, usuario (`avnadmin`), contraseña y base (`defaultdb`)**. El puerto no es 5432: Aiven asigna uno propio.
4. Usar la **conexión directa**, no la de *Connection pools* (PgBouncer): en modo transacción rompe el *advisory lock* que EF Core usa para migrar.
5. Armar la cadena en formato Npgsql. El pool es chico porque el plan gratis limita las conexiones simultáneas:

```
Host=pg-xxxx-proyecto.l.aivencloud.com;Port=12345;Database=defaultdb;Username=avnadmin;Password=CLAVE;SSL Mode=Require;Trust Server Certificate=true;Maximum Pool Size=10
```

Aiven exige SSL. `Trust Server Certificate=true` acepta su certificado sin instalar la CA. Para validarlo del todo, descargar el *CA certificate* del panel y usar `SSL Mode=VerifyFull;Root Certificate=/ruta/ca.pem` (en Render habría que agregar el archivo como *Secret File*).

En *Overview → Allowed IP addresses* hay que dejar `0.0.0.0/0`, que es lo que viene por defecto: Render no tiene IP fija en el plan gratis, así que no se puede restringir a su IP. La protección queda en el SSL y en la contraseña.

Notas del plan gratis:
- **Respaldos:** revisar en el panel qué respaldos trae el plan. Si no incluye, programar un `pg_dump` periódico: son datos de menores y no se deben perder.
- **Inactividad:** Aiven puede apagar un servicio gratis tras un periodo largo sin uso y avisa por correo antes. Con docentes sincronizando a diario no debería pasar. Si pasa, se enciende desde el panel sin perder datos.
- **Límites:** 1 GB alcanza de sobra. Un cuadro con sus notas pesa decenas de KB, así que caben miles de clases.

## 2. Render (API)

El repositorio trae un blueprint ([render.yaml](../render.yaml)). En Render: *New* → *Blueprint* → elegir el repositorio. Crea el servicio `profeapp` con Docker, raíz en `backend/`, plan free y el health check en `/health/live`.

Antes del primer deploy, cargar los dos secretos en *Environment*:

| Variable | Valor |
|---|---|
| `ConnectionStrings__Default` | la cadena de Aiven del paso 1 |
| `Jwt__Key` | `openssl rand -base64 48` |

`App__ApplyMigrationsOnStartup=true` crea el esquema en el primer arranque.

**Cuentas:** la app no tiene registro público y la API no expone `/auth/register`. Por ahora se entra con el docente demo, que se crea con `App__SeedDemoData=true` (ya configurada en Render). La variable no se quita: si el usuario ya existe, no hace nada. El alta de docentes reales está por definir.

Si la web se publica en otro dominio que no sea `profeapphn.com`, hay que cambiar `App__CorsOrigins__0` por ese dominio exacto, sin barra final.

## 3. Cloudflare Pages (web)

Pages compila la web desde GitHub en cada push a `main`. Su imagen no trae Flutter: lo instala [scripts/cloudflare-build.sh](../scripts/cloudflare-build.sh).

En Cloudflare: *Workers & Pages* → *Create* → *Pages* → *Connect to Git* → `MendezOscar/profe-app`:

| Campo | Valor |
|---|---|
| Project name | `profe-app` (queda en `https://profe-app.pages.dev`, que redirige a `https://profeapphn.com`) |
| Production branch | `main` |
| Framework preset | `None` |
| Build command | `bash scripts/cloudflare-build.sh` |
| Build output directory | `mobile/build/web` |
| Root directory | vacío (raíz del repo) |
| Environment variables | `API_BASE_URL` = `https://api.profeapphn.com` |

El primer build tarda unos minutos porque baja Flutter. Para no recompilar la web con cambios que sólo tocan el backend: *Settings → Build → Build watch paths* → incluir `mobile/*`, `scripts/*` y `site/*` (la landing).

El build deja la landing y las páginas legales (`site/`) en la raíz y el panel en `/app/`. El enrutado lo hace [site/_worker.js](../site/_worker.js): las rutas de `/app/` sin extensión devuelven el `index.html` del panel, y los enlaces viejos de la raíz (`/inicio`, `/login`…) redirigen a `/app/…`.

**CORS:** la API sólo acepta al navegador desde `App__CorsOrigins__0`, que en [render.yaml](../render.yaml) es `https://profeapphn.com`. Si el dominio cambia, hay que actualizar esa variable en Render.

**Dominio:** `profeapphn.com` está registrado en Cloudflare. El sitio es un *Custom domain* del proyecto de Pages (`profeapphn.com` y `www`, que el worker redirige al dominio sin www). La API es un *Custom Domain* de Render (`api.profeapphn.com`, CNAME a `profeapp-o7hw.onrender.com` sin proxy de Cloudflare).

## 4. APK de Android

### Keystore (una sola vez)

**Guardarlo muy bien.** Si se pierde el keystore, los docentes tienen que desinstalar la app, y perder lo que no se haya sincronizado, para poder instalar una versión nueva.

```bash
keytool -genkey -v -keystore ~/profeapp-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias profeapp
```

Crear `mobile/android/key.properties` (está en `.gitignore`):

```properties
storePassword=<la clave del keystore>
keyPassword=<la clave de la llave>
keyAlias=profeapp
storeFile=/Users/<usuario>/profeapp-upload.jks
```

Respaldar el `.jks` y las claves fuera de la máquina, por ejemplo en un gestor de contraseñas.

### Compilar

```bash
cd mobile
flutter build apk --release --dart-define-from-file=env/prod.json
# build/app/outputs/flutter-apk/app-release.apk
```

Sin `key.properties` el build firma con la llave de debug. Ese APK sirve para probar, pero no para repartir: las actualizaciones firmadas con la llave real no se instalarían encima.

Antes de cada versión nueva, subir `version:` en `mobile/pubspec.yaml`. El número después del `+` debe crecer siempre.

## Verificación

```bash
curl https://api.profeapphn.com/health/live   # sin base
curl https://api.profeapphn.com/health        # con base: "Healthy" si Aiven responde
```

Después, en la web o en el APK:
1. Entrar con el docente demo.
2. Importar un cuadro.
3. Capturar una nota.
4. Ver la nube en "respaldado".
5. Entrar con el mismo usuario en otro dispositivo y ver la clase.
6. Exportar el cuadro.

## 6. Cuentas: plataforma, centros y docentes

No hay registro público. Las cuentas se crean desde los paneles, con contraseña temporal que se cambia al entrar:

- **Plataforma** (quien opera ProfeApp): se crea al arrancar la API si existen estas variables en Render (secretas, `sync: false`):
  - `App__PlatformAdmin__Email`
  - `App__PlatformAdmin__Password` (mínimo 8, con mayúscula, minúscula y número)
  - `App__PlatformAdmin__Name` (opcional)

  Entrando con esa cuenta se abre el panel **Plataforma**: crear centros (plan, cupo, vencimiento y su administrador) y cuentas de docentes del plan personal.
- **Administrador de centro**: su panel **Centro** da de alta docentes dentro del cupo, los desactiva o reactiva y les restablece la contraseña. Ve el avance de cada docente, no sus notas.
- **Licencia vencida o suspendida**: los docentes del centro no pueden entrar ni renovar sesión.

## 7. Límites y mantenimiento

- **Límites de peticiones** (Program.cs): login 10 por minuto por IP; sync unas 120 por
  minuto por docente (ráfagas de 240); exportar, 4 a la vez para toda la API
  (`App__ExportacionesSimultaneas`) y el resto espera turno.
- **Limpieza diaria** (`LimpiezaService`): sesiones vencidas o rotadas hace más de 7 días, y
  lápidas (borrados ya propagados) de más de 120 días.
- **Al crecer**: Render Starter o superior (sin dormirse, más memoria) y Postgres de pago.
  Con muchos docentes, particionar `registros` por año lectivo.


## 8. Seguridad del sitio y la API

- **CSP**: `site/_worker.js` manda la política del sitio y la del panel (`/app/`). Si cambia
  la URL de la API, actualizar la constante `API` del worker además de `env/prod.json`, o el
  panel no podrá conectarse. El panel no admite scripts en línea: todo va en archivos
  (por eso `web/arranque.js`).
- **CORS**: sólo los orígenes de `App__CorsOrigins__N` (hoy `https://profeapphn.com`),
  sin cookies: el token va en el encabezado `Authorization`.
- **Bloqueo de cuenta**: 10 contraseñas equivocadas seguidas bloquean la cuenta 15 minutos
  (login, cambiar contraseña y eliminar cuenta), además del límite por IP del login.

## 9. Cobro

Se opera desde el panel de **Plataforma** (pestañas Docentes y Centros, menú ⋯ de cada cuenta):
registrar pago, plan y vencimiento, reponer contraseña y suspender.

- **A quién se cobra**: al docente del plan personal (en su espacio, `tenants`) o al centro
  (`instituciones`). Los docentes de un centro no tienen cobro propio.
- **Planes del docente** por secciones (cada clase importada es una asignatura en una sección):
  Básico hasta 3, Docente hasta 8, Plus sin tope
  (`NivelesDocente`). Sin nivel no hay tope (demo, revisión, cortesía).
- **Vencimiento**: sin «pagado hasta» la cuenta nunca vence. Siete días antes se avisa; vencida
  corren los días de gracia; después, **sólo lectura**: entra, ve y exporta, pero `/sync/push`
  responde 409 `solo_lectura` y lo del teléfono queda pendiente hasta que se registre el pago.
- **Tope**: una sección nueva por encima del plan no se importa en la app y el servidor la
  rechaza con 409 `tope_asignaturas`. Las que ya tiene siguen respaldándose.
- **Suspender** es otra cosa: nadie de la cuenta entra y se cierran sus sesiones.
- **Registrar pago** suma los meses al vencimiento que ya tenía (no a hoy); cada pago queda en
  `pagos` con hasta dónde dejó pagado. El estado del plan vive 5 minutos en memoria, salvo al
  registrar un pago o cambiar el plan, que lo renuevan al instante.
