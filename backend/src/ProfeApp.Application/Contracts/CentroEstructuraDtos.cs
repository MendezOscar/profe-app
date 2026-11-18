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
    IReadOnlyList<AsignacionDto> Carga, int Matriculados = 0);

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

// ── Matrícula y fichas ───────────────────────────────────────────────────────

/// <summary>Un alumno en la lista de una sección, con el estado de su matrícula.</summary>
public sealed record AlumnoSeccionDto(
    Guid MatriculaId, Guid AlumnoId, string Identidad, string Nombre, string? Sexo,
    string Tipo, string Estado, DateOnly FechaIngreso, DateOnly? FechaBaja, string? MotivoBaja);

public sealed record AlumnoImportado(string Identidad, string Nombre);

/// <summary>
/// Lista de una sección leída del archivo de SACE. Quien ya está matriculado en otra
/// sección del mismo año no se mueve, salvo con <c>MoverDeSeccion</c>.
/// </summary>
public sealed record ImportarAlumnosRequest(IReadOnlyList<AlumnoImportado> Alumnos, bool MoverDeSeccion = false);

public sealed record ConflictoMatriculaDto(string Identidad, string Nombre, string Seccion);

public sealed record ImportacionDto(
    int Nuevos, int YaEstaban, int Movidos, IReadOnlyList<ConflictoMatriculaDto> EnOtraSeccion, int Activos, int? Cupo);

public sealed record MatricularRequest(string Identidad, string Nombre, string Tipo, DateOnly? FechaIngreso = null);

public sealed record EncargadoDto(string Nombre, string? Parentesco, string? Telefono, string? Correo, bool Principal);

public sealed record MatriculaHistorialDto(
    Guid Id, int Anio, Guid SeccionId, string Seccion, string Tipo, string Estado,
    DateOnly FechaIngreso, DateOnly? FechaBaja, string? MotivoBaja);

public sealed record FichaAlumnoDto(
    Guid Id, string Identidad, string Nombre, DateOnly? FechaNacimiento, string? Sexo, string? Direccion,
    string? Salud, string? Notas, IReadOnlyList<EncargadoDto> Encargados, IReadOnlyList<MatriculaHistorialDto> Matriculas,
    bool PuedeEditar);

public sealed record FichaAlumnoRequest(
    string Identidad, string Nombre, DateOnly? FechaNacimiento, string? Sexo, string? Direccion,
    string? Salud, string? Notas, IReadOnlyList<EncargadoDto> Encargados);

/// <summary><c>Estado</c>: retirada o trasladada.</summary>
public sealed record BajaRequest(string Estado, DateOnly Fecha, string? Motivo);

public sealed record CambioSeccionRequest(Guid SeccionId);

/// <summary><c>Seccion</c> y <c>Estado</c> son de su matrícula en el año actual, si tiene.</summary>
public sealed record AlumnoBuscadoDto(Guid Id, string Identidad, string Nombre, string? Seccion, string? Estado);

public sealed record PaginaAlumnosDto(IReadOnlyList<AlumnoBuscadoDto> Alumnos, int Total, bool Mas);
