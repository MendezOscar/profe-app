# Publicar en la App Store

Para Google Play, ver [play-store.md](play-store.md): los límites de texto son otros y Play
tiene formularios que Apple no. Lo común a las dos (URL, cuentas de revisión) está en
[tiendas.md](tiendas.md).

Esto sale de lo aprendido con GarajApp (aprobada el 2 de septiembre de 2026 después de dos
rechazos «por información»): las respuestas que Apple pidió entonces ya van escritas en las
**Notas para el revisor**, para no esperar a que las pregunte.

## Ficha de la app

| Campo | Valor |
| --- | --- |
| Nombre (30) | `ProfeApp — Notas y asistencia` (29) |
| Subtítulo (30) | `Tu cuadro de SACE, sin papel` (28) |
| Categoría | Educación · secundaria: Productividad |
| Clasificación por edad | 4+ |
| Idioma principal | Español (México): es el más cercano a Honduras |
| Derechos de autor | `2026 Oscar Armando Cruz Mendez` (año y titular, sin ©) |
| URL de soporte | `https://profeapphn.com/soporte` |
| URL de marketing | `https://profeapphn.com/` |
| URL de política de privacidad | `https://profeapphn.com/privacidad` |
| Precio | Gratis |
| Disponibilidad | Honduras (el producto trabaja con SACE, que es de Honduras) |

«SACE» no va en el nombre a propósito: es el sistema de la Secretaría de Educación y en el
nombre se lee como app oficial. En el subtítulo y la descripción sí, con el aviso de que
ProfeApp es independiente.

Las cuatro URL son páginas estáticas de Cloudflare Pages: abren aunque la API de Render esté
dormida.

### Palabras clave (100, separadas por coma, sin espacios)

```
calificaciones,docente,maestro,profesor,honduras,rubrica,parcial,libreta,evaluacion,lista,colegio
```

97 caracteres. Sin repetir lo que ya está en el nombre o el subtítulo (notas, asistencia,
cuadro, SACE): Apple los indexa igual y repetirlos desperdicia espacio. Sin acentos.

### Texto promocional (menos de 170)

```
Importa tus cuadros de SACE, califica por puntos con tu rúbrica, pasa lista y cierra el parcial con la nota y las faltas ya escritas en el cuadro. Funciona sin internet.
```

169 caracteres. Se puede cambiar sin mandar la app a revisión.

### Descripción

```
ProfeApp es la libreta de notas del docente hondureño, hecha para trabajar con los cuadros que
descargas de SACE.

TUS CUADROS, EN EL TELÉFONO
· Importa los cuadros de todas tus asignaturas a la vez, tal como los descargas de SACE.
· Tus alumnos quedan listos y trabajas aunque no haya internet.

CALIFICA POR PUNTOS
· Arma una rúbrica de evaluación (tareas, trabajos, proyectos, exámenes) y reutilízala en todas
  tus secciones.
· Califica alumno por alumno con el teclado numérico, o varias actividades de una sola vez.

PASA LISTA EN SEGUNDOS
· Todos presentes de entrada: marcas solo a los que faltan, llegan tarde o justifican.
· Con tu horario, ves tus clases de hoy y la app te recuerda pasar lista los días que te toca.

RÚBRICAS OFICIALES
· Las tablas del Acuerdo 0158-SE-2025 para cada ciclo, listas para aplicar; la app recomienda la
  de tu grado.

TU PORTAFOLIO DOCENTE
· El PDF con el formato 2026: matrícula por edad y sexo, horario, rúbricas, tareas, cuadro de
  evaluaciones, notas y nivelación salen de lo que ya tienes en la app.

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

Las cuentas las entrega ProfeApp o la administración de tu centro educativo.

ProfeApp es un servicio independiente: no está afiliado ni respaldado por la Secretaría de
Educación de Honduras ni por SACE.
```

Sin «planes y precios en el sitio»: la regla 3.1.3(f) permite no usar compras dentro de la app
siempre que la app (y su ficha) no inviten a comprar por fuera.

### Novedades de esta versión

1.3.0 (compilación 13), la misma para Google Play (cabe en sus 500 caracteres):

```
• Horario: días, hora y aula de cada clase; tus clases de hoy y la lista según tu horario.
• Rúbricas oficiales del Acuerdo 0158 para cada ciclo, recomendadas según el grado.
• Portafolio docente en PDF con el formato 2026, armado con lo que ya tienes en la app.
• Plan Pro: plan y examen con el programa oficial de tu asignatura; presentación y nivelación del portafolio con IA.
• Mejoras y correcciones.
```

1.2.1 (compilación 12):

```
• Califica en tanda: toma los trabajos de toda la sección y mándalos juntos al asistente con IA; en unos minutos ves la nota sugerida junto a cada alumno y decides cuáles usar.
• Saldo mensual de créditos de IA: la app te dice cuánto te queda y cuánto usa cada función.
• Avisos más claros cuando el asistente no está disponible.
• Mejoras y correcciones.
```

1.2.0 (compilación 11):

```
Novedades para centros educativos y docentes:

• Gestión del centro: matrícula importada de SACE, secciones, horarios sin choques, excusas y permisos que el docente ve al pasar lista, incidencias disciplinarias, carnet estudiantil con foto, boletas, reportes y estadísticas de los docentes.
• App para las familias: notas, asistencia, horario, incidencias y comunicados del centro, con avisos al teléfono.
• Asistente con IA (plan Pro): sugiere el plan del parcial, genera exámenes con su clave, sugiere la nota de un trabajo desde una foto y redacta comentarios. Siempre propone; tú decides. No se envían nombres de alumnos.
• Mejoras y correcciones.
```

### Publicación

**Publicar automáticamente** al aprobarse. Puede tardar hasta 24 horas en aparecer.

## Encabezado y resultados de búsqueda (iOS 27)

Opcionales. Van en la página de la versión, en **Encabezado** y **Resultados de la búsqueda**,
con **Cargar**. Apple los revisa aparte y los acepta sin transparencia:

| Pieza | Medida | Archivo |
| --- | --- | --- |
| Encabezado | 3840 × 1646 (21:9) | [`tiendas/app-store/encabezado-3840x1646.png`](tiendas/app-store/encabezado-3840x1646.png) |
| Resultados de la búsqueda | 3840 × 2560 (3:2) | [`tiendas/app-store/resultados-busqueda-3840x2560.png`](tiendas/app-store/resultados-busqueda-3840x2560.png) |

Se generan con `node scripts/encabezado-app-store.mjs`. Muestran una sola idea, centrada, y no
llevan precios ni la dirección del sitio, que Apple no acepta en estas piezas.

## Capturas

Se suben las de `docs/tiendas/capturas-con-texto/` (con título encima; ver
[tiendas.md](tiendas.md#capturas)), hechas del panel con los datos de la cuenta de revisión:

| Carpeta | Medida | Para |
| --- | --- | --- |
| `iphone-6.9/` | 1320 × 2868 | iPhone 6,9": Apple escala para los demás iPhone |
| `ipad-13/` | 2064 × 2752 | iPad 13": **obligatorio**, la app también corre en iPad |

| # | Pantalla | Por qué esa |
| --- | --- | --- |
| 1 | Inicio | Lo urgente arriba, el promedio y quién va en riesgo |
| 2 | Calificar | Lo que más hace el docente: notas con el teclado numérico |
| 3 | Plan | La rúbrica por puntos que suma 100 |
| 4 | Pasar lista | Todos presentes y un toque por ausente |
| 5 | Estadísticas | Lo que convence: cómo va el grupo |
| 6 | Libro de notas | Un parcial cerrado, con las notas ya en el cuadro |
| 7 | Cuadro de SACE | El archivo que se sube a SACE (en iPad se ve entero) |

Se suben en ese orden; las tres primeras son las que se ven sin desplazar.

## Notas para el revisor (Información de revisión de la app → Notas)

Garaj se rechazó por la 2.1 con este campo vacío. Esto va completo desde el primer envío:

```
QUÉ ES
Herramienta de trabajo para docentes y centros educativos de Honduras. El Ministerio usa el sistema web SACE: cada docente descarga un Excel por asignatura (el "cuadro"), lo llena con notas y faltas y lo vuelve a subir. ProfeApp importa ese archivo, deja calificar por puntos y pasar lista sin internet, y al cerrar el parcial escribe nota y faltas en el mismo archivo. Es independiente: no está afiliada a la Secretaría de Educación ni se conecta a SACE.

CUENTAS (no hay registro público; las crea ProfeApp o el centro)
1) Docente
Usuario: <correo de la cuenta de revisión docente>
Contraseña: <contraseña>
Secciones de ejemplo con alumnos ficticios. Revisar: Inicio → una asignatura → Plan, Actividades, Notas y Estadísticas; ícono de lista para pasar lista; ícono de tabla para el cuadro de SACE.

2) Administrador de centro
Usuario: <correo de la cuenta de revisión del centro>
Contraseña: <contraseña>
Gestiona el centro (datos ficticios): tablero, docentes, secciones, horarios, asistencia, excusas, incidencias, alumnos con carnet, comunicados, reportes.

ELIMINAR LA CUENTA
Docente: Cuenta → Eliminar mi cuenta. Administrador: menú de la cuenta → Eliminar mi cuenta. Pide la contraseña y borra en el momento, en el servidor y en el dispositivo.

PAGOS (3.1)
No se compra nada en la app: sin compras, precios ni enlaces para pagar. El servicio se contrata por fuera: el centro para sus docentes (3.1.3(c)) o el docente, que también lo usa desde el navegador (3.1.3(f)). Si vence, la app solo informa la fecha.

SERVICIOS EXTERNOS
API propia en Render, base de datos en Aiven, web en Cloudflare. Push solo para cuentas de familia (comunicados y faltas) por Firebase Cloud Messaging. El asistente con IA usa la API de Anthropic (Claude) desde nuestro servidor. Nada de publicidad, analítica ni pagos.

ASISTENTE CON IA (5.1.2(i))
Las dos cuentas tienen el plan Pro activo. Antes del primer uso la app explica qué se envía a Anthropic y pide permiso ("Acepto" / "Ahora no"); sin aceptar no se envía nada. Nunca se envían nombres ni identidades de alumnos, y las fotos no se guardan. El asistente solo propone.
Docente: Plan → "Sugerir el plan con IA" (si la asignatura tiene programa oficial de la Secretaría de Educación, el diálogo muestra sus resultados de aprendizaje); Actividades → "Generar examen con IA"; Cuenta → Portafolio docente → "Redactar con IA" y "Redactar acciones de mejora con IA" (el PDF se genera con "Generar portafolio en PDF"); al calificar, el ícono de escáner junto a un alumno ("Calificar con foto (IA)"), o el ícono de tanda arriba para tomar los trabajos de varios alumnos y mandarlos juntos (las notas sugeridas llegan en unos minutos).
Centro: Reportes → "Preguntar a la IA" e "Informe con IA".

CÁMARA Y FOTOS
Solo para la foto del carnet de un alumno o la de un trabajo para calificar con IA.

Solo español, sin diferencias regionales. Probada en iPhone 12 Pro con iOS 27 y en iPad.
```

> Si el revisor elimina una cuenta de revisión, hay que volver a crearla antes de responderle
> (ver [tiendas.md](tiendas.md#cuentas-de-revisión)).

### El video

Apple pidió a Garaj una grabación en un aparato físico. Se adjunta desde el primer envío:

- **Sin narración.** Se revisa sin sonido; lo que explica va en las Notas.
- **Instalar desde TestFlight → Pruebas internas**, no desde Xcode: así se graba lo mismo que verá
  el revisor.
- **La sesión sobrevive a borrar la app** (el token vive en el llavero). Antes de grabar:
  Cuenta → Cerrar sesión, para que se vea el inicio de sesión.
- **Recorrido**: entrar con la cuenta docente → Inicio → asignatura (Plan, Actividades, Notas,
  Estadísticas) → calificar una actividad → pasar lista → cuadro de SACE y exportar → avisos →
  Cuenta → Eliminar mi cuenta (en una cuenta de prueba **aparte**, no la de revisión).
- Confirmar antes que las dos contraseñas de revisión entran **en producción**: una que falle
  obliga a repetir el video entero.

## Privacidad de la app (el cuestionario)

Primera pregunta, «¿recopilas datos?»: **Sí** (mandar nombres y notas al servidor propio cuenta
como recopilación).

**Desde la 1.2.0 cambia** (centro, familias, carnet, avisos e IA): hay que **editar el cuestionario
publicado** y agregar las filas marcadas con ⭐, y volver a pulsar **Publicar**.

| Tipo (Apple) | Qué es en ProfeApp | Vinculado a la persona | Rastreo | Finalidad |
| --- | --- | --- | --- | --- |
| Información de contacto → Nombre | Del docente, del personal del centro, de los alumnos y de las familias | Sí | No | Funcionalidad de la app |
| Información de contacto → Correo electrónico | Correo de la cuenta | Sí | No | Funcionalidad de la app |
| Información de contacto → Número de teléfono 🆕 | Teléfono del docente y del director que el docente escribe (opcional) para su portafolio | Sí | No | Funcionalidad de la app |
| Contenido del usuario → Fotos o videos ⭐ | Foto del alumno para el carnet (se guarda). La foto de un trabajo que se califica con IA se procesa y no se guarda | Sí | No | Funcionalidad de la app |
| Contenido del usuario → Otro contenido | Cuadros de SACE con identidad de los alumnos, notas, asistencia, excusas, incidencias y comunicados ⭐; horario y datos del portafolio (DNI, títulos y años de servicio del docente, sexo de los alumnos, acciones de nivelación) 🆕 | Sí | No | Funcionalidad de la app |
| Identificadores → ID de usuario | Id interno de la cuenta | Sí | No | Funcionalidad de la app |
| Identificadores → ID del dispositivo ⭐ | Token de notificaciones de las cuentas de familia (Firebase Cloud Messaging) | Sí | No | Funcionalidad de la app |

🆕 **Desde la 1.3.0** (portafolio docente): editar el cuestionario publicado, agregar el número de
teléfono y volver a pulsar **Publicar**.

Todo lo demás (ubicación, contactos, salud, compras, historial, identificadores de publicidad,
diagnóstico) **no** se recopila. Los datos que van al asistente con IA (Anthropic) no son
«rastreo» ni se usan para publicidad: Anthropic los procesa por cuenta de ProfeApp. Rastreo: **No**. Al terminar hay que pulsar **Publicar**: llenarlo
no basta y el botón de enviar se niega.

## Lo que pide «Información de la app» (y bloquea el envío)

- **Derechos sobre el contenido**: ¿muestra contenido de terceros? **No** (los cuadros son del
  propio docente).
- **Privacidad de la app**: publicada (arriba).
- **Clasificación por edades**: 4+ (todas las respuestas «No»).
- **Cumplimiento de exportación**: ya resuelto en el binario (`ITSAppUsesNonExemptEncryption =
  false`, solo HTTPS).
- **Acuerdos, impuestos y banca**: el acuerdo de apps gratuitas tiene que estar **en efecto**, o
  la app aprobada no se distribuye.
- La **declaración de comerciante de la UE** no bloquea: sin ella, la app no aparece en Europa,
  que de todos modos no aplica.

## Compilar y subir

```bash
cd mobile
flutter build ipa --release --dart-define-from-file=env/prod.json
```

Sale en `build/ios/ipa/profeapp.ipa`. Se sube con **Transporter** (arrastrar el `.ipa`) o desde
Xcode → Organizer. Cada subida necesita un número de compilación nuevo: el `+N` de `version:` en
`mobile/pubspec.yaml`.

Si al subir llega un correo de Apple por «Missing purpose string» (ITMS-90683), es porque algún
paquete enlaza una API de fotos o cámara aunque la app no la use. Se agrega en `Info.plist` la
clave que nombre el correo, con una frase que describa para qué es (nunca una frase de
desarrollo, que fue lo que Apple le señaló a Garaj), y se vuelve a compilar. Pasó con la
compilación 1: `file_picker` enlaza la fototeca, así que `NSPhotoLibraryUsageDescription` ya
está. La app nunca pide permiso de fotos: el selector de archivos de iOS no lo necesita.

La app pide iOS 15 o superior (Apple lo exige para subir desde abril de 2027).

## Lista antes de mandar

Para la **1.2.0 (11)**: plan Pro activo en las dos cuentas de revisión (Plataforma → plan de la
cuenta → «Plan Pro»), cuestionario de privacidad editado y **publicado** con las filas ⭐, notas
para el revisor con las secciones nuevas (servicios externos, asistente con IA, cámara) y las
novedades de la versión.

- [ ] App creada en App Store Connect con el bundle `hn.profeapp.profeapp`.
- [ ] `.ipa` 1.0.0 (1) subido, apuntando a producción (`env/prod.json`).
- [ ] Ficha, palabras clave, texto promocional y descripción pegados.
- [ ] Capturas de iPhone 6,9" **e iPad 13"**.
- [ ] Las dos cuentas de revisión existen **en producción** y entran; datos ficticios.
- [ ] Notas para el revisor con las credenciales reales, y el video adjunto.
- [ ] Privacidad de la app **publicada**; derechos sobre el contenido: No.
- [ ] Acuerdo de apps gratuitas en efecto.
- [ ] Mirar la app en un iPad antes de enviar: Apple revisó Garaj en iPad.

## Si rechazan

Responder desde **Revisión de apps → Ver envío → Responder**, y dejar el mismo texto en las Notas
de la versión. **Responder no la devuelve a la cola**: hay que pulsar **«Volver a enviar a
revisión de apps»** en la página del envío.
