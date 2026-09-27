using ProfeApp.Domain.Common;

namespace ProfeApp.Domain.Instituciones;

/// <summary>
/// Centro educativo con licencia institucional. Sus docentes siguen teniendo cada uno su
/// propio espacio de datos (tenant); la institución sólo los agrupa para darlos de alta,
/// controlar el cupo de la licencia y ver el avance de los cierres.
/// </summary>
public class Institucion : BaseEntity
{
    public string Nombre { get; set; } = null!;

    /// <summary>pequeno, mediano, grande o red (ver la página de precios).</summary>
    public string Plan { get; set; } = null!;

    /// <summary>Cupo de docentes activos que cubre la licencia.</summary>
    public int MaxDocentes { get; set; }

    /// <summary>Fin de la licencia. Vencida, sus docentes no pueden entrar.</summary>
    public DateTimeOffset? VenceEn { get; set; }

    public bool Activa { get; set; } = true;

    public bool Vigente(DateTimeOffset ahora) => Activa && (VenceEn is null || VenceEn > ahora);
}
