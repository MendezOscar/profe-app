using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ProfeApp.Domain.Cobros;
using ProfeApp.Domain.Instituciones;

namespace ProfeApp.Infrastructure.Persistence.Configurations;

public class InstitucionConfig : IEntityTypeConfiguration<Institucion>
{
    public void Configure(EntityTypeBuilder<Institucion> b)
    {
        b.ToTable("instituciones");
        b.Property(x => x.Nombre).HasMaxLength(200).IsRequired();
        b.Property(x => x.Plan).HasMaxLength(20).IsRequired();
        b.ConfigurarCobro();
    }
}

public class PagoConfig : IEntityTypeConfiguration<Pago>
{
    public void Configure(EntityTypeBuilder<Pago> b)
    {
        b.ToTable("pagos");
        b.Property(x => x.Monto).HasPrecision(12, 2);
        b.Property(x => x.Referencia).HasMaxLength(200);
        // El historial de una cuenta, del último hacia atrás, y su último pago en las listas.
        b.HasIndex(x => new { x.CuentaId, x.PagadoEl });
    }
}

internal static class CobroConfig
{
    public static void ConfigurarCobro<T>(this EntityTypeBuilder<T> b) where T : class, ICobrable
    {
        b.Property(x => x.PlanNombre).HasMaxLength(80);
        b.Property(x => x.Monto).HasPrecision(12, 2);
        b.Property(x => x.ComoPagar).HasMaxLength(500);
    }
}
