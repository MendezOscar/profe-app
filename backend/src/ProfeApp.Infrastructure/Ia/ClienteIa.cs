using System.Text.Json;
using Microsoft.Extensions.Logging;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Common;
using ProfeApp.Domain.Common;
using ProfeApp.Infrastructure.Persistence;

namespace ProfeApp.Infrastructure.Ia;

/// <summary>
/// Llama al modelo, anota el uso (tokens, sin el texto) y convierte la respuesta. Un error de
/// red o del modelo vuelve como mensaje para la persona, nunca como excepción.
/// </summary>
public sealed class ClienteIa(AppDbContext db, IGeneradorIa generador, ILogger<ClienteIa> log)
{
    public static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    public bool Disponible => generador.Disponible;

    public Task<string> CrearLoteAsync(IReadOnlyList<(string Id, PeticionIa Peticion)> peticiones, CancellationToken ct) =>
        generador.CrearLoteAsync(peticiones, ct);

    public async Task<Result<string>> TextoAsync(string funcion, PeticionIa peticion, Guid usuario, Guid? institucion, CancellationToken ct)
    {
        RespuestaIa respuesta;
        try
        {
            respuesta = await generador.GenerarAsync(peticion, ct);
        }
        catch (Exception e) when (e is not OperationCanceledException)
        {
            log.LogError(e, "Falló la llamada a la IA ({Funcion})", funcion);
            return Result<string>.Fail(Error.Validation("La IA no respondió. Intenta de nuevo en un momento."));
        }

        db.UsosIa.Add(Uso(funcion, respuesta, usuario, institucion));
        await db.SaveChangesAsync(ct);

        return respuesta.Rechazada || string.IsNullOrWhiteSpace(respuesta.Texto)
            ? Result<string>.Fail(Error.Validation("La IA no pudo con esta petición. Cambia el texto e intenta de nuevo."))
            : respuesta.Texto;
    }

    public async Task<Result<T>> JsonAsync<T>(string funcion, PeticionIa peticion, Guid usuario, Guid? institucion, CancellationToken ct)
    {
        var texto = await TextoAsync(funcion, peticion, usuario, institucion, ct);
        if (!texto.IsSuccess) return Result<T>.Fail(texto.Error!);
        try
        {
            return JsonSerializer.Deserialize<T>(texto.Value, Json)!;
        }
        catch (JsonException e)
        {
            log.LogWarning(e, "Respuesta de la IA que no se pudo leer ({Funcion})", funcion);
            return Result<T>.Fail(Error.Validation("La IA respondió algo que no se pudo leer. Intenta de nuevo."));
        }
    }

    public static UsoIa Uso(string funcion, RespuestaIa r, Guid usuario, Guid? institucion) => new()
    {
        UsuarioId = usuario,
        InstitucionId = institucion,
        Funcion = funcion,
        Modelo = r.Modelo,
        TokensEntrada = r.TokensEntrada,
        TokensSalida = r.TokensSalida,
    };

    /// <summary>Esquema JSON a partir de un objeto anónimo.</summary>
    public static Dictionary<string, JsonElement> Esquema(object schema) =>
        JsonSerializer.SerializeToElement(schema).EnumerateObject().ToDictionary(p => p.Name, p => p.Value.Clone());

    /// <summary>Recorta y limpia un texto de la persona; null si queda vacío.</summary>
    public static string? Texto(string? valor, int maximo)
    {
        var t = (valor ?? "").Trim();
        return t.Length == 0 ? null : t.Length > maximo ? t[..maximo] : t;
    }

    /// <summary>El mes empieza a la medianoche de Honduras; Postgres guarda en UTC.</summary>
    public static DateTimeOffset InicioDelMes(DateOnly hoy) =>
        new DateTimeOffset(hoy.Year, hoy.Month, 1, 0, 0, 0, TimeSpan.FromHours(-6)).ToUniversalTime();

    public const string Contexto =
        "Trabajas para ProfeApp, una app de centros educativos y docentes de Honduras. Escribe en español de Honduras, " +
        "claro y profesional. Sigue el Currículo Nacional Básico (CNB) de la Secretaría de Educación cuando aplique. " +
        "Una persona revisa todo lo que propones antes de usarlo.";
}
