using ProfeApp.Domain.Common;

namespace ProfeApp.Domain.Centros;

/// <summary>
/// Organización académica de un centro con licencia: años lectivos, grados con sus
/// asignaturas, aulas, secciones y quién da cada asignatura en cada sección. Es del centro,
/// no de un docente: no lleva tenant, cada fila lleva la institución.
/// </summary>
public abstract class EntidadDeCentro : BaseEntity
{
    public Guid InstitucionId { get; set; }
}

/// <summary>Año lectivo (en Honduras, de febrero a noviembre) con el cierre de sus cuatro parciales.</summary>
public class AnioLectivo : EntidadDeCentro
{
    public int Anio { get; set; }
    public DateOnly Inicio { get; set; }
    public DateOnly Fin { get; set; }
    public DateOnly? CierreParcial1 { get; set; }
    public DateOnly? CierreParcial2 { get; set; }
    public DateOnly? CierreParcial3 { get; set; }
    public DateOnly? CierreParcial4 { get; set; }

    /// <summary>El año con el que trabaja el centro; sólo uno por centro.</summary>
    public bool Actual { get; set; }
}

/// <summary>Grado del centro: "7.º grado", "10.º BCH". <see cref="Nivel"/> según <see cref="NivelesEducativos"/>.</summary>
public class Grado : EntidadDeCentro
{
    public string Nivel { get; set; } = null!;
    public string Nombre { get; set; } = null!;
    public int Orden { get; set; }
}

/// <summary>Asignatura que lleva un grado (su malla curricular).</summary>
public class AsignaturaGrado : EntidadDeCentro
{
    public Guid GradoId { get; set; }
    public string Nombre { get; set; } = null!;
    public int Orden { get; set; }
}

public class Aula : EntidadDeCentro
{
    public string Nombre { get; set; } = null!;
    public int? Capacidad { get; set; }
}

/// <summary>Sección de un grado en un año lectivo y una jornada, con su aula y su maestro guía.</summary>
public class Seccion : EntidadDeCentro
{
    public Guid AnioLectivoId { get; set; }
    public Guid GradoId { get; set; }
    public string Nombre { get; set; } = null!;
    public string Jornada { get; set; } = null!;
    public int? Cupo { get; set; }
    public Guid? AulaId { get; set; }

    /// <summary>Usuario docente del centro.</summary>
    public Guid? MaestroGuiaId { get; set; }
}

/// <summary>Quién da una asignatura del grado en una sección. Una fila por asignatura y sección.</summary>
public class CargaDocente : EntidadDeCentro
{
    public Guid SeccionId { get; set; }
    public Guid AsignaturaGradoId { get; set; }
    public Guid DocenteId { get; set; }
}

public static class NivelesEducativos
{
    public const string Prebasica = "prebasica";
    public const string Basica = "basica";
    public const string Media = "media";
    public static readonly string[] Todos = [Prebasica, Basica, Media];
}

public static class Jornadas
{
    public static readonly string[] Todas = ["matutina", "vespertina", "nocturna", "doble", "sabatina"];
}

/// <summary>
/// Cargo del personal de un centro (cuentas con rol AdminCentro). La dirección, la
/// subdirección y la secretaría administran; orientación sólo consulta.
/// </summary>
public static class Cargos
{
    public const string Director = "director";
    public const string Subdirector = "subdirector";
    public const string Secretaria = "secretaria";
    public const string Orientador = "orientador";
    public static readonly string[] Todos = [Director, Subdirector, Secretaria, Orientador];

    /// <summary>Sin cargo es el administrador original del centro: tiene todo.</summary>
    public static bool Administra(string? cargo) => cargo is null or Director or Subdirector or Secretaria;
}
