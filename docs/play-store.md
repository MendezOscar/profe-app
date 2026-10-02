# Publicar en Google Play

Lo mismo que [app-store.md](app-store.md) pero para Play. Lo común (URL, cuentas de revisión,
capturas) está en [tiendas.md](tiendas.md). Sale de lo aprendido con GarajApp, que pasó la prueba
cerrada y el acceso a producción en septiembre de 2026.

## La cuenta y el calendario

**US$25, pago único**, con verificación de identidad.

> **La trampa de calendario.** Una cuenta **personal** nueva no puede publicar en producción de
> entrada: Google pide una **prueba cerrada con 12 probadores que se mantengan 14 días seguidos**
> y después se solicita el acceso. Con una cuenta de organización no aplica, pero pide número
> D-U-N-S. Si la cuenta de Garaj ya tiene acceso a producción, **no** se hereda: la regla es por
> app nueva en cuentas personales creadas después de noviembre de 2023. Confirmarlo en Play
> Console al crear la app.

Los 14 días cuentan desde que hay **12 probadores aceptados**, no desde que se publica la versión,
y hasta que Google libera la revisión de la prueba cerrada el enlace dice «App not available» y
no registra aceptaciones: no repartirlo antes. Lo que dejó Garaj:

- Los probadores usan **cuentas de docente aparte**, no las de revisión: doce personas dejan
  desorden y la de revisión es la que abre el revisor.
- Subir versiones nuevas al canal cerrado **no reinicia** los 14 días; perder probadores sí.
- Vigilar «Usuarios con la app instalada»: doce aceptaciones con dos instalaciones se ve mal
  cuando pidan cuentas de la prueba.
- Anotar día a día lo que reportan: de ahí salen las respuestas para pedir el acceso (abajo).

Para ProfeApp los doce probadores naturales son docentes conocidos con Android, con un cuadro
de SACE propio o el de ejemplo.

## Ficha de la app

| Campo | Valor |
| --- | --- |
| Nombre (30) | `ProfeApp — Notas y asistencia` |
| **Descripción corta (80)** | `Califica, pasa lista y llena tu cuadro de SACE, aunque no tengas internet.` (74) |
| Categoría | Educación · etiquetas: educación, productividad |
| Correo de contacto | `soporte@profeapphn.com` |
| Teléfono de contacto | `+504 9824 2108` |
| Sitio web | `https://profeapphn.com` |
| Política de privacidad | `https://profeapphn.com/privacidad` |
| Anuncios | No contiene anuncios |
| Compras dentro de la app | No |

La descripción corta sale bajo el nombre y **se indexa**: nombra lo que el docente busca
(calificar, lista, SACE).

### Descripción completa (4000)

La de la App Store con un párrafo más al final, porque Play **indexa este campo**:

```
ProfeApp es la libreta de notas del docente hondureño, hecha para trabajar con los cuadros que
descargas de SACE: calificaciones por puntos, asistencia y cierre del parcial desde el teléfono.

TUS CUADROS, EN EL TELÉFONO
· Importa los cuadros de todas tus asignaturas a la vez, tal como los descargas de SACE.
· Tus alumnos quedan listos y trabajas aunque no haya internet.

CALIFICA POR PUNTOS
· Arma una rúbrica de evaluación (tareas, trabajos, proyectos, exámenes) y reutilízala en todas
  tus secciones.
· Califica alumno por alumno con el teclado numérico, o varias actividades de una sola vez.

PASA LISTA EN SEGUNDOS
· Todos presentes de entrada: marcas solo a los que faltan, llegan tarde o justifican.

CIERRA EL PARCIAL
· ProfeApp suma los puntos y las faltas y llena NOTA TOTAL e INASISTENCIAS en el cuadro.
· Exportas el archivo listo para cargarlo en SACE.

SABE CÓMO VA TU GRUPO
· Promedio, alumnos en riesgo, rendimiento por rubro, entregas y asistencia de cada parcial.
· La evolución de cada alumno de parcial a parcial.

NO SE TE PASA NADA
· Avisos de lo que falta calificar, la lista de hoy, el parcial por cerrar y el cuadro por
  exportar, con un recordatorio diario opcional.

SIN INTERNET
· Todo se guarda en el teléfono. Cuando hay señal, se respalda y se sincroniza con la web y tus
  otros dispositivos.

PARA QUIÉN ES
· Docentes de educación media y básica que llenan cuadros de SACE.
· Centros educativos que quieren dar la herramienta a todo su personal.

Las cuentas las entrega ProfeApp o la administración de tu centro educativo.

ProfeApp es un servicio independiente: no está afiliado ni respaldado por la Secretaría de
Educación de Honduras ni por SACE.
```

El último párrafo no es opcional: la política de **suplantación** de Play pide aclarar que no se
representa a un gobierno cuando la app trabaja con algo oficial.

## Gráficos

| Pieza | Medida | Archivo |
| --- | --- | --- |
| Icono | 512 × 512 PNG, a sangre | [`tiendas/play-store/icono-512.png`](tiendas/play-store/icono-512.png) (el del kit de marca) |
| Gráfico destacado | 1024 × 500, sin transparencia | [`tiendas/play-store/destacado-1024x500.png`](tiendas/play-store/destacado-1024x500.png) |
| Capturas de teléfono | 1080 × 2400, mínimo 2 | `tiendas/capturas/android-telefono/` (las 7, en orden) |

El icono va a sangre (cuadrado azul completo): Play le pone su propia máscara redondeada. El
gráfico destacado deja el texto a la izquierda y las pantallas a la derecha, lejos de los bordes
que Play recorta en algunos tamaños.

Las capturas de iPhone no sirven aquí: se notan de iPhone.

## Acceso a la app (credenciales del revisor)

**App content → App access** → «Todas o algunas funciones están restringidas»:

```
Nombre: Cuenta de revisión (docente)
Usuario: <correo de la cuenta de revisión docente>
Contraseña: <contraseña>

No hay registro público: las cuentas las crea ProfeApp o el administrador de un centro
educativo. Esta cuenta de docente tiene una asignatura de ejemplo (Química, 20 alumnos
ficticios) con tres parciales cerrados y el cuarto en curso.

Nombre: Cuenta de revisión (administrador de centro)
Usuario: <correo de la cuenta de revisión del centro>
Contraseña: <contraseña>

Ve y administra los docentes de su centro.
```

## Contenido de la app (las declaraciones)

| Declaración | Respuesta |
| --- | --- |
| Política de privacidad | `https://profeapphn.com/privacidad` |
| Anuncios | No |
| Acceso a la app | Arriba |
| Clasificación de contenido | Cuestionario IARC, abajo |
| Público objetivo | **18 años o más**. La app es para docentes, no está dirigida a niños |
| App de noticias | No |
| Seguridad de los datos | Abajo |
| Apps gubernamentales | **No** (no la desarrolla ni la encarga un gobierno) |
| Funciones financieras | Ninguna |
| Salud | No |
| ID de publicidad | **No se usa** (no hay anuncios ni analítica) |

> El público objetivo es lo que más cuesta corregir después: si se marca cualquier edad menor
> de 13, la app entra en la política de Familias. Los alumnos aparecen como datos que maneja el
> docente, no como usuarios.

### Clasificación de contenido (IARC)

Categoría: **Utilidades, productividad, comunicación u otro**. Todas las respuestas «No»:

| Pregunta | Respuesta |
| --- | --- |
| Violencia, sangre, lenguaje, sexo | No |
| Drogas, alcohol, tabaco | No |
| Apuestas, reales o simuladas | No |
| Contenido generado por usuarios que se comparta con otros | **No**: las notas solo las ve el docente (y su centro si es institucional) |
| Comparte la ubicación | No |
| Permite comprar bienes digitales | No |

Resultado esperado: para todo público.

## Seguridad de los datos

Google cruza lo declarado con lo que hace la app; una declaración falsa es motivo de
suspensión.

| Tipo (Google) | Qué es | ¿Se recoge? | ¿Se comparte? | Para qué | ¿Obligatorio? |
| --- | --- | --- | --- | --- | --- |
| Información personal → Nombre | Del docente y de los alumnos del cuadro | Sí | No | Funcionalidad de la app, gestión de la cuenta | Sí |
| Información personal → Dirección de correo | De la cuenta | Sí | No | Funcionalidad, gestión de la cuenta | Sí |
| Información personal → ID de usuario | Id interno de la cuenta | Sí | No | Funcionalidad, gestión de la cuenta | Sí |
| Información personal → Otra información | Número de identidad de los alumnos, que viene en el cuadro | Sí | No | Funcionalidad | Sí |
| Archivos y documentos | El cuadro de SACE (Excel) | Sí | No | Funcionalidad | Sí |
| Ubicación, contactos, mensajes, fotos, audio, salud, finanzas, actividad, ID del dispositivo | — | No | — | — | — |

Las tres preguntas generales:

- **¿Se cifra en tránsito?** Sí, todo va por HTTPS.
- **¿Se pueden borrar los datos?** Sí, desde la app (Cuenta → Eliminar mi cuenta) y por web.
- **URL para pedir que se borren:** `https://profeapphn.com/eliminar-cuenta`

«Compartir» en Google es entregar datos a otra empresa para sus propios fines. Render, Aiven y
Cloudflare solo procesan por cuenta de ProfeApp: no cuenta como compartir.

### Permisos que declara el `.aab`

| Permiso | Para qué |
| --- | --- |
| `INTERNET` | Respaldar y sincronizar |
| `POST_NOTIFICATIONS` | El recordatorio de pendientes, solo si el docente lo activa (se pide en ese momento) |
| `RECEIVE_BOOT_COMPLETED` | Que el recordatorio siga programado después de reiniciar el teléfono |

Ninguno es «sensible» y no llevan formulario. No usa alarmas exactas
(`SCHEDULE_EXACT_ALARM`), ni ubicación, cámara, contactos, SMS, accesibilidad ni acceso a todos
los archivos.

## La solicitud de acceso a producción

Después de los 14 días. El formulario tiene **tope de 300 caracteres por respuesta**. Borradores,
para ajustar con lo que de verdad pase en la prueba:

**Cómo se reclutó a los probadores**

> Docentes de secundaria conocidos, con su propio cuadro de SACE, que usaron la app en sus
> clases durante los 14 días: calificaron, pasaron lista y cerraron un parcial de prueba.

**Público objetivo**

> Docentes de secundaria de Honduras que llenan los cuadros de notas de SACE, y los centros
> educativos que les dan la herramienta. No es una app de consumo masivo: la usa quien da clases.

**Cómo ofrece valor**

> Reemplaza la libreta y la hoja de cálculo. El docente califica y pasa lista desde el teléfono,
> aunque no haya señal, y al cerrar el parcial la nota y las faltas quedan escritas en el cuadro
> listo para subir a SACE.

**Qué cambió con lo que dijeron** — llenar con los cambios reales de la prueba (Garaj: «23
cambios. Los principales: …»). Nombrar cambios concretos se lee como prueba de verdad.

**Cómo se decidió que está lista**

> Cuando la prueba dejó de encontrar fallos que impidieran trabajar. Antes de publicar corren
> las pruebas automáticas de la app y de la API y se recorre a mano el ciclo completo: importar,
> calificar, pasar lista, cerrar y exportar. Lo pendiente son mejoras. Saldrá escalonada.

**Instalaciones esperadas el primer año** — «entre 0 y 10,000», coherente con el público.

Mientras Google responde: no quitar probadores, no cerrar el canal, no subir versiones a ese
canal y no tocar la base de producción.

## Compilar y subir

```bash
cd mobile
flutter build appbundle --release --dart-define-from-file=env/prod.json
```

Sale en `build/app/outputs/bundle/release/app-release.aab`, firmado con la llave de subida
(`~/profeapp-upload.jks`, ver [despliegue.md](despliegue.md)).

- **Play App Signing**: aceptarlo al crear la app. Google guarda la llave final y la nuestra
  queda de llave de subida; si se pierde, Google puede cambiarla.
- **`versionCode` nuevo en cada subida**: el `+N` de `version:` en `mobile/pubspec.yaml`. Uno ya
  subido no se puede volver a usar en ningún canal, solo promover.
- Primero a **Prueba interna** (sin revisión, llega en minutos) para comprobar el binario, y de
  ahí se promueve a la prueba cerrada.

## Lista antes de mandar

- [ ] Cuenta de Play Console pagada y con identidad verificada.
- [ ] App creada (`hn.profeapp.profeapp`) y Play App Signing aceptado.
- [ ] Ficha: nombre, descripción corta y completa.
- [ ] Icono 512, gráfico destacado 1024 × 500 y las capturas de teléfono.
- [ ] Todas las declaraciones de Contenido de la app.
- [ ] Las dos cuentas de revisión entran **en producción**.
- [ ] `.aab` en Prueba interna, luego prueba cerrada con 12 probadores.
- [ ] 14 días cumplidos y acceso a producción solicitado.
