using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.Extensions.Caching.Memory;

namespace ProfeApp.Infrastructure.Identity;

/// <summary>
/// Access tokens anulados al cerrar sesión. Viven en memoria sólo hasta que el token vence
/// (15 minutos como mucho), así que la lista nunca crece.
/// </summary>
public sealed class TokensRevocados(IMemoryCache cache)
{
    private static string Clave(string jti) => $"jwt-revocado:{jti}";

    public void Revocar(ClaimsPrincipal usuario)
    {
        var jti = usuario.FindFirstValue(JwtRegisteredClaimNames.Jti);
        if (jti is null || !long.TryParse(usuario.FindFirstValue(JwtRegisteredClaimNames.Exp), out var exp)) return;
        var vence = DateTimeOffset.FromUnixTimeSeconds(exp);
        if (vence > DateTimeOffset.UtcNow) cache.Set(Clave(jti), true, vence.AddMinutes(1));
    }

    public bool Revocado(ClaimsPrincipal? usuario) =>
        usuario?.FindFirstValue(JwtRegisteredClaimNames.Jti) is { } jti && cache.TryGetValue(Clave(jti), out _);
}
