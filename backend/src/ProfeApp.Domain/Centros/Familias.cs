using ProfeApp.Domain.Common;

namespace ProfeApp.Domain.Centros;

/// <summary>
/// Código que secretaría entrega a la familia de un alumno para que el padre o la madre
/// cree su cuenta y quede vinculado. Uno vigente por alumno: generar otro anula el anterior.
/// </summary>
public class CodigoFamilia : EntidadDeCentro
{
    public Guid AlumnoId { get; set; }
    public string Codigo { get; set; } = null!;
    public DateTimeOffset ExpiraEn { get; set; }
}

/// <summary>Cuenta de padre o madre vinculada a un alumno. El centro la puede quitar.</summary>
public class VinculoFamiliar : EntidadDeCentro
{
    public Guid AlumnoId { get; set; }
    public Guid UsuarioId { get; set; }
}

/// <summary>Aviso del centro a las familias: a todas, o a las de ciertas secciones.</summary>
public class Comunicado : EntidadDeCentro
{
    public string Titulo { get; set; } = null!;
    public string Cuerpo { get; set; } = null!;

    /// <summary>Vacía = todo el centro.</summary>
    public List<Guid> SeccionIds { get; set; } = [];

    public Guid? AutorId { get; set; }
    public DateTimeOffset PublicadoEn { get; set; }
}

/// <summary>Quién leyó un comunicado y cuándo.</summary>
public class LecturaComunicado : BaseEntity
{
    public Guid ComunicadoId { get; set; }
    public Guid UsuarioId { get; set; }
    public DateTimeOffset LeidoEn { get; set; }
}
