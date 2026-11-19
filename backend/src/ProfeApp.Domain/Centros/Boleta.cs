namespace ProfeApp.Domain.Centros;

/// <summary>
/// Comentario del desempeño de un alumno en la boleta de un parcial. Lo redacta el asistente
/// con IA o el centro; si una persona lo edita, la IA ya no lo reescribe.
/// </summary>
public class ComentarioBoleta : EntidadDeCentro
{
    public Guid SeccionId { get; set; }
    public Guid AlumnoId { get; set; }

    /// <summary>1 a 4.</summary>
    public int Parcial { get; set; }

    public string Texto { get; set; } = null!;

    /// <summary>Verdadero mientras sea el texto de la IA sin cambios.</summary>
    public bool DeIa { get; set; }
}
