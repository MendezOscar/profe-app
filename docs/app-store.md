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

```
Primera versión.
```

### Publicación

**Publicar automáticamente** al aprobarse. Puede tardar hasta 24 horas en aparecer.

## Capturas

En `docs/tiendas/capturas/` (fuera del repositorio, ver [tiendas.md](tiendas.md#capturas)),
tomadas del panel con los datos de la cuenta demo:

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
ProfeApp es una herramienta de trabajo para docentes de secundaria de Honduras. El Ministerio de
Educación usa un sistema web llamado SACE donde cada docente descarga un archivo de Excel por
asignatura (el "cuadro"), lo llena con las notas y faltas del parcial y lo vuelve a subir.
ProfeApp importa ese archivo, deja calificar por puntos y pasar lista sin internet, y al cerrar
el parcial escribe la nota y las faltas en el mismo archivo para subirlo a SACE. ProfeApp es
independiente: no está afiliada a la Secretaría de Educación ni se conecta a SACE.

QUIÉN LA USA Y CÓMO SE ENTRA
No hay registro público: las cuentas las crea ProfeApp para cada docente, o el administrador de
un centro educativo para sus docentes. Hay dos tipos de cuenta en la app:

1) Docente (la principal)
   Usuario: <correo de la cuenta de revisión docente>
   Contraseña: <contraseña>
   Tiene tres secciones de ejemplo (Química 10-1 y 10-2, Física 11-1; alumnos ficticios) con
   tres parciales cerrados y el cuarto en curso.
   Qué revisar: Inicio → tocar la asignatura → pestañas Plan, Actividades, Notas y
   Estadísticas; el ícono de lista arriba para pasar lista; el ícono de tabla para el cuadro de
   SACE y exportarlo; la campana de Inicio para los avisos.

2) Administrador de centro
   Usuario: <correo de la cuenta de revisión del centro>
   Contraseña: <contraseña>
   Ve los docentes de su centro (tres de ejemplo, ficticios) y su avance; los da de alta, los
   desactiva y les restablece la contraseña.

Existe además una cuenta interna de plataforma que solo usa el equipo de ProfeApp para crear
centros; no es para usuarios.

ELIMINAR LA CUENTA
Docente: pestaña Cuenta → Eliminar mi cuenta. Administrador: menú de la cuenta (arriba a la
derecha) → Eliminar mi cuenta. Pide la contraseña, se confirma y se borra en el momento, con
todos los datos en el servidor y en el dispositivo.

PAGOS (regla 3.1)
En la app no se compra nada: no hay compras dentro de la app, ni precios, ni enlaces para
comprar. El servicio lo contrata por fuera de la app el centro educativo para sus docentes
(3.1.3(c), servicios para empresas u organizaciones) o el propio docente, que también lo usa
desde el navegador (3.1.3(f), app gratuita que acompaña una herramienta web). La app no mueve
dinero ni tiene pasarela de pago. Si el servicio de la cuenta vence, la app solo informa la
fecha y que lo nuevo no se respalda; no muestra precios, datos de pago ni enlaces para pagar.

SERVICIOS EXTERNOS
API propia en Render, base de datos PostgreSQL en Aiven y el sitio y panel web en Cloudflare
Pages. Ninguno es de publicidad, analítica ni pagos. Los avisos son notificaciones locales que
programa el propio teléfono; no hay notificaciones push. Enlaces salientes: WhatsApp de soporte
y las páginas de privacidad, términos y ayuda.

DIFERENCIAS REGIONALES
Ninguna. Solo español, porque el producto es para el sistema educativo de Honduras.

INDUSTRIA REGULADA O CONTENIDO DE TERCEROS
No aplica. Los archivos de SACE los descarga el propio docente con su usuario; ProfeApp no los
obtiene por su cuenta.

PROBADA EN
iPhone 12 Pro con iOS 27 y iPad (pantalla ancha, misma app). El video adjunto recorre la app en
el iPhone desde el inicio de sesión hasta eliminar la cuenta.
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

| Tipo (Apple) | Qué es en ProfeApp | Vinculado a la persona | Rastreo | Finalidad |
| --- | --- | --- | --- | --- |
| Información de contacto → Nombre | Nombre del docente | Sí | No | Funcionalidad de la app |
| Información de contacto → Correo electrónico | Correo de la cuenta | Sí | No | Funcionalidad de la app |
| Contenido del usuario → Otro contenido | Cuadros de SACE con nombres e identidad de los alumnos, notas, asistencia | Sí | No | Funcionalidad de la app |
| Identificadores → ID de usuario | Id interno de la cuenta | Sí | No | Funcionalidad de la app |

Todo lo demás (ubicación, contactos, salud, compras, historial, identificadores de publicidad,
diagnóstico) **no** se recopila. Rastreo: **No**. Al terminar hay que pulsar **Publicar**: llenarlo
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
desarrollo, que fue lo que Apple le señaló a Garaj), y se vuelve a compilar. Con la versión
actual no debería pasar: la app no pide fotos, cámara ni ubicación.

## Lista antes de mandar

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
