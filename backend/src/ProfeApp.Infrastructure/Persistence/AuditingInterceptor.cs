using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using ProfeApp.Application.Abstractions;
using ProfeApp.Domain.Common;

namespace ProfeApp.Infrastructure.Persistence;

/// <summary>
/// Estampa tenant y auditoría en cada guardado. Es el único lugar donde se asigna
/// TenantId: así ninguna operación puede "olvidarlo" y mezclar datos de dos docentes.
/// </summary>
public sealed class AuditingInterceptor(ITenantContext tenant, ICurrentUser user, IClock clock)
    : SaveChangesInterceptor
{
    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData, InterceptionResult<int> result, CancellationToken ct = default)
    {
        if (eventData.Context is not null) Apply(eventData.Context);
        return base.SavingChangesAsync(eventData, result, ct);
    }

    public override InterceptionResult<int> SavingChanges(
        DbContextEventData eventData, InterceptionResult<int> result)
    {
        if (eventData.Context is not null) Apply(eventData.Context);
        return base.SavingChanges(eventData, result);
    }

    private void Apply(DbContext context)
    {
        var now = clock.Now;
        var userId = user.UserId;

        foreach (var entry in context.ChangeTracker.Entries())
        {
            if (entry.Entity is IMustHaveTenant scoped && entry.State is EntityState.Added
                && scoped.TenantId == Guid.Empty)
            {
                scoped.TenantId = tenant.RequireTenantId();
            }

            if (entry.Entity is not BaseEntity auditable) continue;
            switch (entry.State)
            {
                case EntityState.Added:
                    if (auditable.CreatedAt == default) auditable.CreatedAt = now;
                    auditable.CreatedBy ??= userId;
                    break;
                case EntityState.Modified:
                    auditable.UpdatedAt = now;
                    auditable.UpdatedBy = userId;
                    break;
            }
        }
    }
}
