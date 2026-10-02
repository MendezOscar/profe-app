namespace ProfeApp.Application.Contracts;

/// <summary>
/// En qué anda el cobro de una cuenta. <c>Estado</c>: alDia, porVencer, gracia o soloLectura.
/// <c>Nivel</c> y <c>TopeAsignaturas</c> sólo en el plan personal del docente.
/// </summary>
public sealed record CobroDto(
    string Estado, string? PlanNombre, decimal Monto, DateOnly? PagadoHasta, int DiasGracia,
    DateOnly? BloqueaEn, int? DiasRestantes, bool SoloLectura, string Mensaje, string? ComoPagar,
    string? Nivel = null, int? TopeAsignaturas = null);

public sealed record InstitucionDto(
    Guid Id, string Nombre, string Plan, int MaxDocentes, int Docentes, bool Activa, CobroDto Cobro,
    DateTimeOffset CreadoEn, string? AdminEmail = null, DateOnly? UltimoPago = null);

public sealed record CrearInstitucionRequest(
    string Nombre, string Plan, int MaxDocentes, string AdminEmail, string AdminNombre, DateOnly? PagadoHasta = null);

/// <summary>El cupo de la licencia. El cobro va por <see cref="PlanCobroRequest"/>.</summary>
public sealed record ActualizarInstitucionRequest(string Plan, int MaxDocentes);

/// <summary>Lo que la plataforma fija a una cuenta. <c>Nivel</c> sólo para el docente personal.</summary>
public sealed record PlanCobroRequest(
    string? PlanNombre, decimal Monto, DateOnly? PagadoHasta, int DiasGracia, string? ComoPagar, string? Nivel = null);

/// <summary>
/// Sin <c>PagadoHasta</c>, el servidor suma los períodos al vencimiento que ya tenía (o a
/// hoy, si no tenía).
/// </summary>
public sealed record RegistrarPagoRequest(
    decimal Monto, int Periodos, DateOnly? PagadoHasta = null, string? Referencia = null, DateOnly? PagadoEl = null);

public sealed record PagoDto(Guid Id, DateOnly PagadoEl, decimal Monto, int Periodos, DateOnly CubreHasta, string? Referencia);

/// <summary>Un docente del plan personal, como lo ve la plataforma.</summary>
public sealed record DocentePlataformaDto(
    Guid Id, string Nombre, string Email, bool Activo, DateTimeOffset CreadoEn, DateTimeOffset? UltimoAcceso,
    int Asignaturas, CobroDto Cobro, DateOnly? UltimoPago);

public sealed record PaginaDocentes(IReadOnlyList<DocentePlataformaDto> Docentes, int Total, bool Mas);

/// <summary>La contraseña temporal sólo se muestra una vez; al entrar, el usuario debe cambiarla.</summary>
public sealed record CuentaCreada(Guid UsuarioId, string Email, string Nombre, string ClaveTemporal);

public sealed record InstitucionCreada(InstitucionDto Institucion, CuentaCreada Admin);

public sealed record CrearDocenteRequest(string Email, string Nombre);

/// <summary>Lo que el centro ve de cada docente: su avance, no sus notas.</summary>
public sealed record DocenteCentroDto(
    Guid Id, string Nombre, string Email, bool Activo, DateTimeOffset? UltimoAcceso,
    int Asignaturas, int Actividades, int ParcialesCerrados);

public sealed record CentroDto(InstitucionDto Institucion, IReadOnlyList<DocenteCentroDto> Docentes);
