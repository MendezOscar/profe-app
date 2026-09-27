# ProfeApp

App para que el docente hondureño capture **notas e inasistencias sin internet** y exporte el cuadro de calificaciones **listo para subir a SACE**. La app no genera un formato propio: rellena el mismo archivo que el docente descarga de SACE y se adapta a los parciales y columnas que traiga (ver [docs/formato-sace.md](docs/formato-sace.md)).

| | |
|---|---|
| Backend | .NET 8 · Minimal APIs · EF Core 8 · Identity + JWT |
| Base de datos | PostgreSQL 15 (multi-tenant con filtro global; un tenant por docente) |
| App | Flutter 3.35 (Android · Web) · Riverpod · go_router |
| SACE | Sin integración directa: se importa y exporta el Excel oficial. Las credenciales de SACE nunca pasan por el servidor |

---

## Cómo levantarlo

```bash
# 1. Base de datos (Postgres en Docker, puerto 5436)
docker compose -f infra/docker-compose.yml up -d

# 2. Backend
cd backend
dotnet restore && dotnet build
cd src/ProfeApp.Api && ASPNETCORE_ENVIRONMENT=Development dotnet run
#    API      http://localhost:5081
#    Swagger  http://localhost:5081/swagger
#    Salud    http://localhost:5081/health

# 3. App (en otra terminal)
cd mobile
flutter pub get
flutter run -d chrome
```

En `Development` la API aplica migraciones y crea el docente demo al arrancar.

La app guarda clases y notas en una base local (sqflite) y funciona sin conexión. En web
usa `web/sqlite3.wasm` y `web/sqflite_sw.js`; si se actualiza `sqflite_common_ffi_web`, se
regeneran con `dart run sqflite_common_ffi_web:setup`.

Para agregar una migración:

```bash
cd backend
dotnet ef migrations add <Nombre> -p src/ProfeApp.Infrastructure -s src/ProfeApp.Api -o Persistence/Migrations
```

### Usuario de demostración

| Perfil | Correo | Contraseña |
|---|---|---|
| Docente | `docente@demo.hn` | `Demo1234!` |

Para apuntar la app al backend desplegado:

```bash
flutter run --dart-define-from-file=env/prod.json
flutter build apk --release --dart-define-from-file=env/prod.json
```

---

## Estructura

```
backend/
  src/ProfeApp.Domain/          entidades y reglas (sin dependencias)
  src/ProfeApp.Application/     casos de uso, DTOs y puertos
  src/ProfeApp.Infrastructure/  EF Core, Identity, seed
  src/ProfeApp.Api/             endpoints y autorización
  tests/                        integración (Testcontainers, Postgres real)
mobile/
  lib/core/                     api, auth, modelos, router, tema
  lib/core/sace/                lector del cuadro de SACE (.xlsx a nivel de XML)
  lib/core/local/               base local sqflite: clases, alumnos y notas offline
  lib/features/                 pantallas por área
brand/                          kit de marca (fuente de verdad de logos, colores e íconos)
infra/                          docker-compose de desarrollo
docs/                           formato SACE y referencias
```

## Sincronización

El teléfono es la fuente de verdad. Lo capturado se respalda en la API (`/api/v1/sync`)
al abrir la app, al volver la señal y unos segundos después de cada cambio. Entre dos
dispositivos del mismo docente, por celda gana la captura más nueva.

El plan de calificación (plantillas, rubros, actividades, notas, asistencia y cierre de
parciales) viaja como *registros* genéricos (`registros` en la base): el servidor guarda
el JSON sin interpretarlo y por fila gana el cambio más nuevo.

## Sitio público

`site/` es la landing con las páginas legales (privacidad, términos, cookies, soporte,
eliminar cuenta). En producción va en la raíz y el panel en `/app/`; al cerrar sesión en la
web se vuelve a la landing. Para publicar en las tiendas: [docs/tiendas.md](docs/tiendas.md).

## Despliegue

API en Render, base en Aiven, web en Cloudflare Pages y APK firmado: ver
[docs/despliegue.md](docs/despliegue.md).

## Pruebas

```bash
cd backend && dotnet test          # requiere Docker (Testcontainers)
cd mobile && flutter analyze && flutter test
```
