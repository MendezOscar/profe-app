namespace ProfeApp.Application.Contracts;

public sealed record BloqueDto(Guid Id, string Jornada, int Orden, TimeOnly Inicio, TimeOnly Fin, bool EsReceso);

public sealed record BloqueRequest(string Jornada, TimeOnly Inicio, TimeOnly Fin, bool EsReceso);

/// <summary><c>Dia</c>: 1 = lunes … 6 = sábado. <c>DocenteId</c> sale de la carga docente.</summary>
public sealed record CeldaHorarioDto(int Dia, Guid BloqueId, Guid AsignaturaId, Guid? AulaId, Guid? DocenteId);

public sealed record CeldaHorarioRequest(int Dia, Guid BloqueId, Guid AsignaturaId, Guid? AulaId);

/// <summary>Reemplaza todo el horario de la sección.</summary>
public sealed record HorarioSeccionRequest(IReadOnlyList<CeldaHorarioRequest> Celdas);

public sealed record HorarioSeccionDto(Guid SeccionId, IReadOnlyList<CeldaHorarioDto> Celdas, IReadOnlyList<string> Choques);

/// <summary>Una clase en el horario de un docente.</summary>
public sealed record ClaseHorarioDto(int Dia, TimeOnly Inicio, TimeOnly Fin, string Asignatura, string Seccion, string? Aula);

// ── Asistencia diaria del maestro guía ───────────────────────────────────────

/// <summary><c>Estado</c>: A (ausente), T (tarde), J (justificada) o null (presente).</summary>
public sealed record AlumnoDiaDto(Guid AlumnoId, string Nombre, string? Estado);

public sealed record ListaDiariaDto(Guid SeccionId, string Seccion, DateOnly Fecha, bool Tomada, IReadOnlyList<AlumnoDiaDto> Alumnos);

public sealed record MarcaDiariaRequest(Guid AlumnoId, string Estado);

/// <summary>Solo las faltas: quien no viene, está presente.</summary>
public sealed record ListaDiariaRequest(DateOnly Fecha, IReadOnlyList<MarcaDiariaRequest> Marcas);

/// <summary>Lo que el centro ve de un día: qué secciones pasaron lista y quién faltó.</summary>
public sealed record AsistenciaDelDiaDto(DateOnly Fecha, IReadOnlyList<SeccionDelDiaDto> Secciones);

public sealed record SeccionDelDiaDto(Guid SeccionId, string Seccion, string? Guia, bool Tomada, int Activos, IReadOnlyList<AlumnoDiaDto> Faltas);

// ── Conducta (maestro guía, por parcial) ─────────────────────────────────────

/// <summary><c>Nota</c>: A–E o null si aún no la tiene.</summary>
public sealed record ConductaAlumnoDto(Guid AlumnoId, string Nombre, string? Nota);

public sealed record ConductaSeccionDto(Guid SeccionId, string Seccion, int Parcial, IReadOnlyList<ConductaAlumnoDto> Alumnos);

public sealed record NotaConductaRequest(Guid AlumnoId, string? Nota);

/// <summary>Reemplaza la conducta del parcial; nota null la borra.</summary>
public sealed record ConductaRequest(int Parcial, IReadOnlyList<NotaConductaRequest> Notas);
