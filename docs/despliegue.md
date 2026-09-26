# Despliegue: Render + Neon + Cloudflare Pages + APK

Todo con planes gratis, sin servidor propio:

| Pieza | Servicio | Límite del plan gratis |
|---|---|---|
| API (.NET) | **Render** | 512 MB; se duerme tras 15 min sin tráfico |
| PostgreSQL | **Neon** | 0.5 GB; se suspende cuando queda inactiva |
| App web (Flutter) | **Cloudflare Pages** | ancho de banda ilimitado |
| App Android | **APK firmado** | se reparte a mano mientras no haya cuenta de Play Store |

Cómo encaja el sueño de Render con el uso: la app funciona sin servidor. Capturar, importar y guardar pasa en el teléfono; lo único que necesita la API es la sincronización (se reintenta sola) y la exportación. Si la API está dormida, la primera petición tarda de 30 a 60 segundos en despertarla y después responde normal.

## 1. Neon

1. Crear un proyecto en [neon.tech](https://neon.tech), en la región `us-east`, la misma de Render.
2. Copiar la cadena de conexión del endpoint **directo**, no el que dice `-pooler`: el pooler (PgBouncer en modo transacción) rompe el *advisory lock* que EF Core usa para migrar.
3. Pasarla a formato Npgsql, con un pool chico:

```
Host=ep-xxxx.us-east-2.aws.neon.tech;Database=profeapp;Username=USUARIO;Password=CLAVE;SSL Mode=Require;Trust Server Certificate=true;Maximum Pool Size=10
```

## 2. Render (API)

El repositorio trae un blueprint ([render.yaml](../render.yaml)). En Render: *New* → *Blueprint* → elegir el repositorio. Crea el servicio `profeapp` con Docker, raíz en `backend/`, plan free y el health check en `/health/live`.

Antes del primer deploy, cargar los dos secretos en *Environment*:

| Variable | Valor |
|---|---|
| `ConnectionStrings__Default` | la cadena de Neon del paso 1 |
| `Jwt__Key` | `openssl rand -base64 48` |

`App__ApplyMigrationsOnStartup=true` crea el esquema en el primer arranque. Para tener el docente demo en producción, agregar `App__SeedDemoData=true` en el primer deploy y quitarlo después.

Si la web se publica en otro dominio que no sea `profeapp.pages.dev`, hay que cambiar `App__CorsOrigins__0` por ese dominio exacto, sin barra final.

## 3. Cloudflare Pages (web)

Automático con [deploy-web.yml](../.github/workflows/deploy-web.yml) en cada push a `main` que toque `mobile/`. En *Settings → Secrets and variables → Actions* del repositorio:

| Tipo | Nombre | Valor |
|---|---|---|
| Variable | `API_BASE_URL` | `https://profeapp.onrender.com` |
| Secreto | `CLOUDFLARE_API_TOKEN` | token con permiso *Cloudflare Pages: Edit* |
| Secreto | `CLOUDFLARE_ACCOUNT_ID` | id de la cuenta |

El proyecto `profeapp` se crea en Pages la primera vez que corre el workflow. A mano:

```bash
cd mobile
flutter build web --release --dart-define-from-file=env/prod.json
npx wrangler pages deploy build/web --project-name profeapp --branch main
```

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
curl https://profeapp.onrender.com/health/live   # sin base
curl https://profeapp.onrender.com/health        # con base: "Healthy" si Neon responde
```

Después, en la web o en el APK:
1. Crear una cuenta.
2. Importar un cuadro.
3. Capturar una nota.
4. Ver la nube en "respaldado".
5. Entrar con la misma cuenta en otro dispositivo y ver la clase.
6. Exportar el cuadro.
