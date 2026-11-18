namespace ProfeApp.Domain.Centros;

/// <summary>
/// Excusa o permiso que registra el centro para un alumno por uno o varios días. Quien pasa
/// lista ve al alumno como falta justificada.
/// </summary>
public class Excusa : EntidadDeCentro
{
    public Guid AlumnoId { get; set; }

    /// <summary>excusa (enfermedad, familia…) o permiso (el centro lo autoriza).</summary>
    public string Tipo { get; set; } = null!;

    public DateOnly Desde { get; set; }
    public DateOnly Hasta { get; set; }
    public string Motivo { get; set; } = null!;
    public Guid RegistradaPor { get; set; }
}

public static class TiposExcusa
{
    public const string Excusa = "excusa";
    public const string Permiso = "permiso";
    public static readonly string[] Todos = [Excusa, Permiso];
}

/// <summary>
/// Falta disciplinaria de un alumno (leve, grave o muy grave). La registra un catedrático de
/// la sección o el centro; la familia ve fecha, gravedad, descripción y medida, no el seguimiento.
/// </summary>
public class Incidencia : EntidadDeCentro
{
    public Guid AlumnoId { get; set; }

    /// <summary>Sección donde estaba matriculado al registrarla.</summary>
    public Guid? SeccionId { get; set; }

    public DateOnly Fecha { get; set; }

    /// <summary>leve, grave o muy_grave.</summary>
    public string Gravedad { get; set; } = null!;

    public string Descripcion { get; set; } = null!;

    /// <summary>Medida tomada (llamada de atención, citación a la familia…).</summary>
    public string? Medida { get; set; }

    /// <summary>Notas internas del centro: la familia no las ve.</summary>
    public string? Seguimiento { get; set; }

    public bool Cerrada { get; set; }
    public Guid RegistradaPor { get; set; }
}

public static class GravedadesIncidencia
{
    public static readonly string[] Todas = ["leve", "grave", "muy_grave"];

    public static string Nombre(string g) => g switch { "leve" => "leve", "grave" => "grave", _ => "muy grave" };
}
