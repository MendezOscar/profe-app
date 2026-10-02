using ProfeApp.Domain.Cobros;
using ProfeApp.Domain.Common;

namespace ProfeApp.Domain.Tenants;

/// <summary>
/// Espacio de datos aislado. En la venta directa cada docente tiene el suyo, y en él va su
/// cobro; con la licencia de un centro, el cobro es del centro.
/// </summary>
public class Tenant : BaseEntity, ICobrable
{
    public string Name { get; set; } = null!;
    public bool IsActive { get; set; } = true;

    /// <summary>basico, docente o plus (ver <see cref="NivelesDocente"/>). Null = sin tope.</summary>
    public string? Nivel { get; set; }

    public string? PlanNombre { get; set; }
    public decimal Monto { get; set; }
    public DateOnly? PagadoHasta { get; set; }
    public int DiasGracia { get; set; }
    public string? ComoPagar { get; set; }
}
