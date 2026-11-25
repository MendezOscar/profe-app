using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ProfeApp.Application.Abstractions;

namespace ProfeApp.Infrastructure.Facturacion;

public sealed class FacturacionCentralOptions
{
    public const string Section = "FacturacionCentral";

    /// <summary>La dirección de la facturación central, sin barra al final.</summary>
    public string? BaseUrl { get; set; }

    /// <summary>
    /// La llave de ProfeApp. <b>Sólo por variable de entorno</b>: identifica al sistema entero
    /// ante la facturación, así que en el repositorio no va nunca, igual que la de la IA.
    /// </summary>
    public string? ApiKey { get; set; }

    /// <summary>
    /// Con CAI. En falso sale un comprobante con el correlativo propio de la facturación, que
    /// es lo que se le da a quien no pide factura.
    /// </summary>
    public bool Fiscal { get; set; } = true;

    /// <summary>
    /// Lo que se espera antes de rendirse. Corto: hay alguien mirando la pantalla después de
    /// anotar un pago, y si la facturación no contesta el pago igual queda guardado.
    /// </summary>
    public int TimeoutSeconds { get; set; } = 12;

    public bool Configurada =>
        !string.IsNullOrWhiteSpace(BaseUrl) && !string.IsNullOrWhiteSpace(ApiKey);
}

/// <summary>
/// Le pide a la facturación central el número del documento de una mensualidad.
/// </summary>
/// <remarks>
/// Tres cosas que no son detalles:
///
/// - **La llave va en la cabecera**, nunca en la dirección: la dirección queda escrita en los
///   registros del servidor y en los de cualquier proxy del camino.
/// - **La clave de idempotencia es el id del pago.** Pedir dos veces por el mismo pago
///   devuelve el documento que ya salió. Es lo que hace que reintentar sea gratis y que un
///   doble toque no queme dos números del SAR.
/// - **Nunca lanza.** Que la facturación esté caída no puede tumbar el registro de un cobro
///   que ya entró; pero el error no se traga: vuelve descrito y se guarda en el pago.
/// </remarks>
public sealed class FacturacionCentralCliente(
    IHttpClientFactory fabrica,
    IOptions<FacturacionCentralOptions> options,
    ILogger<FacturacionCentralCliente> log)
    : IFacturacionCentral
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    private readonly FacturacionCentralOptions _options = options.Value;

    public bool Configurada => _options.Configurada;

    public async Task<ResultadoFactura> EmitirAsync(
        Guid pagoId, PeticionFactura peticion, CancellationToken ct = default)
    {
        if (!Configurada)
            return ResultadoFactura.Falla(
                "La facturación central no está configurada en este servidor.", sePuedeReintentar: false);

        var cuerpo = new Cuerpo(
            new Cliente(peticion.Cliente, peticion.RazonSocial, peticion.Rtn),
            [new Linea(peticion.Concepto, 1, peticion.Monto)],
            peticion.ReferenciaDelCliente,
            _options.Fiscal,
            peticion.PagadoEl?.ToString("yyyy-MM-dd"),
            peticion.Referencia);

        try
        {
            var http = fabrica.CreateClient(nameof(FacturacionCentralCliente));
            http.Timeout = TimeSpan.FromSeconds(Math.Clamp(_options.TimeoutSeconds, 3, 60));

            using var mensaje = new HttpRequestMessage(
                HttpMethod.Post, $"{_options.BaseUrl!.TrimEnd('/')}/api/billing/invoices")
            {
                Content = JsonContent.Create(cuerpo, options: Json)
            };

            mensaje.Headers.Add("X-Billing-Key", _options.ApiKey);
            mensaje.Headers.Add("Idempotency-Key", pagoId.ToString());

            using var respuesta = await http.SendAsync(mensaje, ct);

            if (!respuesta.IsSuccessStatusCode)
            {
                var detalle = await Detalle(respuesta, ct);

                // 5xx y 408 son del otro lado: reintentar sirve. Un 4xx es un rechazo por lo
                // que se mandó, y volver a mandarlo igual da lo mismo.
                var reintentable = (int)respuesta.StatusCode >= 500
                    || respuesta.StatusCode == HttpStatusCode.RequestTimeout;

                log.LogWarning(
                    "La facturación central rechazó el pago {Pago}: {Estado} {Detalle}",
                    pagoId, (int)respuesta.StatusCode, detalle);

                return ResultadoFactura.Falla(detalle, reintentable);
            }

            var emitida = await respuesta.Content.ReadFromJsonAsync<Emitida>(Json, ct);

            if (emitida is null || string.IsNullOrWhiteSpace(emitida.Number))
                return ResultadoFactura.Falla(
                    "La facturación contestó sin número de documento.", sePuedeReintentar: true);

            return ResultadoFactura.Ok(emitida.Number, emitida.Cai, emitida.Id);
        }
        catch (TaskCanceledException) when (!ct.IsCancellationRequested)
        {
            return ResultadoFactura.Falla(
                "La facturación central no contestó a tiempo.", sePuedeReintentar: true);
        }
        catch (HttpRequestException e)
        {
            log.LogWarning(e, "No se pudo hablar con la facturación central");

            return ResultadoFactura.Falla(
                "No se pudo conectar con la facturación central.", sePuedeReintentar: true);
        }
    }

    /// <summary>
    /// El motivo que contestó la facturación, para poder enseñarlo tal cual. Se recorta: es
    /// para una fila de la pantalla, no para un registro.
    /// </summary>
    private static async Task<string> Detalle(HttpResponseMessage respuesta, CancellationToken ct)
    {
        try
        {
            var problema = await respuesta.Content.ReadFromJsonAsync<Problema>(Json, ct);

            if (problema?.Detail is { Length: > 0 } detalle) return Recortar(detalle);
            if (problema?.Title is { Length: > 0 } titulo) return Recortar(titulo);
        }
        catch (Exception)
        {
            // El cuerpo no era el problema que se esperaba. Con el código basta.
        }

        return respuesta.StatusCode switch
        {
            HttpStatusCode.Unauthorized => "La llave de ProfeApp no vale o fue rotada.",
            HttpStatusCode.TooManyRequests => "La facturación pidió esperar: demasiadas peticiones.",
            _ => $"La facturación contestó {(int)respuesta.StatusCode}."
        };
    }

    private static string Recortar(string texto) => texto.Length <= 300 ? texto : texto[..300];

    // La forma del cuerpo la fija la facturación central; va en inglés porque es su contrato.
    private sealed record Cuerpo(
        Cliente Customer,
        IReadOnlyList<Linea> Lines,
        string ExternalCustomerRef,
        bool Fiscal,
        string? PaidOn,
        string? PaymentReference);

    private sealed record Cliente(string Name, string? LegalName, string? TaxId);

    private sealed record Linea(string Description, decimal Quantity, decimal UnitPrice);

    private sealed record Emitida(
        Guid Id,
        string Number,
        string? Cai,
        [property: JsonPropertyName("alreadyIssued")] bool AlreadyIssued);

    private sealed record Problema(string? Title, string? Detail);
}
