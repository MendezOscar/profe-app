using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using ProfeApp.Application.Abstractions;
using ProfeApp.Infrastructure.Persistence;

namespace ProfeApp.Infrastructure.Identity;

public sealed class TokenService(AppDbContext db, IOptions<JwtOptions> options, IClock clock)
{
    private readonly JwtOptions _jwt = options.Value;

    public (string Token, DateTimeOffset ExpiresAt) CreateAccessToken(AppUser user, string role)
    {
        var expires = clock.Now.AddMinutes(_jwt.AccessTokenMinutes);
        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
            new(JwtRegisteredClaimNames.Email, user.Email ?? string.Empty),
            new(AppClaims.FullName, user.FullName),
            new(ClaimTypes.Role, role)
        };
        if (user.TenantId is { } tenantId) claims.Add(new Claim(AppClaims.TenantId, tenantId.ToString()));

        var credentials = new SigningCredentials(
            new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_jwt.Key)), SecurityAlgorithms.HmacSha256);
        var token = new JwtSecurityToken(_jwt.Issuer, _jwt.Audience, claims,
            expires: expires.UtcDateTime, signingCredentials: credentials);

        return (new JwtSecurityTokenHandler().WriteToken(token), expires);
    }

    /// <summary>Se guarda sólo el hash: una filtración de la tabla no permite suplantar sesiones.</summary>
    public async Task<(string Token, RefreshToken Entity)> IssueRefreshTokenAsync(
        Guid userId, string? ip, string? deviceName, CancellationToken ct = default)
    {
        var raw = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));
        var entity = new RefreshToken
        {
            UserId = userId,
            TokenHash = Hash(raw),
            CreatedAt = clock.Now,
            ExpiresAt = clock.Now.AddDays(_jwt.RefreshTokenDays),
            CreatedByIp = ip,
            DeviceName = deviceName
        };
        db.RefreshTokens.Add(entity);
        await db.SaveChangesAsync(ct);
        return (raw, entity);
    }

    public Task<RefreshToken?> FindAsync(string raw, CancellationToken ct = default)
    {
        var hash = Hash(raw);
        return db.RefreshTokens.FirstOrDefaultAsync(t => t.TokenHash == hash, ct);
    }

    public static string Hash(string raw) =>
        Convert.ToBase64String(SHA256.HashData(Encoding.UTF8.GetBytes(raw)));
}
