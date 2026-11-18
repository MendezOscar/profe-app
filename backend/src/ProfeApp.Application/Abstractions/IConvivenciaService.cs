using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;

namespace ProfeApp.Application.Abstractions;

/// <summary>Excusas y permisos que registra el centro, e incidencias disciplinarias.</summary>
public interface IConvivenciaService
{
    /// <summary>Las que terminan desde <paramref name="desde"/> (por defecto, hace 30 días); de un alumno si se indica.</summary>
    Task<Result<IReadOnlyList<ExcusaDto>>> ExcusasAsync(DateOnly? desde, Guid? alumnoId, CancellationToken ct = default);

    Task<Result<ExcusaDto>> RegistrarExcusaAsync(ExcusaRequest request, CancellationToken ct = default);
    Task<Result> EliminarExcusaAsync(Guid id, CancellationToken ct = default);

    /// <summary>Las de ese día de los alumnos de las secciones donde el docente da clase o es guía.</summary>
    Task<IReadOnlyList<ExcusaDocenteDto>> ExcusasDelDocenteAsync(DateOnly fecha, CancellationToken ct = default);

    /// <summary>Del año actual (las más recientes primero); de un alumno, o solo las abiertas.</summary>
    Task<Result<IReadOnlyList<IncidenciaDto>>> IncidenciasAsync(Guid? alumnoId, bool soloAbiertas, CancellationToken ct = default);

    Task<Result<IncidenciaDto>> RegistrarIncidenciaAsync(IncidenciaRequest request, CancellationToken ct = default);
    Task<Result<IncidenciaDto>> SeguimientoAsync(Guid id, SeguimientoIncidenciaRequest request, CancellationToken ct = default);
    Task<Result> EliminarIncidenciaAsync(Guid id, CancellationToken ct = default);

    /// <summary>Las que registró el docente que llama en el año actual.</summary>
    Task<IReadOnlyList<IncidenciaDto>> IncidenciasDelDocenteAsync(CancellationToken ct = default);

    Task<Result<IncidenciaDto>> RegistrarIncidenciaDocenteAsync(IncidenciaDocenteRequest request, CancellationToken ct = default);
}
