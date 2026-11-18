namespace ProfeApp.Domain.Centros;

/// <summary>Foto del alumno para el carnet: JPEG pequeño (la app la reduce antes de subirla).</summary>
public class FotoAlumno : EntidadDeCentro
{
    public Guid AlumnoId { get; set; }
    public byte[] Contenido { get; set; } = null!;
}

/// <summary>Logo, color y lema del centro para el carnet. Uno por centro.</summary>
public class MarcaCentro : EntidadDeCentro
{
    public byte[]? Logo { get; set; }

    /// <summary>image/png o image/jpeg.</summary>
    public string? TipoLogo { get; set; }

    /// <summary>Color principal en "#RRGGBB".</summary>
    public string Color { get; set; } = MarcasCentro.ColorPorDefecto;

    public string? Lema { get; set; }
}

public static class MarcasCentro
{
    public const string ColorPorDefecto = "#1F4E79";
}
