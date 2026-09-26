using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ProfeApp.Domain.Planes;

namespace ProfeApp.Infrastructure.Persistence.Configurations;

public class RegistroConfig : IEntityTypeConfiguration<Registro>
{
    public void Configure(EntityTypeBuilder<Registro> b)
    {
        b.ToTable("registros");
        b.Property(x => x.Tipo).HasMaxLength(20).IsRequired();
        b.Property(x => x.ClaseClave).HasMaxLength(600).IsRequired();
        b.Property(x => x.Clave).HasMaxLength(200).IsRequired();
        b.Property(x => x.Datos).HasColumnType("jsonb");
        b.HasIndex(x => new { x.TenantId, x.Tipo, x.ClaseClave, x.Clave }).IsUnique();
        b.HasIndex(x => new { x.TenantId, x.ModificadoEn });
    }
}
