namespace ProfeApp.Domain.Centros;

/// <summary>
/// Alumno del centro, identificado por su número de identidad (o el documento con que
/// SACE lo registra). Su ficha la lleva secretaría; los datos de salud son sensibles.
/// </summary>
public class Alumno : EntidadDeCentro
{
    public string Identidad { get; set; } = null!;
    public string Nombre { get; set; } = null!;
    public DateOnly? FechaNacimiento { get; set; }

    /// <summary>"F" o "M".</summary>
    public string? Sexo { get; set; }

    public string? Direccion { get; set; }

    /// <summary>Alergias, condiciones o medicamentos que el centro debe conocer.</summary>
    public string? Salud { get; set; }

    /// <summary>Becas, necesidades especiales u otra nota de secretaría.</summary>
    public string? Notas { get; set; }
}

/// <summary>Padre, madre o encargado del alumno. El principal es a quien se llama primero.</summary>
public class Encargado : EntidadDeCentro
{
    public Guid AlumnoId { get; set; }
    public string Nombre { get; set; } = null!;
    public string? Parentesco { get; set; }
    public string? Telefono { get; set; }
    public string? Correo { get; set; }
    public bool Principal { get; set; }
}

/// <summary>
/// El alumno en una sección durante un año lectivo. Una por alumno y año: cambiarlo de
/// sección es cambiar la sección de su matrícula; un retiro la deja con fecha y motivo.
/// </summary>
public class Matricula : EntidadDeCentro
{
    public Guid AlumnoId { get; set; }
    public Guid AnioLectivoId { get; set; }
    public Guid SeccionId { get; set; }
    public string Tipo { get; set; } = TiposMatricula.NuevoIngreso;
    public string Estado { get; set; } = EstadosMatricula.Activa;
    public DateOnly FechaIngreso { get; set; }
    public DateOnly? FechaBaja { get; set; }
    public string? MotivoBaja { get; set; }
}

public static class TiposMatricula
{
    public const string NuevoIngreso = "nuevo_ingreso";
    public const string Reingreso = "reingreso";
    public const string TrasladoEntrante = "traslado_entrante";
    public static readonly string[] Todos = [NuevoIngreso, Reingreso, TrasladoEntrante];
}

public static class EstadosMatricula
{
    public const string Activa = "activa";
    public const string Retirada = "retirada";
    public const string Trasladada = "trasladada";
    public static readonly string[] Bajas = [Retirada, Trasladada];
}
