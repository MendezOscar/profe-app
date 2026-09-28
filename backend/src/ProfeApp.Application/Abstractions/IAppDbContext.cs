using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Infrastructure;
using ProfeApp.Domain.Cuadros;
using ProfeApp.Domain.Planes;
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
    DbSet<Registro> Registros { get; }

    DatabaseFacade Database { get; }

    /// <summary>Para cargar a pedido lo que no se trae al consultar (el archivo de una clase).</summary>
    EntityEntry<TEntity> Entry<TEntity>(TEntity entity) where TEntity : class;
    Task<int> SaveChangesAsync(CancellationToken ct = default);
}
