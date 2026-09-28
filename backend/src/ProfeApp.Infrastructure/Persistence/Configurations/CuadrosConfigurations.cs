using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ProfeApp.Domain.Cuadros;

namespace ProfeApp.Infrastructure.Persistence.Configurations;

public class ClaseConfig : IEntityTypeConfiguration<Clase>
{
    public void Configure(EntityTypeBuilder<Clase> b)
    {
        b.ToTable("clases");
        b.Property(x => x.Clave).HasMaxLength(600).IsRequired();
        b.Property(x => x.CodigoCentro).HasMaxLength(40);
        b.Property(x => x.Centro).HasMaxLength(200);
        b.Property(x => x.Modalidad).HasMaxLength(200);
        b.Property(x => x.GradoSeccion).HasMaxLength(120);
        b.Property(x => x.Jornada).HasMaxLength(60);
        b.Property(x => x.Asignatura).HasMaxLength(160);
        b.Property(x => x.Hoja).HasMaxLength(100).IsRequired();
        b.Property(x => x.ArchivoNombre).HasMaxLength(255).IsRequired();
        b.HasIndex(x => new { x.TenantId, x.Clave }).IsUnique();
        b.HasIndex(x => new { x.TenantId, x.ModificadoEn });
        b.HasMany(x => x.Columnas).WithOne().HasForeignKey(x => x.ClaseId).OnDelete(DeleteBehavior.Cascade);
        b.HasMany(x => x.Alumnos).WithOne().HasForeignKey(x => x.ClaseId).OnDelete(DeleteBehavior.Cascade);
        b.HasMany(x => x.Valores).WithOne().HasForeignKey(x => x.ClaseId).OnDelete(DeleteBehavior.Cascade);
        // Table splitting: el archivo vive en la misma fila pero es otra entidad, así cargar
        // la clase (en cada push y pull) no arrastra los bytes.
        b.HasOne(x => x.Archivo).WithOne().HasForeignKey<ClaseArchivo>(x => x.Id);
        b.Navigation(x => x.Archivo).IsRequired();
    }
}

public class ClaseArchivoConfig : IEntityTypeConfiguration<ClaseArchivo>
{
    public void Configure(EntityTypeBuilder<ClaseArchivo> b)
    {
        b.ToTable("clases");
        b.Property(x => x.Contenido).HasColumnName("archivo").IsRequired();
    }
}

public class ClaseColumnaConfig : IEntityTypeConfiguration<ClaseColumna>
{
    public void Configure(EntityTypeBuilder<ClaseColumna> b)
    {
        b.ToTable("clase_columnas");
        b.Property(x => x.Clave).HasMaxLength(300).IsRequired();
        b.Property(x => x.Grupo).HasMaxLength(150).IsRequired();
        b.Property(x => x.Nombre).HasMaxLength(150).IsRequired();
        b.Property(x => x.Tipo).HasMaxLength(30).IsRequired();
        b.HasIndex(x => new { x.ClaseId, x.Clave }).IsUnique();
    }
}

public class ClaseAlumnoConfig : IEntityTypeConfiguration<ClaseAlumno>
{
    public void Configure(EntityTypeBuilder<ClaseAlumno> b)
    {
        b.ToTable("clase_alumnos");
        b.Property(x => x.Clave).HasMaxLength(200).IsRequired();
        b.Property(x => x.Identidad).HasMaxLength(30).IsRequired();
        b.Property(x => x.Documento).HasMaxLength(20).IsRequired();
        b.Property(x => x.Nombre).HasMaxLength(200).IsRequired();
        b.HasIndex(x => new { x.ClaseId, x.Clave }).IsUnique();
    }
}

public class ClaseValorConfig : IEntityTypeConfiguration<ClaseValor>
{
    public void Configure(EntityTypeBuilder<ClaseValor> b)
    {
        b.ToTable("clase_valores");
        b.Property(x => x.AlumnoClave).HasMaxLength(200).IsRequired();
        b.Property(x => x.ColumnaClave).HasMaxLength(300).IsRequired();
        b.HasIndex(x => new { x.ClaseId, x.AlumnoClave, x.ColumnaClave }).IsUnique();
        b.HasIndex(x => new { x.ClaseId, x.ModificadoEn });
    }
}
