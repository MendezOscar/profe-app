namespace ProfeApp.Application.Contracts;

// ── Excusas y permisos ───────────────────────────────────────────────────────

/// <summary><c>Tipo</c>: excusa o permiso. Días de <c>Desde</c> a <c>Hasta</c>, ambos incluidos.</summary>
public sealed record ExcusaDto(
    Guid Id, Guid AlumnoId, string Alumno, string? Seccion, string Tipo, DateOnly Desde, DateOnly Hasta,
    string Motivo, string? RegistradaPor, DateTimeOffset RegistradaEn);

public sealed record ExcusaRequest(Guid AlumnoId, string? Tipo, DateOnly Desde, DateOnly Hasta, string? Motivo);

/// <summary>Lo que ve el docente al pasar lista: el alumno se busca por identidad en su cuadro.</summary>
public sealed record ExcusaDocenteDto(string Identidad, string Nombre, string Tipo, DateOnly Desde, DateOnly Hasta, string Motivo);

// ── Incidencias disciplinarias ───────────────────────────────────────────────

/// <summary><c>Gravedad</c>: leve, grave o muy_grave.</summary>
public sealed record IncidenciaDto(
    Guid Id, Guid AlumnoId, string Alumno, string? Seccion, DateOnly Fecha, string Gravedad, string Descripcion,
    string? Medida, string? Seguimiento, bool Cerrada, string? RegistradaPor, DateTimeOffset RegistradaEn);

/// <summary>El centro la registra por alumno.</summary>
public sealed record IncidenciaRequest(Guid AlumnoId, DateOnly Fecha, string? Gravedad, string? Descripcion, string? Medida);

/// <summary>El catedrático la registra desde su sección, buscando al alumno por identidad.</summary>
public sealed record IncidenciaDocenteRequest(Guid SeccionId, string? Identidad, DateOnly Fecha, string? Gravedad, string? Descripcion, string? Medida);

/// <summary>Seguimiento que da el centro.</summary>
public sealed record SeguimientoIncidenciaRequest(string? Medida, string? Seguimiento, bool Cerrada);

/// <summary>Lo que ve la familia.</summary>
public sealed record IncidenciaFamiliaDto(DateOnly Fecha, string Gravedad, string Descripcion, string? Medida);
