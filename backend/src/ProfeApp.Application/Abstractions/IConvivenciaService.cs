using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;

namespace ProfeApp.Application.Abstractions;

/// <summary>Excusas y permisos de los alumnos que registra el centro.</summary>
public interface IConvivenciaService
{
    /// <summary>Las que terminan desde <paramref name="desde"/> (por defecto, hace 30 días); de un alumno si se indica.</summary>
    Task<Result<IReadOnlyList<ExcusaDto>>> ExcusasAsync(DateOnly? desde, Guid? alumnoId, CancellationToken ct = default);

    Task<Result<ExcusaDto>> RegistrarExcusaAsync(ExcusaRequest request, CancellationToken ct = default);
    Task<Result> EliminarExcusaAsync(Guid id, CancellationToken ct = default);

    /// <summary>Las de ese día de los alumnos de las secciones donde el docente da clase o es guía.</summary>
    Task<IReadOnlyList<ExcusaDocenteDto>> ExcusasDelDocenteAsync(DateOnly fecha, CancellationToken ct = default);
}
