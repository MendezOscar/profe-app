namespace ProfeApp.Infrastructure.Identity;

public sealed class JwtOptions
{
    public const string Section = "Jwt";
    public string Issuer { get; set; } = "profeapp";
    public string Audience { get; set; } = "profeapp-app";
    public string Key { get; set; } = null!;
    public int AccessTokenMinutes { get; set; } = 15;
    /// <summary>
    /// Largo a propósito: el docente rural puede pasar semanas sin señal y no debe
    /// perder la sesión por eso. Lo que captura offline vive en el teléfono igual.
    /// </summary>
    public int RefreshTokenDays { get; set; } = 90;
}

public static class AppClaims
{
    public const string TenantId = "tenant_id";
    public const string FullName = "full_name";
}
