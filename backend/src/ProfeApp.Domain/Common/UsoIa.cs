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
