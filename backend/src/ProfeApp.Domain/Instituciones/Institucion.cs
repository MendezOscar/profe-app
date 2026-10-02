using ProfeApp.Domain.Cobros;
using ProfeApp.Domain.Common;

namespace ProfeApp.Domain.Instituciones;

/// <summary>
/// Centro educativo con licencia institucional. Sus docentes siguen teniendo cada uno su
/// propio espacio de datos (tenant); la institución sólo los agrupa para darlos de alta,
/// controlar el cupo de la licencia, cobrar y ver el avance de los cierres.
/// </summary>
public class Institucion : BaseEntity, ICobrable
{
    public string Nombre { get; set; } = null!;

    /// <summary>pequeno, mediano, grande o red (ver la página de precios).</summary>
    public string Plan { get; set; } = null!;

    /// <summary>Cupo de docentes activos que cubre la licencia.</summary>
    public int MaxDocentes { get; set; }

    /// <summary>Suspendido, ni el centro ni sus docentes entran.</summary>
    public bool Activa { get; set; } = true;

    public string? PlanNombre { get; set; }
    public decimal Monto { get; set; }
    public DateOnly? PagadoHasta { get; set; }
    public int DiasGracia { get; set; }
    public string? ComoPagar { get; set; }
}
