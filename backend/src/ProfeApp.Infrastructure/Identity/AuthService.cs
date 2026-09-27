using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;
using ProfeApp.Domain.Common;
using ProfeApp.Domain.Tenants;
using ProfeApp.Infrastructure.Persistence;

namespace ProfeApp.Infrastructure.Identity;

public sealed class AuthService(
    AppDbContext db,
    UserManager<AppUser> users,
    TokenService tokens,
    ITenantContext tenant,
    ICurrentUser currentUser,
    IClock clock) : IAuthService
{
    public async Task<Result<AuthResponse>> RegisterAsync(RegisterRequest request, string? ip, CancellationToken ct = default)
    {
        var email = request.Email.Trim().ToLowerInvariant();
        if (string.IsNullOrWhiteSpace(request.FullName))
            return Result<AuthResponse>.Fail(Error.Validation("El nombre es obligatorio."));
        if (await users.FindByEmailAsync(email) is not null)
            return Result<AuthResponse>.Fail(Error.Conflict("Ya existe una cuenta con ese correo.", "email_taken"));

        // Tenant y usuario en una sola transacción: un alta a medias dejaría un espacio
        // sin dueño o un docente sin espacio. Con reintentos activos, la transacción
        // tiene que ir dentro de la estrategia de ejecución o EF la rechaza.
        var user = new AppUser
        {
            Id = Guid.NewGuid(),
            UserName = email,
            Email = email,
            FullName = request.FullName.Trim(),
            CreatedAt = clock.Now
        };
        var strategy = db.Database.CreateExecutionStrategy();
        var failure = await strategy.ExecuteAsync(async () =>
        {
            await using var transaction = await db.Database.BeginTransactionAsync(ct);

            var space = new Tenant { Name = user.FullName, CreatedAt = clock.Now };
            db.Tenants.Add(space);
            await db.SaveChangesAsync(ct);

            user.TenantId = space.Id;
            var created = await users.CreateAsync(user, request.Password);
            if (!created.Succeeded)
                return string.Join(" ", created.Errors.Select(e => e.Description));
            await users.AddToRoleAsync(user, Roles.Docente);

            await transaction.CommitAsync(ct);
            return null;
        });
        if (failure is not null) return Result<AuthResponse>.Fail(Error.Validation(failure));

        return await IssueAsync(user, ip, request.DeviceName, ct);
    }

    public async Task<Result<AuthResponse>> LoginAsync(LoginRequest request, string? ip, CancellationToken ct = default)
    {
        var user = await users.FindByEmailAsync(request.Email.Trim());
        if (user is null || !user.IsActive || !await users.CheckPasswordAsync(user, request.Password))
            return Result<AuthResponse>.Fail(new Error(ErrorKind.Forbidden, "invalid_credentials", "Credenciales inválidas."));

        // Aún no hay JWT: fijamos el tenant a mano para poder leer su espacio.
        tenant.SetTenant(user.TenantId, ignoreFilter: true);

        if (user.TenantId is { } tenantId
            && !await db.Tenants.AnyAsync(t => t.Id == tenantId && t.IsActive, ct))
            return Result<AuthResponse>.Fail(new Error(ErrorKind.Forbidden, "tenant_disabled",
                "Tu cuenta está suspendida. Contacta a soporte."));

        return await IssueAsync(user, ip, request.DeviceName, ct);
    }

    public async Task<Result<AuthResponse>> RefreshAsync(RefreshRequest request, string? ip, CancellationToken ct = default)
    {
        var existing = await tokens.FindAsync(request.RefreshToken, ct);
        if (existing is null || !existing.IsActive(clock.Now))
            return Result<AuthResponse>.Fail(new Error(ErrorKind.Forbidden, "invalid_refresh_token", "Sesión expirada, vuelve a iniciar sesión."));

        var user = await users.FindByIdAsync(existing.UserId.ToString());
        if (user is null || !user.IsActive)
            return Result<AuthResponse>.Fail(new Error(ErrorKind.Forbidden, "user_disabled", "El usuario está deshabilitado."));

        var role = await RoleOfAsync(user);
        var (access, accessExpires) = tokens.CreateAccessToken(user, role);
        var (refresh, refreshEntity) = await tokens.IssueRefreshTokenAsync(user.Id, ip, existing.DeviceName, ct);

        // Rotación: el token usado queda inutilizable y apunta a su reemplazo.
        existing.RevokedAt = clock.Now;
        existing.ReplacedByTokenId = refreshEntity.Id;
        await db.SaveChangesAsync(ct);

        return new AuthResponse(new AuthTokens(access, accessExpires, refresh, refreshEntity.ExpiresAt), Profile(user, role));
    }

    public async Task<Result> LogoutAsync(string refreshToken, CancellationToken ct = default)
    {
        var existing = await tokens.FindAsync(refreshToken, ct);
        if (existing is not null && existing.RevokedAt is null)
        {
            existing.RevokedAt = clock.Now;
            await db.SaveChangesAsync(ct);
        }
        return Result.Success();
    }

    public async Task<Result<CurrentUserDto>> GetCurrentAsync(CancellationToken ct = default)
    {
        var user = await users.FindByIdAsync(currentUser.RequireUserId().ToString());
        if (user is null) return Result<CurrentUserDto>.Fail(Error.NotFound("El usuario"));
        return Profile(user, await RoleOfAsync(user));
    }

    public async Task<Result> ChangePasswordAsync(ChangePasswordRequest request, CancellationToken ct = default)
    {
        var user = await users.FindByIdAsync(currentUser.RequireUserId().ToString());
        if (user is null) return Result.Fail(Error.NotFound("El usuario"));

        var result = await users.ChangePasswordAsync(user, request.CurrentPassword, request.NewPassword);
        if (!result.Succeeded)
            return Result.Fail(Error.Validation(string.Join(" ", result.Errors.Select(e => e.Description))));

        user.MustChangePassword = false;
        await users.UpdateAsync(user);
        return Result.Success();
    }

    /// <summary>
    /// Borra la cuenta y todo lo del docente en el servidor: clases, cuadros, planes,
    /// notas, sesiones y el usuario. Es lo que piden App Store y Google Play. Lo guardado
    /// en el teléfono se borra al cerrar sesión en la app.
    /// </summary>
    public async Task<Result> DeleteAccountAsync(DeleteAccountRequest request, CancellationToken ct = default)
    {
        var user = await users.FindByIdAsync(currentUser.RequireUserId().ToString());
        if (user is null) return Result.Fail(Error.NotFound("El usuario"));
        if (!await users.CheckPasswordAsync(user, request.Password ?? ""))
            return Result.Fail(Error.Validation("La contraseña no es correcta."));

        var strategy = db.Database.CreateExecutionStrategy();
        await strategy.ExecuteAsync(async () =>
        {
            await using var tx = await db.Database.BeginTransactionAsync(ct);
            // El filtro de tenant ya limita estas consultas a lo del docente. Columnas,
            // alumnos y valores caen en cascada con su clase.
            await db.Registros.ExecuteDeleteAsync(ct);
            await db.Clases.ExecuteDeleteAsync(ct);
            await db.RefreshTokens.Where(t => t.UserId == user.Id).ExecuteDeleteAsync(ct);
            var result = await users.DeleteAsync(user);
            if (!result.Succeeded) throw new InvalidOperationException(string.Join(" ", result.Errors.Select(e => e.Description)));
            if (user.TenantId is Guid tenantId)
                await db.Tenants.Where(t => t.Id == tenantId).ExecuteDeleteAsync(ct);
            await tx.CommitAsync(ct);
        });
        return Result.Success();
    }

    private async Task<AuthResponse> IssueAsync(AppUser user, string? ip, string? deviceName, CancellationToken ct)
    {
        var role = await RoleOfAsync(user);
        var (access, accessExpires) = tokens.CreateAccessToken(user, role);
        var (refresh, refreshEntity) = await tokens.IssueRefreshTokenAsync(user.Id, ip, deviceName, ct);

        user.LastLoginAt = clock.Now;
        await users.UpdateAsync(user);

        return new AuthResponse(new AuthTokens(access, accessExpires, refresh, refreshEntity.ExpiresAt), Profile(user, role));
    }

    private async Task<string> RoleOfAsync(AppUser user) =>
        (await users.GetRolesAsync(user)).FirstOrDefault() ?? Roles.Docente;

    private static CurrentUserDto Profile(AppUser user, string role) =>
        new(user.Id, user.Email!, user.FullName, role, user.TenantId, user.MustChangePassword);
}
