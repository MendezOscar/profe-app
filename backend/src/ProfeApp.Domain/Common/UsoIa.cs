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
}
