using System.Security.Claims;
using ProfeApp.Application.Abstractions;
using ProfeApp.Domain.Common;
using ProfeApp.Infrastructure.Identity;

namespace ProfeApp.Api.Auth;

/// <summary>Tenant resuelto del claim del JWT. Es la base del aislamiento entre docentes.</summary>
public sealed class HttpTenantContext(IHttpContextAccessor accessor) : ITenantContext
{
    private Guid? _override;
    private bool _ignoreFilter;
    private bool _hasOverride;

    public Guid? TenantId => _hasOverride
        ? _override
        : Guid.TryParse(accessor.HttpContext?.User.FindFirstValue(AppClaims.TenantId), out var id) ? id : null;

    public bool IgnoreTenantFilter => _hasOverride
        ? _ignoreFilter
        : accessor.HttpContext?.User.IsInRole(Roles.PlatformAdmin) == true;

    public Guid RequireTenantId() => TenantId
        ?? throw new InvalidOperationException("La petición no tiene tenant asociado.");

    public void SetTenant(Guid? tenantId, bool ignoreFilter = false)
    {
        _override = tenantId;
        _hasOverride = true;
        _ignoreFilter = ignoreFilter;
    }
}

public sealed class HttpCurrentUser(IHttpContextAccessor accessor) : ICurrentUser
{
    private ClaimsPrincipal? Principal => accessor.HttpContext?.User;

    public Guid? UserId => Guid.TryParse(Principal?.FindFirstValue("sub")
        ?? Principal?.FindFirstValue(ClaimTypes.NameIdentifier), out var id) ? id : null;

    public string? Email => Principal?.FindFirstValue("email") ?? Principal?.FindFirstValue(ClaimTypes.Email);
    public string? Role => Principal?.FindFirstValue(ClaimTypes.Role);

    public Guid RequireUserId() => UserId ?? throw new UnauthorizedAccessException("Sin usuario autenticado.");
}
