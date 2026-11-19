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
