using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ProfeApp.Domain.Centros;
using ProfeApp.Domain.Instituciones;
using ProfeApp.Infrastructure.Identity;

namespace ProfeApp.Infrastructure.Persistence.Configurations;

public class AnioLectivoConfig : IEntityTypeConfiguration<AnioLectivo>
{
    public void Configure(EntityTypeBuilder<AnioLectivo> b)
    {
        b.ToTable("anios_lectivos");
        b.HasOne<Institucion>().WithMany().HasForeignKey(x => x.InstitucionId).OnDelete(DeleteBehavior.Cascade);
        b.HasIndex(x => new { x.InstitucionId, x.Anio }).IsUnique();
        // Un solo año actual por centro.
        b.HasIndex(x => x.InstitucionId).IsUnique().HasFilter("actual").HasDatabaseName("ix_anios_lectivos_actual");
    }
}

public class GradoConfig : IEntityTypeConfiguration<Grado>
{
    public void Configure(EntityTypeBuilder<Grado> b)
    {
        b.ToTable("grados");
        b.Property(x => x.Nivel).HasMaxLength(20).IsRequired();
        b.Property(x => x.Nombre).HasMaxLength(80).IsRequired();
        b.HasOne<Institucion>().WithMany().HasForeignKey(x => x.InstitucionId).OnDelete(DeleteBehavior.Cascade);
        b.HasIndex(x => new { x.InstitucionId, x.Nombre }).IsUnique();
    }
}

public class AsignaturaGradoConfig : IEntityTypeConfiguration<AsignaturaGrado>
{
    public void Configure(EntityTypeBuilder<AsignaturaGrado> b)
    {
        b.ToTable("asignaturas_grado");
        b.Property(x => x.Nombre).HasMaxLength(120).IsRequired();
        b.HasOne<Grado>().WithMany().HasForeignKey(x => x.GradoId).OnDelete(DeleteBehavior.Cascade);
        b.HasIndex(x => new { x.GradoId, x.Nombre }).IsUnique();
        b.HasIndex(x => x.InstitucionId);
    }
}

public class AulaConfig : IEntityTypeConfiguration<Aula>
{
    public void Configure(EntityTypeBuilder<Aula> b)
    {
        b.ToTable("aulas");
        b.Property(x => x.Nombre).HasMaxLength(80).IsRequired();
        b.HasOne<Institucion>().WithMany().HasForeignKey(x => x.InstitucionId).OnDelete(DeleteBehavior.Cascade);
        b.HasIndex(x => new { x.InstitucionId, x.Nombre }).IsUnique();
    }
}

public class SeccionConfig : IEntityTypeConfiguration<Seccion>
{
    public void Configure(EntityTypeBuilder<Seccion> b)
    {
        b.ToTable("secciones");
        b.Property(x => x.Nombre).HasMaxLength(20).IsRequired();
        b.Property(x => x.Jornada).HasMaxLength(20).IsRequired();
        b.HasOne<AnioLectivo>().WithMany().HasForeignKey(x => x.AnioLectivoId).OnDelete(DeleteBehavior.Restrict);
        b.HasOne<Grado>().WithMany().HasForeignKey(x => x.GradoId).OnDelete(DeleteBehavior.Restrict);
        b.HasOne<Aula>().WithMany().HasForeignKey(x => x.AulaId).OnDelete(DeleteBehavior.SetNull);
        b.HasOne<AppUser>().WithMany().HasForeignKey(x => x.MaestroGuiaId).OnDelete(DeleteBehavior.SetNull);
        b.HasIndex(x => new { x.AnioLectivoId, x.GradoId, x.Jornada, x.Nombre }).IsUnique();
        b.HasIndex(x => x.InstitucionId);
    }
}

public class CargaDocenteConfig : IEntityTypeConfiguration<CargaDocente>
{
    public void Configure(EntityTypeBuilder<CargaDocente> b)
    {
        b.ToTable("cargas_docentes");
        b.HasOne<Seccion>().WithMany().HasForeignKey(x => x.SeccionId).OnDelete(DeleteBehavior.Cascade);
        b.HasOne<AsignaturaGrado>().WithMany().HasForeignKey(x => x.AsignaturaGradoId).OnDelete(DeleteBehavior.Cascade);
        // Si el docente elimina su cuenta, su carga queda libre.
        b.HasOne<AppUser>().WithMany().HasForeignKey(x => x.DocenteId).OnDelete(DeleteBehavior.Cascade);
        b.HasIndex(x => new { x.SeccionId, x.AsignaturaGradoId }).IsUnique();
        b.HasIndex(x => x.DocenteId);
    }
}
