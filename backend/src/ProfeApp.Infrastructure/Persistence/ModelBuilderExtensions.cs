using System.Linq.Expressions;
using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata;
using ProfeApp.Domain.Common;

namespace ProfeApp.Infrastructure.Persistence;

public static partial class ModelBuilderExtensions
{
    /// <summary>Tablas y columnas en snake_case, como es idiomático en PostgreSQL.</summary>
    public static void ApplySnakeCaseNames(this ModelBuilder builder)
    {
        foreach (var entity in builder.Model.GetEntityTypes())
        {
            if (entity.IsOwned()) continue;
            var table = entity.GetTableName();
            if (table is not null) entity.SetTableName(ToSnake(table));

            var storeObject = StoreObjectIdentifier.Table(
                entity.GetTableName() ?? string.Empty, entity.GetSchema());

            foreach (var property in entity.GetProperties())
                property.SetColumnName(ToSnake(property.GetColumnName(storeObject) ?? property.Name));

            foreach (var key in entity.GetKeys())
                key.SetName(ToSnake(key.GetName() ?? string.Empty));
            foreach (var fk in entity.GetForeignKeys())
                fk.SetConstraintName(ToSnake(fk.GetConstraintName() ?? string.Empty));
            foreach (var index in entity.GetIndexes())
                index.SetDatabaseName(ToSnake(index.GetDatabaseName() ?? string.Empty));
        }
    }

    /// <summary>
    /// Los Guid de las entidades de dominio los genera el código (BaseEntity), no la base.
    /// Sin esto EF ve un Id ya asignado en una entidad agregada por navegación y emite
    /// un UPDATE en vez de un INSERT.
    /// </summary>
    public static void ApplyClientGeneratedKeys(this ModelBuilder builder)
    {
        foreach (var entity in builder.Model.GetEntityTypes())
        {
            if (!typeof(BaseEntity).IsAssignableFrom(entity.ClrType)) continue;
            var key = entity.FindPrimaryKey();
            if (key is null) continue;
            foreach (var property in key.Properties.Where(p => p.ClrType == typeof(Guid)))
                property.ValueGenerated = ValueGenerated.Never;
        }
    }

    /// <summary>
    /// Filtro global de tenant + soft delete para toda entidad que lo requiera.
    /// El tenant se lee del contexto en cada consulta, así que EF lo parametriza.
    /// </summary>
    public static void ApplyTenantAndSoftDeleteFilters(this ModelBuilder builder, AppDbContext context)
    {
        foreach (var entity in builder.Model.GetEntityTypes())
        {
            var clr = entity.ClrType;
            if (entity.BaseType is not null) continue;

            var isTenant = typeof(IMustHaveTenant).IsAssignableFrom(clr);
            var isSoftDelete = typeof(ISoftDelete).IsAssignableFrom(clr);
            if (!isTenant && !isSoftDelete) continue;

            var parameter = Expression.Parameter(clr, "e");
            Expression? body = null;

            if (isTenant)
            {
                // e.TenantId == context.CurrentTenantId || context.IgnoreTenantFilter
                var tenantProp = Expression.Property(parameter, nameof(IMustHaveTenant.TenantId));
                var currentTenant = Expression.Property(
                    Expression.Constant(context), nameof(AppDbContext.CurrentTenantId));
                var bypass = Expression.Property(
                    Expression.Constant(context), nameof(AppDbContext.IgnoreTenantFilter));
                body = Expression.OrElse(Expression.Equal(tenantProp, currentTenant), bypass);
            }

            if (isSoftDelete)
            {
                var deletedProp = Expression.Property(parameter, nameof(ISoftDelete.DeletedAt));
                var notDeleted = Expression.Equal(deletedProp, Expression.Constant(null, typeof(DateTimeOffset?)));
                body = body is null ? notDeleted : Expression.AndAlso(body, notDeleted);
            }

            entity.SetQueryFilter(Expression.Lambda(body!, parameter));
        }
    }

    private static string ToSnake(string name) => string.IsNullOrEmpty(name)
        ? name
        : SnakeRegex().Replace(name, "$1_$2").ToLowerInvariant();

    [GeneratedRegex("([a-z0-9])([A-Z])")]
    private static partial Regex SnakeRegex();
}
