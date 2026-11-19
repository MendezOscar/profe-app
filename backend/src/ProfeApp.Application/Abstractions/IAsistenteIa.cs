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
}

/// <summary>Una petición al modelo. <c>Esquema</c>: JSON Schema de la respuesta; null = texto libre.</summary>
public sealed record PeticionIa(string Sistema, string Usuario, IReadOnlyDictionary<string, JsonElement>? Esquema, int MaxTokens, bool Breve);

/// <summary><c>Rechazada</c>: el modelo declinó responder (filtros de seguridad).</summary>
public sealed record RespuestaIa(string Texto, string Modelo, int TokensEntrada, int TokensSalida, bool Rechazada = false);

/// <summary>Quien llama al modelo. En pruebas se reemplaza por uno que no sale a internet.</summary>
public interface IGeneradorIa
{
    bool Disponible { get; }
    Task<RespuestaIa> GenerarAsync(PeticionIa peticion, CancellationToken ct);
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
}
