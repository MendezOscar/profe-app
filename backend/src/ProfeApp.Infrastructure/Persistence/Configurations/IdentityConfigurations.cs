using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ProfeApp.Domain.Instituciones;
using ProfeApp.Domain.Tenants;
using ProfeApp.Infrastructure.Identity;

namespace ProfeApp.Infrastructure.Persistence.Configurations;

public class TenantConfig : IEntityTypeConfiguration<Tenant>
{
    public void Configure(EntityTypeBuilder<Tenant> b)
    {
        b.ToTable("tenants");
        b.Property(x => x.Name).HasMaxLength(160).IsRequired();
        b.Property(x => x.Nivel).HasMaxLength(20);
        b.ConfigurarCobro();
    }
}

public class AppUserConfig : IEntityTypeConfiguration<AppUser>
{
    public void Configure(EntityTypeBuilder<AppUser> b)
    {
        b.Property(x => x.FullName).HasMaxLength(160).IsRequired();
        b.Property(x => x.Cargo).HasMaxLength(20);
        b.HasIndex(x => x.TenantId);
        b.HasOne<Tenant>().WithMany().HasForeignKey(x => x.TenantId).OnDelete(DeleteBehavior.Restrict);
        b.HasIndex(x => x.InstitucionId);
        b.HasOne<Institucion>().WithMany().HasForeignKey(x => x.InstitucionId).OnDelete(DeleteBehavior.Restrict);
    }
}

public class RefreshTokenConfig : IEntityTypeConfiguration<RefreshToken>
{
    public void Configure(EntityTypeBuilder<RefreshToken> b)
    {
        b.ToTable("refresh_tokens");
        b.Property(x => x.TokenHash).HasMaxLength(88).IsRequired();
        b.Property(x => x.CreatedByIp).HasMaxLength(60);
        b.Property(x => x.DeviceName).HasMaxLength(120);
        b.HasIndex(x => x.TokenHash).IsUnique();
        b.HasIndex(x => x.UserId);
        b.HasOne<AppUser>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
    }
}

public class DispositivoPushConfig : IEntityTypeConfiguration<ProfeApp.Domain.Common.DispositivoPush>
{
    public void Configure(EntityTypeBuilder<ProfeApp.Domain.Common.DispositivoPush> b)
    {
        b.ToTable("dispositivos_push");
        b.Property(x => x.Token).HasMaxLength(512).IsRequired();
        b.Property(x => x.Plataforma).HasMaxLength(10).IsRequired();
        b.HasOne<AppUser>().WithMany().HasForeignKey(x => x.UsuarioId).OnDelete(DeleteBehavior.Cascade);
        b.HasIndex(x => x.Token).IsUnique();
        b.HasIndex(x => x.UsuarioId);
    }
}

public class UsoIaConfig : IEntityTypeConfiguration<ProfeApp.Domain.Common.UsoIa>
{
    public void Configure(EntityTypeBuilder<ProfeApp.Domain.Common.UsoIa> b)
    {
        b.ToTable("usos_ia");
        b.Property(x => x.Funcion).HasMaxLength(20).IsRequired();
        b.Property(x => x.Modelo).HasMaxLength(60).IsRequired();
        b.HasOne<AppUser>().WithMany().HasForeignKey(x => x.UsuarioId).OnDelete(DeleteBehavior.Cascade);
        b.HasIndex(x => new { x.UsuarioId, x.CreatedAt });
        b.HasIndex(x => new { x.InstitucionId, x.CreatedAt });
    }
}

public class TandaIaConfig : IEntityTypeConfiguration<ProfeApp.Domain.Common.TandaIa>
{
    public void Configure(EntityTypeBuilder<ProfeApp.Domain.Common.TandaIa> b)
    {
        b.ToTable("tandas_ia");
        b.Property(x => x.Actividad).HasMaxLength(64).IsRequired();
        b.Property(x => x.Lote).HasMaxLength(100).IsRequired();
        b.Property(x => x.Estado).HasMaxLength(20).IsRequired();
        b.Property(x => x.Puntos).HasPrecision(6, 2);
        b.Property(x => x.Resultados).HasColumnType("jsonb");
        b.Property(x => x.Paginas).HasColumnType("jsonb");
        b.HasOne<AppUser>().WithMany().HasForeignKey(x => x.UsuarioId).OnDelete(DeleteBehavior.Cascade);
        b.HasIndex(x => new { x.UsuarioId, x.Actividad });
        b.HasIndex(x => x.Estado);
    }
}
