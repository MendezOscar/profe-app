namespace ProfeApp.Application.Contracts;

// ── Lado del centro ──────────────────────────────────────────────────────────

/// <summary>Código para la familia, como se le entrega: XXXX-XXXX.</summary>
public sealed record CodigoFamiliaDto(string Codigo, DateTimeOffset ExpiraEn);

public sealed record VinculoDto(Guid UsuarioId, string Nombre, string Email, DateTimeOffset Desde);

/// <summary>Acceso de las familias a un alumno: el código vigente (si hay) y quiénes ya entraron.</summary>
public sealed record FamiliaAlumnoDto(CodigoFamiliaDto? Codigo, IReadOnlyList<VinculoDto> Vinculos);

/// <summary><c>SeccionIds</c> vacía o nula: para todo el centro.</summary>
public sealed record ComunicadoRequest(string Titulo, string Cuerpo, IReadOnlyList<Guid>? SeccionIds);

/// <summary><c>Destinatarios</c>: cuentas de familia que lo pueden ver hoy; <c>Leidos</c>: cuántas lo abrieron.</summary>
public sealed record ComunicadoCentroDto(
    Guid Id, string Titulo, string Cuerpo, IReadOnlyList<Guid> SeccionIds, DateTimeOffset PublicadoEn, string? Autor,
    int Leidos, int Destinatarios);

// ── Lado del padre ───────────────────────────────────────────────────────────

public sealed record RegistroPadreRequest(string Codigo, string Email, string Password, string FullName, string? DeviceName = null);

public sealed record CodigoRequest(string Codigo);

public sealed record HijoDto(Guid AlumnoId, string Nombre, string Centro, string? Seccion);

public sealed record ComunicadoPadreDto(Guid Id, string Centro, string Titulo, string Cuerpo, DateTimeOffset PublicadoEn, bool Leido);

public sealed record ActividadHijoDto(string Titulo, DateOnly? Fecha, decimal Puntos, decimal? Nota);

/// <summary><c>Obtenidos</c> de <c>Calificados</c>: puntos de lo ya calificado, no del parcial completo.</summary>
public sealed record ParcialHijoDto(string Parcial, bool Cerrado, decimal Obtenidos, decimal Calificados, IReadOnlyList<ActividadHijoDto> Actividades);

public sealed record AsignaturaHijoDto(string Asignatura, string Docente, IReadOnlyList<ParcialHijoDto> Parciales);

/// <summary><c>Estado</c>: ausente, tarde o justificada.</summary>
public sealed record FaltaDto(DateOnly Fecha, string Asignatura, string Estado);

public sealed record AsistenciaHijoDto(int Sesiones, int Ausencias, int Tardes, int Justificadas, IReadOnlyList<FaltaDto> Recientes);

public sealed record EntregaDto(string Asignatura, string Titulo, DateOnly Fecha, decimal Puntos);

/// <summary><c>AsistenciaDiaria</c>: la lista del día que pasa el maestro guía (<c>Sesiones</c> = días con lista).</summary>
public sealed record ResumenHijoDto(
    Guid AlumnoId, string Nombre, string Centro, string? Seccion,
    IReadOnlyList<AsignaturaHijoDto> Asignaturas, AsistenciaHijoDto Asistencia, IReadOnlyList<EntregaDto> Proximas,
    AsistenciaHijoDto? AsistenciaDiaria = null, IReadOnlyList<ClaseHorarioDto>? Horario = null,
    IReadOnlyList<string?>? Conducta = null, IReadOnlyList<IncidenciaFamiliaDto>? Incidencias = null);
