using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using ProfeApp.Infrastructure.Identity;

namespace ProfeApp.Api.Auth;

/// <summary>
/// Configura la validación del JWT desde IOptions&lt;JwtOptions&gt;, la misma fuente que usa
/// TokenService para firmarlo. Leer la clave por separado en Program abría la puerta a que
/// emisión y validación usaran claves distintas.
/// </summary>
public sealed class JwtBearerSetup(IOptions<JwtOptions> options) : IPostConfigureOptions<JwtBearerOptions>
{
    public void PostConfigure(string? name, JwtBearerOptions bearer)
    {
        var jwt = options.Value;
        if (string.IsNullOrWhiteSpace(jwt.Key))
            throw new InvalidOperationException("Falta configurar Jwt:Key (usa dotnet user-secrets o una variable de entorno).");

        bearer.TokenValidationParameters = new TokenValidationParameters
        {
            ValidIssuer = jwt.Issuer,
            ValidAudience = jwt.Audience,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt.Key)),
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateIssuerSigningKey = true,
            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromSeconds(30),
            NameClaimType = "sub",
            RoleClaimType = ClaimTypes.Role
        };
    }
}
