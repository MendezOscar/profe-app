namespace ProfeApp.Application.Contracts;

/// <summary>
/// Si el docente tiene el asistente (plan Pro) y cuánto le queda este mes.
/// <c>Disponible</c> falso: el servidor no tiene la IA configurada.
/// </summary>
public sealed record EstadoIaDto(bool Habilitada, bool Disponible, int Generaciones, int LimiteGeneraciones, int Comentarios, int LimiteComentarios);

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
