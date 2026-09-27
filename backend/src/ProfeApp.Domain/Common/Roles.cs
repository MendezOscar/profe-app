namespace ProfeApp.Domain.Common;

/// <summary>
/// El docente es dueño de su propio espacio. El administrador de un centro da de alta a
/// sus docentes y ve su avance, sin acceso a editar sus notas. PlatformAdmin es quien
/// opera ProfeApp: crea centros y cuentas del plan personal.
/// </summary>
public static class Roles
{
    public const string PlatformAdmin = "PlatformAdmin";
    public const string Docente = "Docente";
    public const string AdminCentro = "AdminCentro";

    public static readonly string[] All = [PlatformAdmin, Docente, AdminCentro];
}

public static class Policies
{
    public const string DocenteOnly = "docente-only";
    public const string PlatformOnly = "platform-only";
    public const string CentroOnly = "centro-only";
}
