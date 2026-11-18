using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using ProfeApp.Application.Abstractions;
using ProfeApp.Domain.Centros;
using ProfeApp.Domain.Cobros;
using ProfeApp.Domain.Cuadros;
using ProfeApp.Domain.Instituciones;
using ProfeApp.Domain.Planes;
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
    public DbSet<Clase> Clases => Set<Clase>();
    public DbSet<ClaseColumna> ClaseColumnas => Set<ClaseColumna>();
    public DbSet<ClaseAlumno> ClaseAlumnos => Set<ClaseAlumno>();
    public DbSet<ClaseValor> ClaseValores => Set<ClaseValor>();
    public DbSet<Registro> Registros => Set<Registro>();
    public DbSet<Institucion> Instituciones => Set<Institucion>();
    public DbSet<Pago> Pagos => Set<Pago>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<AnioLectivo> AniosLectivos => Set<AnioLectivo>();
    public DbSet<Grado> Grados => Set<Grado>();
    public DbSet<AsignaturaGrado> AsignaturasGrado => Set<AsignaturaGrado>();
    public DbSet<Aula> Aulas => Set<Aula>();
    public DbSet<Seccion> Secciones => Set<Seccion>();
    public DbSet<CargaDocente> CargasDocentes => Set<CargaDocente>();

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
