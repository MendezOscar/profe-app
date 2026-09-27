namespace ProfeApp.Application.Contracts;

public sealed record InstitucionDto(
    Guid Id, string Nombre, string Plan, int MaxDocentes, int Docentes, DateTimeOffset? VenceEn, bool Activa);

public sealed record CrearInstitucionRequest(
    string Nombre, string Plan, int MaxDocentes, DateTimeOffset? VenceEn, string AdminEmail, string AdminNombre);

public sealed record ActualizarInstitucionRequest(string Plan, int MaxDocentes, DateTimeOffset? VenceEn, bool Activa);

/// <summary>La contraseña temporal sólo se muestra una vez; al entrar, el usuario debe cambiarla.</summary>
public sealed record CuentaCreada(Guid UsuarioId, string Email, string Nombre, string ClaveTemporal);

public sealed record InstitucionCreada(InstitucionDto Institucion, CuentaCreada Admin);

public sealed record CrearDocenteRequest(string Email, string Nombre);

/// <summary>Lo que el centro ve de cada docente: su avance, no sus notas.</summary>
public sealed record DocenteCentroDto(
    Guid Id, string Nombre, string Email, bool Activo, DateTimeOffset? UltimoAcceso,
    int Asignaturas, int Actividades, int ParcialesCerrados);

public sealed record CentroDto(InstitucionDto Institucion, IReadOnlyList<DocenteCentroDto> Docentes);
