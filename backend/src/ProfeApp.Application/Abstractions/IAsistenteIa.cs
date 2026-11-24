using System.Text.Json;
using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;

namespace ProfeApp.Application.Abstractions;

/// <summary>Asistente con IA del docente (plan Pro): propone; el docente revisa y decide.</summary>
public interface IAsistenteIaService
{
    Task<EstadoIaDto> EstadoAsync(CancellationToken ct = default);
    Task<Result<PlanIaDto>> PlanAsync(PlanIaRequest request, CancellationToken ct = default);
    Task<Result<ExamenIaDto>> ExamenAsync(ExamenIaRequest request, CancellationToken ct = default);
    Task<Result<ComentarioIaDto>> ComentarioAsync(ComentarioIaRequest request, CancellationToken ct = default);
    Task<Result<CalificacionIaDto>> CalificarAsync(CalificarIaRequest request, CancellationToken ct = default);

    /// <summary>Manda a calificar en tanda (hasta 10 trabajos por envío); los resultados llegan en minutos.</summary>
    Task<Result<TandaIaDto>> CalificarTandaAsync(CalificarTandaIaRequest request, CancellationToken ct = default);

    /// <summary>Las tandas de los últimos 7 días de una actividad, con sus resultados si ya están.</summary>
    Task<IReadOnlyList<TandaIaDto>> TandasAsync(string actividad, CancellationToken ct = default);
}

/// <summary>
/// Una petición al modelo. <c>Esquema</c>: JSON Schema de la respuesta; null = texto libre.
/// <c>Imagenes</c>: fotos JPEG que van antes del texto. <c>Historial</c>: turnos anteriores
/// (pregunta, respuesta) de una conversación.
/// </summary>
public sealed record PeticionIa(
    string Sistema, string Usuario, IReadOnlyDictionary<string, JsonElement>? Esquema, int MaxTokens, bool Breve,
    IReadOnlyList<byte[]>? Imagenes = null, IReadOnlyList<(string Pregunta, string Respuesta)>? Historial = null);

/// <summary><c>Rechazada</c>: el modelo declinó responder (filtros de seguridad).</summary>
public sealed record RespuestaIa(string Texto, string Modelo, int TokensEntrada, int TokensSalida, bool Rechazada = false);

/// <summary>Quien llama al modelo. En pruebas se reemplaza por uno que no sale a internet.</summary>
public interface IGeneradorIa
{
    bool Disponible { get; }
    Task<RespuestaIa> GenerarAsync(PeticionIa peticion, CancellationToken ct);

    /// <summary>Manda varias peticiones en un lote (mitad de precio, tarda minutos). Devuelve el id del lote.</summary>
    Task<string> CrearLoteAsync(IReadOnlyList<(string Id, PeticionIa Peticion)> peticiones, CancellationToken ct);

    /// <summary>
    /// Null mientras el lote sigue en proceso. Al terminar, la respuesta de cada petición (null si
    /// falló o venció: no se cobra) y el lote se borra en Anthropic.
    /// </summary>
    Task<IReadOnlyList<(string Id, RespuestaIa? Respuesta)>?> ResultadosLoteAsync(string lote, CancellationToken ct);
}

/// <summary>Asistente del centro (plan Pro del centro): boletas, informe de dirección y comunicados.</summary>
public interface ICentroIaService
{
    Task<Result<EstadoIaCentroDto>> EstadoAsync(CancellationToken ct = default);
    Task<Result<ComentariosSeccionDto>> ComentariosAsync(Guid seccionId, int parcial, CancellationToken ct = default);

    /// <summary>Pone en cola la redacción de los comentarios de la sección; vuelve enseguida.</summary>
    Task<Result<ComentariosSeccionDto>> GenerarComentariosAsync(Guid seccionId, GenerarComentariosRequest request, CancellationToken ct = default);

    Task<Result> EditarComentarioAsync(Guid seccionId, Guid alumnoId, EditarComentarioRequest request, CancellationToken ct = default);
    Task<Result<InformeIaDto>> InformeAsync(CancellationToken ct = default);
    Task<Result<ComunicadoIaDto>> ComunicadoAsync(ComunicadoIaRequest request, CancellationToken ct = default);

    /// <summary>Responde preguntas de la dirección con las cifras del centro (sin nombres de alumnos).</summary>
    Task<Result<RespuestaIaDto>> PreguntarAsync(PreguntaIaRequest request, CancellationToken ct = default);
}

/// <summary>Cuánto cuesta la IA en un mes, por función y por cuenta. Solo para la plataforma.</summary>
public interface ICostosIaService
{
    Task<CostosIaDto> CostosAsync(int? anio, int? mes, CancellationToken ct = default);
}

/// <summary>Programas curriculares oficiales (Media por carrera, Básica por área y mes).</summary>
public interface IProgramasCurriculares
{
    /// <summary>El programa de la asignatura de un cuadro de SACE, o null si no lo hay.</summary>
    ProgramaDto? Buscar(string? modalidad, string? grado, string? asignatura);

    /// <summary>
    /// El texto del programa para la IA: en Media, los resultados de aprendizaje elegidos (todos si
    /// no viene ninguno) con criterios y contenidos; en Básica, lo de los meses del parcial.
    /// </summary>
    string? Contexto(string? modalidad, string? grado, string? asignatura, string? parcial, IReadOnlyList<string>? resultados);
}
