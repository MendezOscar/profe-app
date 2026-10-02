using ProfeApp.Domain.Common;

namespace ProfeApp.Domain.Cobros;

/// <summary>
/// Quien le paga a ProfeApp: el docente del plan personal (en su espacio) o el centro con
/// licencia. Los dos se cobran igual: un monto por período, pagado hasta una fecha y unos
/// días de gracia antes de quedar de sólo lectura.
/// </summary>
public interface ICobrable
{
    string? PlanNombre { get; set; }
    decimal Monto { get; set; }

    /// <summary>Último día pagado, en hora de Honduras. Sin fecha no se cobra.</summary>
    DateOnly? PagadoHasta { get; set; }

    int DiasGracia { get; set; }

    /// <summary>Banco, cuenta, a quién avisar del depósito.</summary>
    string? ComoPagar { get; set; }
}

public enum EstadoCobro
{
    /// <summary>Al día, o sin fecha de vencimiento.</summary>
    AlDia = 0,

    /// <summary>Faltan pocos días: se avisa, pero trabaja igual.</summary>
    PorVencer = 1,

    /// <summary>Venció y corre la gracia: trabaja igual, con el aviso encima.</summary>
    Gracia = 2,

    /// <summary>Pasó la gracia: entra, consulta y exporta, pero no respalda nada nuevo.</summary>
    SoloLectura = 3,
}

/// <summary>
/// El cobro contra el día de hoy. Vive en el dominio porque lo usan tres lugares: el aviso
/// que ve el docente, el candado de la sincronización y la lista de la plataforma.
/// </summary>
public sealed record SituacionCobro(
    EstadoCobro Estado,
    string? PlanNombre,
    decimal Monto,
    DateOnly? PagadoHasta,
    int DiasGracia,
    DateOnly? BloqueaEn,
    int? DiasRestantes,
    string? ComoPagar)
{
    /// <summary>Con cuánta anticipación se empieza a recordar el pago.</summary>
    public const int DiasDeAviso = 7;

    public static readonly SituacionCobro SinCobro = new(EstadoCobro.AlDia, null, 0, null, 0, null, null, null);

    public bool SoloLectura => Estado == EstadoCobro.SoloLectura;

    public static SituacionCobro Para(ICobrable? cuenta, DateOnly hoy) => cuenta is null
        ? SinCobro
        : Para(cuenta.PlanNombre, cuenta.Monto, cuenta.PagadoHasta, cuenta.DiasGracia, cuenta.ComoPagar, hoy);

    public static SituacionCobro Para(
        string? planNombre, decimal monto, DateOnly? pagadoHasta, int diasGracia, string? comoPagar, DateOnly hoy)
    {
        var gracia = Math.Max(0, diasGracia);

        // Sin fecha no se cobra: la demo, las cuentas de revisión y las de cortesía no se
        // bloquean solas por un campo que nadie llenó.
        if (pagadoHasta is not { } hasta)
            return new(EstadoCobro.AlDia, planNombre, monto, null, gracia, null, null, comoPagar);

        var bloquea = hasta.AddDays(gracia);
        var quedan = hasta.DayNumber - hoy.DayNumber;

        // El día del vencimiento todavía está pagado, y el último día de gracia también.
        var estado = quedan >= 0
            ? quedan <= DiasDeAviso ? EstadoCobro.PorVencer : EstadoCobro.AlDia
            : hoy <= bloquea ? EstadoCobro.Gracia : EstadoCobro.SoloLectura;

        return new(estado, planNombre, monto, hasta, gracia, bloquea, quedan, comoPagar);
    }
}

/// <summary>
/// Los planes del docente personal se separan por cuántas secciones maneja: cada cuadro
/// de SACE (una asignatura en una sección) cuenta una. Sin nivel
/// no hay tope (cuentas de cortesía); los docentes de un centro tampoco lo tienen.
/// </summary>
public static class NivelesDocente
{
    public const string Basico = "basico";
    public const string Docente = "docente";
    public const string Plus = "plus";

    public static readonly string[] Todos = [Basico, Docente, Plus];

    public static int? Tope(string? nivel) => nivel switch
    {
        Basico => 3,
        Docente => 8,
        _ => null,
    };
}

/// <summary>
/// Un pago a ProfeApp. Sin filtro de tenant a propósito: es plata de la plataforma, no del
/// docente, y sólo la ve quien opera ProfeApp. <c>CuentaId</c> es el espacio del docente o
/// el centro. Queda hasta dónde dejó pagado cada depósito, que es lo que se discute.
/// </summary>
public class Pago : BaseEntity
{
    public Guid CuentaId { get; set; }

    /// <summary>El día en que entró la plata, que no siempre es el día que se anota.</summary>
    public DateOnly PagadoEl { get; set; }

    public decimal Monto { get; set; }

    /// <summary>Meses que cubrió.</summary>
    public int Periodos { get; set; }

    /// <summary>Hasta dónde quedó pagada la cuenta con este depósito.</summary>
    public DateOnly CubreHasta { get; set; }

    /// <summary>Número de transferencia, banco, quién depositó.</summary>
    public string? Referencia { get; set; }
}
