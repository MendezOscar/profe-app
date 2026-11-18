namespace ProfeApp.Application.Contracts;

// ── Excusas y permisos ───────────────────────────────────────────────────────

/// <summary><c>Tipo</c>: excusa o permiso. Días de <c>Desde</c> a <c>Hasta</c>, ambos incluidos.</summary>
public sealed record ExcusaDto(
    Guid Id, Guid AlumnoId, string Alumno, string? Seccion, string Tipo, DateOnly Desde, DateOnly Hasta,
    string Motivo, string? RegistradaPor, DateTimeOffset RegistradaEn);

public sealed record ExcusaRequest(Guid AlumnoId, string? Tipo, DateOnly Desde, DateOnly Hasta, string? Motivo);

/// <summary>Lo que ve el docente al pasar lista: el alumno se busca por identidad en su cuadro.</summary>
public sealed record ExcusaDocenteDto(string Identidad, string Nombre, string Tipo, DateOnly Desde, DateOnly Hasta, string Motivo);
