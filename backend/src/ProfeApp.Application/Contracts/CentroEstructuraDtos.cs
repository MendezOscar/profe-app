namespace ProfeApp.Application.Contracts;

/// <summary>Lo que el panel del centro necesita para mostrar su organización de un año lectivo.</summary>
public sealed record EstructuraDto(
    bool PuedeEditar,
    IReadOnlyList<AnioLectivoDto> Anios,
    Guid? AnioId,
    IReadOnlyList<GradoDto> Grados,
    IReadOnlyList<AulaDto> Aulas,
    IReadOnlyList<SeccionDto> Secciones,
    IReadOnlyList<DocenteBreveDto> Docentes);

/// <summary><c>Cierres</c>: fecha de cierre de cada parcial, I a IV (null si aún no se fija).</summary>
public sealed record AnioLectivoDto(Guid Id, int Anio, DateOnly Inicio, DateOnly Fin, IReadOnlyList<DateOnly?> Cierres, bool Actual);

public sealed record AnioLectivoRequest(int Anio, DateOnly Inicio, DateOnly Fin, IReadOnlyList<DateOnly?>? Cierres, bool Actual);

public sealed record GradoDto(Guid Id, string Nivel, string Nombre, int Orden, IReadOnlyList<AsignaturaGradoDto> Asignaturas);

public sealed record GradoRequest(string Nivel, string Nombre, int? Orden = null);

/// <summary>Crea los grados que falten de los niveles pedidos (prebasica, basica, media).</summary>
public sealed record PlantillaGradosRequest(IReadOnlyList<string> Niveles);

public sealed record AsignaturaGradoDto(Guid Id, string Nombre, int Orden);

/// <summary>Las mismas asignaturas en varios grados a la vez; las que ya existan se saltan.</summary>
public sealed record AgregarAsignaturasRequest(IReadOnlyList<Guid> GradoIds, IReadOnlyList<string> Nombres);

public sealed record NombreRequest(string Nombre);

public sealed record AulaDto(Guid Id, string Nombre, int? Capacidad);

public sealed record AulaRequest(string Nombre, int? Capacidad);

public sealed record SeccionDto(
    Guid Id, Guid GradoId, string Nombre, string Jornada, int? Cupo, Guid? AulaId, Guid? MaestroGuiaId,
    IReadOnlyList<AsignacionDto> Carga);

public sealed record SeccionRequest(
    Guid AnioLectivoId, Guid GradoId, string Nombre, string Jornada, int? Cupo, Guid? AulaId, Guid? MaestroGuiaId);

public sealed record AsignacionDto(Guid AsignaturaId, Guid DocenteId);

/// <summary>Reemplaza toda la carga de la sección: la asignatura que no venga queda sin docente.</summary>
public sealed record CargaRequest(IReadOnlyList<AsignacionDto> Asignaciones);

public sealed record DocenteBreveDto(Guid Id, string Nombre, bool Activo);

/// <summary>Personal del centro: dirección, secretaría, orientación. <c>Cargo</c> null = administrador original.</summary>
public sealed record PersonalDto(Guid Id, string Nombre, string Email, string? Cargo, bool Activo, DateTimeOffset? UltimoAcceso, bool EsYo);

public sealed record CrearPersonalRequest(string Email, string Nombre, string Cargo);

public sealed record CargoRequest(string Cargo);
