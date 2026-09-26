using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using ProfeApp.Domain.Cuadros;
using ProfeApp.Domain.Tenants;

namespace ProfeApp.Application.Abstractions;

/// <summary>
/// Puerto de persistencia. Expone los DbSet directamente: el filtro global de tenant
/// ya está aplicado en la configuración, así que las consultas de Application son seguras.
/// </summary>
public interface IAppDbContext
{
    DbSet<Tenant> Tenants { get; }
    DbSet<Clase> Clases { get; }
    DbSet<ClaseColumna> ClaseColumnas { get; }
    DbSet<ClaseAlumno> ClaseAlumnos { get; }
    DbSet<ClaseValor> ClaseValores { get; }

    DatabaseFacade Database { get; }
    Task<int> SaveChangesAsync(CancellationToken ct = default);
}
