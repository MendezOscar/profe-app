# Formato del cuadro de notas SACE

Estado: **provisional**. Se armó a partir de dos capturas del archivo que genera "Descargar Archivos Notas" (manual SACE Docente, sección 4.1.1):
- **A:** básica, Tercer grado, Ciencias Naturales, 4 parciales, vacío.
- **B:** media, BTP Contaduría y Finanzas, Onceavo grado, Lengua y Literatura, 2 parciales, lleno.

Hay que validarlo con un archivo real antes de congelar el importador.

## Estructura

Hay un archivo por clase, es decir, por combinación de centro, modalidad, curso, sección, jornada y asignatura.

### Encabezado (filas superiores, texto centrado en celdas combinadas)
| Línea | Ejemplo |
|---|---|
| Código del centro \| nombre del centro | `080100642M02 \| ESPANA JESUS MILLA SELVA` |
| Modalidad | `MODALIDAD: BACHILLERATO TÉCNICO PROFESIONAL EN CONTADURÍA Y FINANZAS` / `MODALIDAD: NO APLICA` (básica) |
| Grado y sección | `ONCEAVO GRADO SECCIÓN 12` |
| Jornada | `JORNADA VESPERTINA` |
| Asignatura | `LENGUA Y LITERATURA` |

### Tabla de alumnos (encabezado en dos filas)
| Columna | Contenido | Tipo |
|---|---|---|
| DOCUMENTO | Tipo o país del documento, p. ej. `HND` | texto, solo lectura |
| IDENTIDAD | 13 dígitos con ceros a la izquierda, p. ej. `0801200101758`, `0000000164448` | **texto** (Excel marca "número como texto"), solo lectura |
| NOMBRE | Nombre completo en mayúsculas | texto, solo lectura |
| PARCIAL *n* → INASISTENCIAS | | entero ≥ 0, editable |
| PARCIAL *n* → NOTA TOTAL | | entero 0–100, editable |
| PARCIAL *n* → NIVELACIÓN | **Solo en algunos parciales** (en B aparece en Parcial I y no en II; en A no aparece) | entero, editable |
| RECUPERACIÓN | Una columna al final | entero 0–100, editable |

**La cantidad de parciales y de columnas cambia según la modalidad.** Básica trae 4 parciales sin nivelación; media semestral trae 2 parciales y nivelación en el Parcial I. Por eso el importador no puede asumir un diseño fijo.

- Los alumnos vienen agrupados por sexo y ordenados alfabéticamente, como los entrega SACE. **No hay que reordenarlos.**
- Algunos alumnos tienen notas vacías y 0 inasistencias (p. ej. JHEIMY, SUSANA). Parecen retirados o sin evaluar, así que se acepta dejar celdas vacías.
- Después del último alumno hay una fila `*****Fin del documento*****`.
- Debajo aparece la nota: *"Únicamente ingrese notas en las casillas generadas por el sistema para este documento, de ninguna forma altere el formato y diseño de este."*

## Reglas inferidas de los datos de B (por confirmar)
- **Nota mínima para aprobar: 70.**
- **NIVELACIÓN = puntos que se suman a la nota del parcial para llegar a 70.** Ejemplos: 60 + 10, 61 + 9, 68 + 2 dan 70 en los tres casos. Si el alumno ya aprobó, va 0.
- **Nota final = promedio de los parciales (con nivelación), redondeado.**
- **RECUPERACIÓN se llena solo si la nota final es < 70.** Los datos coinciden en todos los casos:
  - 71 y 48 dan 59.5, con recuperación.
  - 94 y 47 dan 70.5, sin recuperación.
  - 79 y 60 dan 69.5, que redondea a 70, sin recuperación.
  - (60 + 10) y 50 dan 60, con recuperación.

La app puede usar estas reglas para calcular la nivelación sugerida, marcar a quién le toca recuperación y alertar a los alumnos en riesgo.

## Decisión de diseño

**No se genera el archivo desde cero; se rellena el archivo original**, tal como pide la nota al pie. El flujo es:
1. El docente descarga el cuadro desde SACE (una vez por clase y por año, con internet).
2. Lo importa en la app, que lee el centro, la modalidad, la sección, la jornada, la asignatura, los alumnos y **las columnas que trae**.
3. Captura notas, inasistencias y nivelación offline.
4. La app escribe **solo las celdas editables** del mismo archivo y lo devuelve para subirlo en "Cargar Archivo de Notas e Inasistencias".

El importador **localiza por texto, no por coordenadas**:
- la fila con `IDENTIDAD`,
- los encabezados `PARCIAL …` (celdas combinadas; su rango define las subcolumnas),
- las subcolumnas `INASISTENCIAS`, `NOTA TOTAL` y `NIVELACIÓN`,
- `RECUPERACIÓN`,
- la fila `Fin del documento`.

Así se conservan las columnas ocultas, las protecciones y los formatos que SACE pueda usar para validar.

## Modelo resultante (dominio)
- `CentroEducativo` (código SACE, nombre)
- `Clase` (centro, modalidad, grado, sección, jornada, asignatura, año). Es la unidad que corresponde a un archivo.
- `Alumno` (documento, identidad, nombre) y `Matricula` (alumno en la clase, con el orden del archivo)
- `EstructuraEvaluacion` de la clase: la lista de parciales, las columnas de cada uno y si hay recuperación, tomada del archivo importado
- `Calificacion` (matrícula × parcial: inasistencias, nota, nivelación) y `Recuperacion` (matrícula)

## Pendiente de confirmar con un archivo real
- [ ] Extensión (`.xls` o `.xlsx`). Si es `.xls` binario, hay que ver cómo reescribirlo sin romperlo.
- [ ] Nombre de la hoja y si trae varias hojas.
- [ ] Coordenadas, celdas combinadas y columnas o filas ocultas (¿IDs de alumno o de clase?).
- [ ] Si la hoja está protegida o tiene validación de datos.
- [ ] Si la columna NIVELACIÓN aparece en el Parcial II cuando se abre la nivelación de ese parcial.
- [ ] Las reglas de nivelación y recuperación con la normativa oficial (Reglamento de Evaluación de los Aprendizajes).
- [ ] Si SACE acepta subir el archivo con solo algunos parciales llenos.
- [ ] Nombre del archivo que genera SACE y si se exige al subir.
