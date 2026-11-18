namespace ProfeApp.Domain.Common;

/// <summary>Teléfono de un usuario que recibe avisos (token de Firebase Cloud Messaging).</summary>
public class DispositivoPush : BaseEntity
{
    public Guid UsuarioId { get; set; }
    public string Token { get; set; } = null!;

    /// <summary>android o ios.</summary>
    public string Plataforma { get; set; } = null!;

    public DateTimeOffset ActualizadoEn { get; set; }
}
