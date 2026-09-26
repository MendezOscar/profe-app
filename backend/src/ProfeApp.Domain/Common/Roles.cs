namespace ProfeApp.Domain.Common;

/// <summary>
/// Por ahora un solo perfil de negocio: el docente, dueño de su propio espacio.
/// Cuando se venda a colegios aparecerá el coordinador del centro.
/// </summary>
public static class Roles
{
    public const string PlatformAdmin = "PlatformAdmin";
    public const string Docente = "Docente";

    public static readonly string[] All = [PlatformAdmin, Docente];
}

public static class Policies
{
    public const string DocenteOnly = "docente-only";
    public const string PlatformOnly = "platform-only";
}
