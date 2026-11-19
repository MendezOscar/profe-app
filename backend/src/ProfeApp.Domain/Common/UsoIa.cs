namespace ProfeApp.Domain.Common;

/// <summary>
/// Una llamada al asistente con IA: quién, para qué y cuántos tokens. Sirve para el tope
/// mensual de cada docente y para saber cuánto cuesta cada centro. No guarda el texto.
/// </summary>
public class UsoIa : BaseEntity
{
    public Guid UsuarioId { get; set; }
    public Guid? InstitucionId { get; set; }

    /// <summary>plan, examen, comentario (docente); boleta, informe o comunicado (centro).</summary>
    public string Funcion { get; set; } = null!;

    public string Modelo { get; set; } = null!;
    public int TokensEntrada { get; set; }
    public int TokensSalida { get; set; }

    /// <summary>Lo que gastó del saldo del mes, en medios créditos (ver <see cref="CreditosIa"/>).</summary>
    public int Medios { get; set; }
}

/// <summary>
/// Saldo mensual de IA en créditos. Un crédito vale L 0.36 (lo que cuesta un trabajo calificado
/// en tanda) y cada función gasta lo que cuesta o un poco más, así que el saldo pone un techo al
/// costo: 140 créditos son a lo sumo L 50 al mes. Todo va en medios créditos para usar enteros.
/// </summary>
public static class CreditosIa
{
    /// <summary>Docente con Pro propio: 140 créditos.</summary>
    public const int SaldoDocente = 280;

    /// <summary>Docente con el Pro de su centro: 75 créditos.</summary>
    public const int SaldoDocenteCentro = 150;

    /// <summary>Dirección del centro: 25 créditos por cada docente activo.</summary>
    public const int SaldoDireccionPorDocente = 50;

    /// <summary>Cada página después de la primera en un trabajo con fotos.</summary>
    public const int PaginaExtra = 1;

    public static int Medios(string funcion) => funcion switch
    {
        FuncionesIa.Examen => 8,
        FuncionesIa.Plan => 6,
        FuncionesIa.Calificar => 4,
        FuncionesIa.CalificarTanda => 2,
        FuncionesIa.Informe => 6,
        FuncionesIa.Pregunta => 3,
        _ => 1, // comentario, boleta y comunicado
    };

    /// <summary>Un trabajo con fotos: la función más media por cada página extra.</summary>
    public static int Trabajo(string funcion, int paginas) => Medios(funcion) + PaginaExtra * Math.Max(0, paginas - 1);

    /// <summary>Lo que usa el docente desde su saldo.</summary>
    public static readonly string[] DelDocente =
        [FuncionesIa.Plan, FuncionesIa.Examen, FuncionesIa.Comentario, FuncionesIa.Calificar, FuncionesIa.CalificarTanda];

    /// <summary>Lo que usa la dirección desde el saldo del centro.</summary>
    public static readonly string[] DeLaDireccion =
        [FuncionesIa.Boleta, FuncionesIa.Informe, FuncionesIa.Comunicado, FuncionesIa.Pregunta];

    public static decimal Creditos(int medios) => medios / 2m;
}

public static class FuncionesIa
{
    public const string Plan = "plan";
    public const string Examen = "examen";
    public const string Comentario = "comentario";
    public const string Boleta = "boleta";
    public const string Informe = "informe";
    public const string Comunicado = "comunicado";
    public const string Calificar = "calificar";

    /// <summary>Un trabajo calificado en tanda (lote de Anthropic, a mitad de precio).</summary>
    public const string CalificarTanda = "calificar_tanda";
    public const string Pregunta = "pregunta";
}

/// <summary>
/// Trabajos de una actividad que el docente mandó a calificar juntos con fotos. Van a Anthropic
/// en un lote (mitad de precio, el resultado tarda unos minutos). Las fotos no se guardan aquí:
/// solo a qué alumno corresponde cada sugerencia y la sugerencia.
/// </summary>
public class TandaIa : BaseEntity
{
    public Guid UsuarioId { get; set; }
    public Guid? InstitucionId { get; set; }

    /// <summary>Id de la actividad en la app del docente.</summary>
    public string Actividad { get; set; } = null!;

    /// <summary>Id del lote en Anthropic.</summary>
    public string Lote { get; set; } = null!;

    public int Trabajos { get; set; }
    public decimal Puntos { get; set; }

    /// <summary>Medios créditos apartados del saldo mientras procesa.</summary>
    public int Medios { get; set; }

    /// <summary>JSON alumno → páginas, para cobrar a cada uno lo suyo al terminar.</summary>
    public string Paginas { get; set; } = "{}";

    /// <summary>procesando, lista o fallida.</summary>
    public string Estado { get; set; } = EstadosTanda.Procesando;

    /// <summary>JSON con la sugerencia de cada alumno, cuando el lote termina.</summary>
    public string? Resultados { get; set; }
}

public static class EstadosTanda
{
    public const string Procesando = "procesando";
    public const string Lista = "lista";
    public const string Fallida = "fallida";
}
