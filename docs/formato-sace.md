# Formato del cuadro de notas SACE

## Confirmado con un archivo real (Química, 10.º BTP Administración, 2025)

- **Formato: `.xls` binario (Excel 97-2003, BIFF8)**, no `.xlsx`. El archivo tiene ROW/INDEX/DBCELL, RK/MULRK y MULBLANK, las huellas de haber sido guardado por Excel ("Last saved by" es un docente). Así que SACE acepta un `.xls` guardado por Excel.
- **Una sola hoja, con un nombre que parece un identificador interno: `19847174~1~1123`.** Probablemente SACE la usa para saber a qué clase corresponde el archivo al subirlo. **Hay que conservarla tal cual.**
- No trae columnas ni filas ocultas y la hoja no está protegida.
- La estructura coincide con la deducida de las capturas:
  - encabezado en A1:A5, combinado de A a O;
  - tabla con la fila `DOCUMENTO/IDENTIDAD/NOMBRE` en la fila 6 (A6:A7, B6:B7 y C6:C7 combinadas);
  - `PARCIAL I–IV` combinados de a dos columnas (INASISTENCIAS, NOTA TOTAL) y `RECUPERACIÓN` en L6:L7;
  - fila `Fin del documento` y nota final combinadas de A a O.
- **Esta modalidad de media (BTP) trae 4 parciales y ninguna columna de nivelación**, a diferencia de la captura del BTP en Contaduría. Confirma que la estructura varía y que hay que leerla del archivo.
- La identidad viene como texto (con los ceros); las notas e inasistencias, como número. Las celdas sin capturar son BLANK/MULBLANK con formato.

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
4. Al exportar, la app manda a la API el archivo original junto con los valores. La API escribe **solo las celdas editables** con NPOI, conservando hoja, estilos y combinaciones, y devuelve el `.xls` sin guardarlo. El docente lo sube en "Cargar Archivo de Notas e Inasistencias".

**Por qué la exportación va en el servidor:** escribir BIFF8 sin romperlo exige rehacer registros, índices (INDEX/DBCELL) y el contenedor OLE, y en Dart no hay una librería madura que lo haga. NPOI sí. Exportar requiere internet, pero subir el archivo a SACE también. **La lectura sí es 100 % offline** en el teléfono ([xls.dart](../mobile/lib/core/sace/xls.dart)).

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
