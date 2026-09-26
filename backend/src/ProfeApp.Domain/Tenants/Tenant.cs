using ProfeApp.Domain.Common;

namespace ProfeApp.Domain.Tenants;

/// <summary>
/// Espacio de datos aislado. En la venta directa cada docente tiene el suyo; con la
/// licencia por colegio, el tenant será el centro y agrupará a sus docentes.
/// </summary>
public class Tenant : BaseEntity
{
    public string Name { get; set; } = null!;
    public bool IsActive { get; set; } = true;
}
