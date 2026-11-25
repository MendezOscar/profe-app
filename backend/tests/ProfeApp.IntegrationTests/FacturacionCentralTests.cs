using System.Net;
using System.Net.Http.Json;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using ProfeApp.Application.Abstractions;
using ProfeApp.Infrastructure.Facturacion;

namespace ProfeApp.IntegrationTests;

/// <summary>
/// El cliente que le pide a la facturación central el número del documento de una mensualidad.
/// </summary>
/// <remarks>
/// Lo que se prueba es cómo se porta cuando el otro lado falla, que es lo único que puede
/// costar caro:
///
/// - **No lanza nunca.** Si la facturación está caída, el cobro ya quedó registrado y no se
///   puede tumbar por eso.
/// - **No se traga el error.** Vuelve descrito, para que quede guardado en el pago y a la
///   vista en Plataforma.
/// - **La llave va en la cabecera** y **la clave de idempotencia es el id del pago**, que es
///   lo que hace que reintentar no queme otro número del SAR.
/// </remarks>
public class FacturacionCentralTests
{
    private static readonly Guid Pago = Guid.Parse("8f14e45f-ea1b-4b2e-9f3c-0a1b2c3d4e5f");

    /// <summary>Un servidor de mentira que contesta lo que le digan y guarda lo que le pidieron.</summary>
    private sealed class Falso(Func<HttpRequestMessage, HttpResponseMessage> responder)
        : HttpMessageHandler
    {
        public HttpRequestMessage? Ultima { get; private set; }

        /// <summary>Se lee acá: el cliente desecha la petición al salir, y con ella el cuerpo.</summary>
        public string? Cuerpo { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Ultima = request;
            Cuerpo = request.Content?.ReadAsStringAsync(cancellationToken).GetAwaiter().GetResult();
            return Task.FromResult(responder(request));
        }
    }

    private sealed class UnaFabrica(HttpMessageHandler handler) : IHttpClientFactory
    {
        public HttpClient CreateClient(string name) => new(handler, disposeHandler: false);
    }

    private static (FacturacionCentralCliente Cliente, Falso Servidor) Armar(
        Func<HttpRequestMessage, HttpResponseMessage> responder)
    {
        var servidor = new Falso(responder);

        var opciones = Options.Create(new FacturacionCentralOptions
        {
            BaseUrl = "https://facturacion.example.com",
            ApiKey = "gbk_llave_de_prueba",
        });

        return (
            new FacturacionCentralCliente(
                new UnaFabrica(servidor), opciones, NullLogger<FacturacionCentralCliente>.Instance),
            servidor);
    }

    private static HttpResponseMessage Emitida() =>
        new(HttpStatusCode.OK)
        {
            Content = JsonContent.Create(new
            {
                id = Guid.Parse("11111111-2222-3333-4444-555555555555"),
                number = "000-001-01-00000042",
                cai = "ABC123",
                alreadyIssued = false,
            })
        };

    private static PeticionFactura Peticion() =>
        new("Instituto San José", null, "08011999123456", "ProfeApp — licencia (1 mes)", 1500m,
            "11111111-1111-1111-1111-111111111111", new DateOnly(2026, 11, 25), "DEP-77123");

    [Fact]
    public async Task Manda_la_llave_en_la_cabecera_y_el_pago_como_clave()
    {
        var (cliente, servidor) = Armar(_ => Emitida());

        await cliente.EmitirAsync(Pago, Peticion());

        servidor.Ultima.Should().NotBeNull();

        // En la cabecera, no en la dirección: la dirección queda escrita en los registros.
        servidor.Ultima!.Headers.GetValues("X-Billing-Key").Should().ContainSingle()
            .Which.Should().Be("gbk_llave_de_prueba");
        servidor.Ultima.RequestUri!.ToString().Should().NotContain("gbk_");

        // El id del pago: pedir dos veces por el mismo cobro devuelve el mismo documento.
        servidor.Ultima.Headers.GetValues("Idempotency-Key").Should().ContainSingle()
            .Which.Should().Be(Pago.ToString());
    }

    [Fact]
    public async Task Con_el_documento_emitido_devuelve_su_numero()
    {
        var (cliente, _) = Armar(_ => Emitida());

        var resultado = await cliente.EmitirAsync(Pago, Peticion());

        resultado.Emitida.Should().BeTrue();
        resultado.Numero.Should().Be("000-001-01-00000042");
        resultado.Cai.Should().Be("ABC123");
        resultado.DocumentoId.Should().Be(Guid.Parse("11111111-2222-3333-4444-555555555555"));
        resultado.Error.Should().BeNull();
    }

    [Fact]
    public async Task Si_el_otro_servidor_se_cae_no_lanza_y_dice_que_se_puede_reintentar()
    {
        var (cliente, _) = Armar(_ => new HttpResponseMessage(HttpStatusCode.BadGateway));

        var resultado = await cliente.EmitirAsync(Pago, Peticion());

        resultado.Emitida.Should().BeFalse();
        resultado.SePuedeReintentar.Should().BeTrue();
        resultado.Error.Should().NotBeNullOrWhiteSpace();
    }

    [Fact]
    public async Task Si_no_hay_red_tampoco_lanza()
    {
        var (cliente, _) = Armar(_ => throw new HttpRequestException("sin red"));

        var resultado = await cliente.EmitirAsync(Pago, Peticion());

        resultado.Emitida.Should().BeFalse();
        resultado.SePuedeReintentar.Should().BeTrue();
    }

    [Fact]
    public async Task Un_rechazo_por_los_datos_no_se_reintenta()
    {
        // El rango se agotó, falta el RTN: volver a mandar lo mismo da lo mismo.
        var (cliente, _) = Armar(_ => new HttpResponseMessage(HttpStatusCode.BadRequest)
        {
            Content = JsonContent.Create(new { detail = "Se agotó el rango autorizado." })
        });

        var resultado = await cliente.EmitirAsync(Pago, Peticion());

        resultado.Emitida.Should().BeFalse();
        resultado.SePuedeReintentar.Should().BeFalse();
        resultado.Error.Should().Be("Se agotó el rango autorizado.");
    }

    [Fact]
    public async Task Con_la_llave_rotada_lo_dice_con_todas_sus_letras()
    {
        var (cliente, _) = Armar(_ => new HttpResponseMessage(HttpStatusCode.Unauthorized));

        var resultado = await cliente.EmitirAsync(Pago, Peticion());

        resultado.Emitida.Should().BeFalse();
        resultado.SePuedeReintentar.Should().BeFalse();
        resultado.Error.Should().Contain("llave");
    }

    [Fact]
    public async Task La_factura_con_CAI_se_decide_pago_por_pago()
    {
        // La variable del servidor es sólo el valor por defecto: la factura se emite **sólo si
        // el catedrático la pide**, y un número autorizado del SAR que se quema no se devuelve.
        var (cliente, servidor) = Armar(_ => Emitida());

        await cliente.EmitirAsync(Pago, Peticion() with { ConCai = false });
        servidor.Cuerpo.Should().Contain("\"fiscal\":false");

        await cliente.EmitirAsync(Pago, Peticion() with { ConCai = true });
        servidor.Cuerpo.Should().Contain("\"fiscal\":true");
    }

    [Fact]
    public async Task Sin_decir_nada_toma_lo_del_servidor()
    {
        var (cliente, servidor) = Armar(_ => Emitida());

        await cliente.EmitirAsync(Pago, Peticion());

        // Options.Fiscal viene en true por defecto.
        servidor.Cuerpo.Should().Contain("\"fiscal\":true");
    }

    [Fact]
    public async Task Sin_configurar_no_llama_a_nadie()
    {
        var servidor = new Falso(_ => Emitida());

        var cliente = new FacturacionCentralCliente(
            new UnaFabrica(servidor),
            Options.Create(new FacturacionCentralOptions()),
            NullLogger<FacturacionCentralCliente>.Instance);

        var resultado = await cliente.EmitirAsync(Pago, Peticion());

        cliente.Configurada.Should().BeFalse();
        resultado.Emitida.Should().BeFalse();
        servidor.Ultima.Should().BeNull();
    }
}
