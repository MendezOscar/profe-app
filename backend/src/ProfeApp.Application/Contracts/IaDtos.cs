namespace ProfeApp.Application.Contracts;

/// <summary>
/// Si el docente tiene el asistente (plan Pro) y cuánto le queda este mes.
/// <c>Disponible</c> falso: el servidor no tiene la IA configurada.
/// </summary>
public sealed record EstadoIaDto(
    bool Habilitada, bool Disponible, int Generaciones, int LimiteGeneraciones, int Comentarios, int LimiteComentarios,
    int Calificaciones = 0, int LimiteCalificaciones = 0);

// ── Plan del parcial ─────────────────────────────────────────────────────────

/// <summary>
/// <c>Rubros</c>: los que ya tiene el parcial (se respetan nombre y puntos); vacío para que
/// la IA los proponga. <c>Total</c>: puntos del parcial (100 en SACE).
/// </summary>
public sealed record PlanIaRequest(
    string? Asignatura, string? Grado, string? Parcial, string? Temas, int Semanas, decimal Total,
    IReadOnlyList<RubroIaDto>? Rubros);

public sealed record RubroIaDto(string Nombre, decimal Puntos);

public sealed record PlanIaDto(IReadOnlyList<RubroPlanIaDto> Rubros);

public sealed record RubroPlanIaDto(string Nombre, decimal Puntos, IReadOnlyList<ActividadIaDto> Actividades);

/// <summary><c>Semana</c>: 1 = primera semana del parcial.</summary>
public sealed record ActividadIaDto(string Titulo, decimal Puntos, string Descripcion, int Semana);

// ── Examen ───────────────────────────────────────────────────────────────────

/// <summary><c>Tipos</c>: opcion_multiple, verdadero_falso, respuesta_corta, desarrollo.</summary>
public sealed record ExamenIaRequest(
    string? Asignatura, string? Grado, string? Temas, int Preguntas, decimal Puntos, IReadOnlyList<string>? Tipos);

public sealed record ExamenIaDto(string Titulo, string Instrucciones, IReadOnlyList<PreguntaIaDto> Preguntas);

/// <summary><c>Opciones</c>: vacía salvo en opción múltiple. <c>Respuesta</c>: la clave para el docente.</summary>
public sealed record PreguntaIaDto(string Tipo, string Enunciado, IReadOnlyList<string> Opciones, string Respuesta, decimal Puntos);

// ── Comentario de un alumno ──────────────────────────────────────────────────

/// <summary>
/// Sin nombre ni identidad: la app manda solo las cifras y pone el nombre en el texto que
/// vuelve (la IA escribe «el estudiante»). <c>Rubros</c>: lo obtenido sobre lo posible.
/// </summary>
public sealed record ComentarioIaRequest(
    string? Asignatura, string? Grado, string? Parcial, IReadOnlyList<RubroNotaIaDto>? Rubros,
    decimal? Nota, int Ausencias, int Tardes, string? Enfoque);

public sealed record RubroNotaIaDto(string Nombre, decimal Obtenido, decimal Posible);

public sealed record ComentarioIaDto(string Texto);

// ── Centro (plan Pro) ────────────────────────────────────────────────────────

/// <summary>Uso del mes del centro y sus topes.</summary>
public sealed record EstadoIaCentroDto(
    bool Habilitada, bool Disponible, int Boletas, int LimiteBoletas, int Informes, int LimiteInformes, int Comunicados, int LimiteComunicados,
    int Preguntas = 0, int LimitePreguntas = 0);

/// <summary><c>EnProceso</c>: la IA todavía está redactando los de esta sección y parcial.</summary>
public sealed record ComentariosSeccionDto(Guid SeccionId, int Parcial, bool EnProceso, IReadOnlyList<ComentarioAlumnoDto> Alumnos);

/// <summary><c>DeIa</c>: texto de la IA sin cambios; falso si lo escribió o editó una persona.</summary>
public sealed record ComentarioAlumnoDto(Guid AlumnoId, string Nombre, string? Texto, bool DeIa);

/// <summary><c>Todos</c>: rehace también los de la IA ya escritos (nunca los editados por una persona).</summary>
public sealed record GenerarComentariosRequest(int Parcial, bool Todos);

public sealed record EditarComentarioRequest(int Parcial, string? Texto);

/// <summary>Informe del año para la dirección, con lo cerrado hasta hoy.</summary>
public sealed record InformeIaDto(string Resumen, IReadOnlyList<string> Fortalezas, IReadOnlyList<string> Alertas, IReadOnlyList<string> Recomendaciones);

/// <summary><c>Puntos</c>: lo que quiere decir el centro, en pocas palabras.</summary>
public sealed record ComunicadoIaRequest(string? Puntos, string? Destinatarios);

public sealed record ComunicadoIaDto(string Titulo, string Cuerpo);

// ── Calificar desde una foto (docente) ───────────────────────────────────────

/// <summary>
/// <c>Imagenes</c>: de 1 a 4 fotos JPEG en base64 del trabajo del alumno. <c>Criterios</c>:
/// clave de respuestas o lo que se pide para la nota completa (opcional, recomendado).
/// </summary>
public sealed record CalificarIaRequest(
    string? Asignatura, string? Grado, string? Actividad, string? Descripcion, decimal Puntos, string? Criterios,
    IReadOnlyList<string>? Imagenes);

/// <summary>Sugerencia para el docente: la nota (de 0 a los puntos de la actividad) y por qué.</summary>
public sealed record CalificacionIaDto(decimal Nota, string Justificacion);

// ── Preguntas de la dirección sobre los datos ────────────────────────────────

public sealed record TurnoIaDto(string Pregunta, string Respuesta);

/// <summary><c>Historial</c>: las preguntas y respuestas anteriores de la conversación (hasta 6).</summary>
public sealed record PreguntaIaRequest(string? Pregunta, IReadOnlyList<TurnoIaDto>? Historial);

public sealed record RespuestaIaDto(string Texto);

// ── Costo de la IA (plataforma) ──────────────────────────────────────────────

/// <summary>Costo estimado del mes en lempiras, con los precios del modelo y la tasa usados.</summary>
public sealed record CostosIaDto(
    int Anio, int Mes, decimal TasaLempira, decimal PrecioEntrada, decimal PrecioSalida, int Usos, decimal Total,
    IReadOnlyList<CostoFuncionIaDto> PorFuncion, IReadOnlyList<CostoCuentaIaDto> PorCuenta);

/// <summary><c>PorUso</c>: el promedio en lempiras de una llamada de esa función.</summary>
public sealed record CostoFuncionIaDto(string Funcion, int Usos, long TokensEntrada, long TokensSalida, decimal Total, decimal PorUso);

/// <summary><c>Tipo</c>: centro (incluye a sus docentes) o docente (plan personal).</summary>
public sealed record CostoCuentaIaDto(string Tipo, string Nombre, int Usos, decimal Total);
