namespace ProfeApp.Application.Abstractions;

/// <summary>Tenant resuelto del JWT. Alimenta el filtro global de EF Core.</summary>
public interface ITenantContext
{
    Guid? TenantId { get; }
    bool IgnoreTenantFilter { get; }
    Guid RequireTenantId();
    /// <summary>Sólo para login, registro, seeds y jobs de background.</summary>
    void SetTenant(Guid? tenantId, bool ignoreFilter = false);
}

public interface ICurrentUser
{
    Guid? UserId { get; }
    string? Email { get; }
    string? Role { get; }
    Guid RequireUserId();
}

public interface IClock
{
    DateTimeOffset Now { get; }
    DateOnly Today { get; }
}
