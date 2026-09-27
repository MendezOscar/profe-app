using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ProfeApp.Domain.Instituciones;

namespace ProfeApp.Infrastructure.Persistence.Configurations;

public class InstitucionConfig : IEntityTypeConfiguration<Institucion>
{
    public void Configure(EntityTypeBuilder<Institucion> b)
    {
        b.ToTable("instituciones");
        b.Property(x => x.Nombre).HasMaxLength(200).IsRequired();
        b.Property(x => x.Plan).HasMaxLength(20).IsRequired();
    }
}
