using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using ProfeApp.Application.Abstractions;
using ProfeApp.Domain.Tenants;
using ProfeApp.Infrastructure.Identity;

namespace ProfeApp.Infrastructure.Persistence;

public class AppDbContext(DbContextOptions<AppDbContext> options, ITenantContext? tenant = null)
    : IdentityDbContext<AppUser, AppRole, Guid>(options), IAppDbContext
{
    private readonly ITenantContext? _tenant = tenant;

    /// <summary>Guid.Empty cuando no hay tenant resuelto: así ninguna fila calza.</summary>
    public Guid CurrentTenantId => _tenant?.TenantId ?? Guid.Empty;
    public bool IgnoreTenantFilter => _tenant?.IgnoreTenantFilter ?? false;

    public DbSet<Tenant> Tenants => Set<Tenant>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();

    protected override void OnModelCreating(ModelBuilder builder)
    {
        base.OnModelCreating(builder);
        builder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
        builder.ApplyClientGeneratedKeys();
        builder.ApplySnakeCaseNames();
        builder.ApplyTenantAndSoftDeleteFilters(this);
    }

    Task<int> IAppDbContext.SaveChangesAsync(CancellationToken ct) => base.SaveChangesAsync(ct);
}
