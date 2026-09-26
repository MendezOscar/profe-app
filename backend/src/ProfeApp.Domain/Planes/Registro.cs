using ProfeApp.Domain.Common;

namespace ProfeApp.Domain.Planes;

/// <summary>
/// Respaldo de una fila del plan de calificación del teléfono: plantilla, rubro, actividad,
/// nota, lista de asistencia, marca de asistencia o estado del parcial. El servidor no
/// interpreta <see cref="Datos"/>: sólo guarda y reparte, y entre dispositivos gana el
/// cambio más nuevo por fila. Así el plan puede crecer en la app sin migrar la base.
/// </summary>
public class Registro : TenantEntity
{
    public const int MaxDatos = 4_000;

    public static readonly IReadOnlySet<string> Tipos = new HashSet<string>
    {
        "plantilla", "rubro", "actividad", "calificacion", "sesion", "asistencia", "parcial",
    };

    public string Tipo { get; set; } = null!;

    /// <summary>Clave de la clase a la que pertenece; vacía para lo que es del docente (plantillas).</summary>
    public string ClaseClave { get; set; } = null!;

    /// <summary>Id del teléfono para rubros, actividades y sesiones; compuesta para notas y asistencia.</summary>
    public string Clave { get; set; } = null!;

    /// <summary>JSON tal como lo manda la app.</summary>
    public string? Datos { get; set; }

    public bool Eliminado { get; set; }

    /// <summary>Hora del teléfono del cambio: gana la más nueva.</summary>
    public DateTimeOffset ActualizadoEn { get; set; }

    /// <summary>Hora del servidor del último cambio: es el cursor del pull.</summary>
    public DateTimeOffset ModificadoEn { get; set; }
}
