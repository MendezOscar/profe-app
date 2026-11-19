using Anthropic;
using Anthropic.Models.Beta;
using Anthropic.Models.Beta.Messages;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using ProfeApp.Application.Abstractions;

namespace ProfeApp.Infrastructure.Ia;

/// <summary>
/// Llama a Claude (Anthropic) desde el servidor. La clave va en <c>Anthropic:ApiKey</c>
/// (variable de Render <c>Anthropic__ApiKey</c>); sin ella el asistente queda apagado y la
/// API arranca igual. Si el modelo declina por sus filtros, el servidor de Anthropic reintenta
/// con otro modelo (fallbacks "default").
/// </summary>
public sealed class GeneradorClaude : IGeneradorIa
{
    public const string Modelo = "claude-opus-5-5";

    private readonly AnthropicClient? _cliente;
    private readonly ILogger<GeneradorClaude> _log;

    public GeneradorClaude(IConfiguration configuration, ILogger<GeneradorClaude> log)
    {
        _log = log;
        var clave = configuration["Anthropic:ApiKey"];
        if (string.IsNullOrWhiteSpace(clave))
        {
            log.LogInformation("Sin Anthropic:ApiKey: el asistente con IA queda apagado.");
            return;
        }
        _cliente = new AnthropicClient { ApiKey = clave };
    }

    public bool Disponible => _cliente is not null;

    /// <summary>Turnos anteriores como texto, y al final la petición con sus fotos antes del texto.</summary>
    private static List<BetaMessageParam> Mensajes(PeticionIa p)
    {
        var mensajes = new List<BetaMessageParam>();
        foreach (var (pregunta, respuesta) in p.Historial ?? [])
        {
            mensajes.Add(new BetaUserMessageParam { Content = pregunta });
            mensajes.Add(new BetaAssistantMessageParam { Content = respuesta });
        }
        if (p.Imagenes is not { Count: > 0 } fotos)
        {
            mensajes.Add(new BetaUserMessageParam { Content = p.Usuario });
            return mensajes;
        }
        var bloques = new List<BetaContentBlockParam>();
        foreach (var foto in fotos)
            bloques.Add(new BetaImageBlockParam
            {
                Source = new BetaBase64ImageSource { Data = Convert.ToBase64String(foto), MediaType = MediaType.ImageJpeg },
            });
        bloques.Add(new BetaTextBlockParam { Text = p.Usuario });
        mensajes.Add(new BetaUserMessageParam { Content = bloques });
        return mensajes;
    }

    public async Task<RespuestaIa> GenerarAsync(PeticionIa p, CancellationToken ct)
    {
        if (_cliente is null) throw new InvalidOperationException("El asistente con IA no está configurado.");
        var parametros = new MessageCreateParams
        {
            Model = Modelo,
            MaxTokens = p.MaxTokens,
            Betas = [AnthropicBeta.ServerSideFallback2026_07_01],
            Fallbacks = new Default(),
            // El sistema es fijo por función: se guarda en caché entre llamadas.
            System = new List<BetaTextBlockParam> { new() { Text = p.Sistema, CacheControl = new BetaCacheControlEphemeral() } },
            OutputConfig = new BetaOutputConfig
            {
                Effort = p.Breve ? Effort.Low : Effort.Medium,
                Format = p.Esquema is null ? null : new BetaJsonOutputFormat { Schema = new Dictionary<string, System.Text.Json.JsonElement>(p.Esquema) },
            },
            Messages = Mensajes(p),
        };
        var respuesta = await _cliente.Beta.Messages.Create(parametros, ct);
        var texto = string.Concat(respuesta.Content.Select(b => b.Value).OfType<BetaTextBlock>().Select(t => t.Text));
        var rechazada = respuesta.StopReason == "refusal";
        if (rechazada) _log.LogWarning("La IA declinó una petición: {Detalle}", respuesta.StopDetails?.Category);
        // La entrada incluye lo que pasó por la caché, para que el reporte de costo no se quede corto.
        var u = respuesta.Usage;
        var entrada = u.InputTokens + (u.CacheCreationInputTokens ?? 0) + (u.CacheReadInputTokens ?? 0);
        return new RespuestaIa(texto, respuesta.Model, (int)entrada, (int)respuesta.Usage.OutputTokens, rechazada);
    }
}
