namespace ProfeApp.Application.Abstractions;

/// <summary>Aviso al teléfono de unos usuarios. <c>Ruta</c>: pantalla de la app que abre al tocarlo.</summary>
public sealed record AvisoPush(IReadOnlyCollection<Guid> Usuarios, string Titulo, string Cuerpo, string? Ruta = null);

/// <summary>
/// Cola de avisos: encolar no espera a Firebase ni falla la petición si el envío falla.
/// Sin credenciales de Firebase, los avisos se descartan.
/// </summary>
public interface IAvisosPush
{
    void Encolar(AvisoPush aviso);
}

/// <summary>Quien manda de verdad a los teléfonos. Devuelve los tokens que ya no sirven.</summary>
public interface IEnviadorPush
{
    Task<IReadOnlyList<string>> EnviarAsync(IReadOnlyList<string> tokens, string titulo, string cuerpo, string? ruta, CancellationToken ct);
}

public sealed record DispositivoRequest(string Token, string Plataforma);

/// <summary>Registra el teléfono del usuario que llama para recibir avisos.</summary>
public interface IDispositivosService
{
    Task<Common.Result> RegistrarAsync(DispositivoRequest request, CancellationToken ct = default);
}
