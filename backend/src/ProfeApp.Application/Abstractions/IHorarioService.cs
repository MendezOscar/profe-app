using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;

namespace ProfeApp.Application.Abstractions;

/// <summary>Bloques y horario de las secciones, con choques de docente y aula; asistencia diaria.</summary>
public interface IHorarioService
{
    Task<Result<IReadOnlyList<BloqueDto>>> BloquesAsync(CancellationToken ct = default);
    Task<Result<BloqueDto>> GuardarBloqueAsync(Guid? id, BloqueRequest request, CancellationToken ct = default);
    Task<Result> EliminarBloqueAsync(Guid id, CancellationToken ct = default);

    Task<Result<HorarioSeccionDto>> HorarioSeccionAsync(Guid seccionId, CancellationToken ct = default);
    Task<Result<HorarioSeccionDto>> GuardarHorarioAsync(Guid seccionId, HorarioSeccionRequest request, CancellationToken ct = default);
    Task<Result<IReadOnlyList<ClaseHorarioDto>>> HorarioDocenteAsync(Guid docenteId, CancellationToken ct = default);
    Task<Result<IReadOnlyList<string>>> ChoquesAsync(CancellationToken ct = default);

    Task<Result<AsistenciaDelDiaDto>> AsistenciaDelDiaAsync(DateOnly fecha, CancellationToken ct = default);

    // Del maestro guía, desde la app.
    Task<Result<ListaDiariaDto>> ListaDiariaAsync(Guid seccionId, DateOnly fecha, CancellationToken ct = default);
    Task<Result<ConductaSeccionDto>> ConductaAsync(Guid seccionId, int parcial, CancellationToken ct = default);
    Task<Result<ConductaSeccionDto>> GuardarConductaAsync(Guid seccionId, ConductaRequest request, CancellationToken ct = default);
    Task<Result<ListaDiariaDto>> GuardarListaDiariaAsync(Guid seccionId, ListaDiariaRequest request, CancellationToken ct = default);
}
