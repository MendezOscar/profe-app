namespace ProfeApp.Application.Abstractions;

/// <summary>
/// El documento fiscal de la mensualidad, que no lo emite ProfeApp: lo emite la facturación
/// central, porque el CAI del SAR es uno solo para todos los servicios de la empresa
/// —ProfeApp, GarajApp, StockRuta—.
/// </summary>
/// <remarks>
/// Aquí sólo se pide el número. El cobro, el vencimiento y el historial siguen siendo de
/// ProfeApp: lo único que viaja afuera es a nombre de quién va el documento y qué dice.
/// </remarks>
public interface IFacturacionCentral
{
    /// <summary>Si hay dirección y llave configuradas. Sin eso no se llama a nadie.</summary>
    bool Configurada { get; }

    /// <summary>
    /// Pide el documento de un pago ya registrado.
    /// </summary>
    /// <param name="pagoId">
    /// El pago de ProfeApp. Viaja como clave de idempotencia, así que pedir dos veces por el
    /// mismo pago devuelve el mismo documento en vez de quemar otro número del SAR.
    /// </param>
    Task<ResultadoFactura> EmitirAsync(Guid pagoId, PeticionFactura peticion, CancellationToken ct = default);
}

/// <param name="Cliente">A nombre de quién va. Se copia en el documento.</param>
/// <param name="Rtn">Sin RTN el documento sale a consumidor final.</param>
/// <param name="ReferenciaDelCliente">
/// El id de la cuenta en ProfeApp —el espacio del docente o el centro—. Allá no es una
/// relación: es la etiqueta que les permite juntar los documentos de un mismo cliente sin
/// tener nuestro padrón.
/// </param>
/// <param name="ConCai">
/// Si va con CAI, es decir si es factura. Se decide <b>pago por pago</b>: el catedrático que
/// no la pide recibe un comprobante, y un número autorizado del SAR que se quema no se
/// devuelve. Null toma lo que diga la configuración del servidor.
/// </param>
public sealed record PeticionFactura(
    string Cliente,
    string? RazonSocial,
    string? Rtn,
    string Concepto,
    decimal Monto,
    string ReferenciaDelCliente,
    DateOnly? PagadoEl = null,
    string? Referencia = null,
    bool? ConCai = null);

/// <summary>
/// Cómo salió el pedido. No es un <c>Result</c> del sistema a propósito: que la facturación
/// falle <b>no puede tumbar el cobro</b> —la plata ya entró—, pero tampoco se puede tragar el
/// error. Por eso vuelve siempre, con el documento o con el motivo, y el motivo queda guardado
/// en el pago y a la vista en Plataforma.
/// </summary>
/// <param name="SePuedeReintentar">
/// Si vale la pena volver a intentar: se cayó la red o el otro servidor. Un rechazo por datos
/// —el rango se agotó, la llave no vale— no se arregla reintentando.
/// </param>
public sealed record ResultadoFactura(
    bool Emitida,
    string? Numero = null,
    string? Cai = null,
    Guid? DocumentoId = null,
    string? Error = null,
    bool SePuedeReintentar = false)
{
    public static ResultadoFactura Ok(string numero, string? cai, Guid documentoId) =>
        new(true, numero, cai, documentoId);

    public static ResultadoFactura Falla(string error, bool sePuedeReintentar) =>
        new(false, Error: error, SePuedeReintentar: sePuedeReintentar);
}
