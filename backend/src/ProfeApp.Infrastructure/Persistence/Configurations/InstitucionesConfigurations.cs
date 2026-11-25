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

        // El documento fiscal que dejó el pago. Los largos son los de allá: el número y el
        // CAI vienen de la facturación central, el motivo del fallo se guarda recortado.
        b.Property(x => x.NumeroDocumento).HasMaxLength(40);
        b.Property(x => x.CaiDocumento).HasMaxLength(50);
        b.Property(x => x.ErrorDocumento).HasMaxLength(300);

        // El historial de una cuenta, del último hacia atrás, y su último pago en las listas.
        b.HasIndex(x => new { x.CuentaId, x.PagadoEl });

        // Para contestar «¿de qué pago es esta factura?» con el número en la mano.
        b.HasIndex(x => x.NumeroDocumento);
    }
}

internal static class CobroConfig
{
    public static void ConfigurarCobro<T>(this EntityTypeBuilder<T> b) where T : class, ICobrable
    {
        b.Property(x => x.PlanNombre).HasMaxLength(80);
        b.Property(x => x.Monto).HasPrecision(12, 2);
        b.Property(x => x.ComoPagar).HasMaxLength(500);
        b.Property(x => x.Rtn).HasMaxLength(20);
    }
}
