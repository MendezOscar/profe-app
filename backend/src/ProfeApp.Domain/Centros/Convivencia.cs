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
