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

public class AlumnoConfig : IEntityTypeConfiguration<Alumno>
{
    public void Configure(EntityTypeBuilder<Alumno> b)
    {
        b.ToTable("alumnos");
        b.Property(x => x.Identidad).HasMaxLength(30).IsRequired();
        b.Property(x => x.Nombre).HasMaxLength(160).IsRequired();
        b.Property(x => x.Sexo).HasMaxLength(1);
        b.Property(x => x.Direccion).HasMaxLength(300);
        b.Property(x => x.Salud).HasMaxLength(1000);
        b.Property(x => x.Notas).HasMaxLength(1000);
        b.HasOne<Institucion>().WithMany().HasForeignKey(x => x.InstitucionId).OnDelete(DeleteBehavior.Cascade);
        b.HasIndex(x => new { x.InstitucionId, x.Identidad }).IsUnique();
    }
}

public class EncargadoConfig : IEntityTypeConfiguration<Encargado>
{
    public void Configure(EntityTypeBuilder<Encargado> b)
    {
        b.ToTable("encargados");
        b.Property(x => x.Nombre).HasMaxLength(160).IsRequired();
        b.Property(x => x.Parentesco).HasMaxLength(40);
        b.Property(x => x.Telefono).HasMaxLength(30);
        b.Property(x => x.Correo).HasMaxLength(160);
        b.HasOne<Alumno>().WithMany().HasForeignKey(x => x.AlumnoId).OnDelete(DeleteBehavior.Cascade);
        b.HasIndex(x => x.AlumnoId);
    }
}

public class MatriculaConfig : IEntityTypeConfiguration<Matricula>
{
    public void Configure(EntityTypeBuilder<Matricula> b)
    {
        b.ToTable("matriculas");
        b.Property(x => x.Tipo).HasMaxLength(20).IsRequired();
        b.Property(x => x.Estado).HasMaxLength(20).IsRequired();
        b.Property(x => x.MotivoBaja).HasMaxLength(300);
        b.HasOne<Alumno>().WithMany().HasForeignKey(x => x.AlumnoId).OnDelete(DeleteBehavior.Cascade);
        b.HasOne<AnioLectivo>().WithMany().HasForeignKey(x => x.AnioLectivoId).OnDelete(DeleteBehavior.Restrict);
        // Una sección con alumnos no se borra: primero se mueven o se retiran.
        b.HasOne<Seccion>().WithMany().HasForeignKey(x => x.SeccionId).OnDelete(DeleteBehavior.Restrict);
        b.HasIndex(x => new { x.AlumnoId, x.AnioLectivoId }).IsUnique();
        b.HasIndex(x => new { x.SeccionId, x.Estado });
    }
}

public class CodigoFamiliaConfig : IEntityTypeConfiguration<CodigoFamilia>
{
    public void Configure(EntityTypeBuilder<CodigoFamilia> b)
    {
        b.ToTable("codigos_familia");
        b.Property(x => x.Codigo).HasMaxLength(12).IsRequired();
        b.HasOne<Alumno>().WithMany().HasForeignKey(x => x.AlumnoId).OnDelete(DeleteBehavior.Cascade);
        b.HasIndex(x => x.Codigo).IsUnique();
        b.HasIndex(x => x.AlumnoId).IsUnique();
    }
}

public class VinculoFamiliarConfig : IEntityTypeConfiguration<VinculoFamiliar>
{
    public void Configure(EntityTypeBuilder<VinculoFamiliar> b)
    {
        b.ToTable("vinculos_familiares");
        b.HasOne<Alumno>().WithMany().HasForeignKey(x => x.AlumnoId).OnDelete(DeleteBehavior.Cascade);
        b.HasOne<AppUser>().WithMany().HasForeignKey(x => x.UsuarioId).OnDelete(DeleteBehavior.Cascade);
        b.HasIndex(x => new { x.AlumnoId, x.UsuarioId }).IsUnique();
        b.HasIndex(x => x.UsuarioId);
    }
}

public class ComunicadoConfig : IEntityTypeConfiguration<Comunicado>
{
    public void Configure(EntityTypeBuilder<Comunicado> b)
    {
        b.ToTable("comunicados");
        b.Property(x => x.Titulo).HasMaxLength(160).IsRequired();
        b.Property(x => x.Cuerpo).HasMaxLength(4000).IsRequired();
        b.HasOne<Institucion>().WithMany().HasForeignKey(x => x.InstitucionId).OnDelete(DeleteBehavior.Cascade);
        b.HasIndex(x => new { x.InstitucionId, x.PublicadoEn });
    }
}

public class LecturaComunicadoConfig : IEntityTypeConfiguration<LecturaComunicado>
{
    public void Configure(EntityTypeBuilder<LecturaComunicado> b)
    {
        b.ToTable("lecturas_comunicados");
        b.HasOne<Comunicado>().WithMany().HasForeignKey(x => x.ComunicadoId).OnDelete(DeleteBehavior.Cascade);
        b.HasOne<AppUser>().WithMany().HasForeignKey(x => x.UsuarioId).OnDelete(DeleteBehavior.Cascade);
        b.HasIndex(x => new { x.ComunicadoId, x.UsuarioId }).IsUnique();
    }
}

public class BloqueHorarioConfig : IEntityTypeConfiguration<BloqueHorario>
{
    public void Configure(EntityTypeBuilder<BloqueHorario> b)
    {
        b.ToTable("bloques_horario");
        b.Property(x => x.Jornada).HasMaxLength(20).IsRequired();
        b.HasOne<Institucion>().WithMany().HasForeignKey(x => x.InstitucionId).OnDelete(DeleteBehavior.Cascade);
        b.HasIndex(x => new { x.InstitucionId, x.Jornada, x.Orden });
    }
}

public class HorarioClaseConfig : IEntityTypeConfiguration<HorarioClase>
{
    public void Configure(EntityTypeBuilder<HorarioClase> b)
    {
        b.ToTable("horarios_clase");
        b.HasOne<Seccion>().WithMany().HasForeignKey(x => x.SeccionId).OnDelete(DeleteBehavior.Cascade);
        b.HasOne<BloqueHorario>().WithMany().HasForeignKey(x => x.BloqueId).OnDelete(DeleteBehavior.Cascade);
        b.HasOne<AsignaturaGrado>().WithMany().HasForeignKey(x => x.AsignaturaGradoId).OnDelete(DeleteBehavior.Cascade);
        b.HasOne<Aula>().WithMany().HasForeignKey(x => x.AulaId).OnDelete(DeleteBehavior.SetNull);
        b.HasIndex(x => new { x.SeccionId, x.Dia, x.BloqueId }).IsUnique();
        b.HasIndex(x => new { x.InstitucionId, x.Dia });
    }
}

public class TomaAsistenciaDiariaConfig : IEntityTypeConfiguration<TomaAsistenciaDiaria>
{
    public void Configure(EntityTypeBuilder<TomaAsistenciaDiaria> b)
    {
        b.ToTable("tomas_asistencia_diaria");
        b.HasOne<Seccion>().WithMany().HasForeignKey(x => x.SeccionId).OnDelete(DeleteBehavior.Cascade);
        b.HasIndex(x => new { x.SeccionId, x.Fecha }).IsUnique();
    }
}

public class MarcaAsistenciaDiariaConfig : IEntityTypeConfiguration<MarcaAsistenciaDiaria>
{
    public void Configure(EntityTypeBuilder<MarcaAsistenciaDiaria> b)
    {
        b.ToTable("marcas_asistencia_diaria");
        b.Property(x => x.Estado).HasMaxLength(1).IsRequired();
        b.HasOne<TomaAsistenciaDiaria>().WithMany().HasForeignKey(x => x.TomaId).OnDelete(DeleteBehavior.Cascade);
        b.HasOne<Alumno>().WithMany().HasForeignKey(x => x.AlumnoId).OnDelete(DeleteBehavior.Cascade);
        b.HasIndex(x => new { x.TomaId, x.AlumnoId }).IsUnique();
        b.HasIndex(x => x.AlumnoId);
    }
}

public class ConductaParcialConfig : IEntityTypeConfiguration<ConductaParcial>
{
    public void Configure(EntityTypeBuilder<ConductaParcial> b)
    {
        b.ToTable("conductas");
        b.Property(x => x.Nota).HasMaxLength(1).IsRequired();
        b.HasOne<Seccion>().WithMany().HasForeignKey(x => x.SeccionId).OnDelete(DeleteBehavior.Cascade);
        b.HasOne<Alumno>().WithMany().HasForeignKey(x => x.AlumnoId).OnDelete(DeleteBehavior.Cascade);
        b.HasIndex(x => new { x.SeccionId, x.AlumnoId, x.Parcial }).IsUnique();
    }
}

public class ExcusaConfig : IEntityTypeConfiguration<Excusa>
{
    public void Configure(EntityTypeBuilder<Excusa> b)
    {
        b.ToTable("excusas");
        b.Property(x => x.Tipo).HasMaxLength(10).IsRequired();
        b.Property(x => x.Motivo).HasMaxLength(300).IsRequired();
        b.HasOne<Alumno>().WithMany().HasForeignKey(x => x.AlumnoId).OnDelete(DeleteBehavior.Cascade);
        b.HasIndex(x => new { x.AlumnoId, x.Hasta });
        b.HasIndex(x => new { x.InstitucionId, x.Hasta });
    }
}

public class IncidenciaConfig : IEntityTypeConfiguration<Incidencia>
{
    public void Configure(EntityTypeBuilder<Incidencia> b)
    {
        b.ToTable("incidencias");
        b.Property(x => x.Gravedad).HasMaxLength(10).IsRequired();
        b.Property(x => x.Descripcion).HasMaxLength(1000).IsRequired();
        b.Property(x => x.Medida).HasMaxLength(500);
        b.Property(x => x.Seguimiento).HasMaxLength(1000);
        b.HasOne<Alumno>().WithMany().HasForeignKey(x => x.AlumnoId).OnDelete(DeleteBehavior.Cascade);
        b.HasOne<Seccion>().WithMany().HasForeignKey(x => x.SeccionId).OnDelete(DeleteBehavior.SetNull);
        b.HasIndex(x => new { x.InstitucionId, x.Fecha });
        b.HasIndex(x => new { x.AlumnoId, x.Fecha });
        b.HasIndex(x => x.SeccionId);
        b.HasIndex(x => x.RegistradaPor);
    }
}

public class FotoAlumnoConfig : IEntityTypeConfiguration<FotoAlumno>
{
    public void Configure(EntityTypeBuilder<FotoAlumno> b)
    {
        b.ToTable("fotos_alumno");
        b.Property(x => x.Contenido).IsRequired();
        b.HasOne<Alumno>().WithMany().HasForeignKey(x => x.AlumnoId).OnDelete(DeleteBehavior.Cascade);
        b.HasIndex(x => x.AlumnoId).IsUnique();
    }
}

public class MarcaCentroConfig : IEntityTypeConfiguration<MarcaCentro>
{
    public void Configure(EntityTypeBuilder<MarcaCentro> b)
    {
        b.ToTable("marcas_centro");
        b.Property(x => x.TipoLogo).HasMaxLength(20);
        b.Property(x => x.Color).HasMaxLength(7).IsRequired();
        b.Property(x => x.Lema).HasMaxLength(120);
        b.HasOne<Institucion>().WithMany().HasForeignKey(x => x.InstitucionId).OnDelete(DeleteBehavior.Cascade);
        b.HasIndex(x => x.InstitucionId).IsUnique();
    }
}
