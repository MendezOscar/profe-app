using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;

namespace ProfeApp.Application.Abstractions;

public interface IReportesService
{
    Task<Result<ReportesDto>> ResumenAsync(CancellationToken ct = default);

    /// <summary>Estadísticas de cada docente en el año actual: carga, avance, listas y rendimiento.</summary>
    Task<Result<EstadisticasDocentesDto>> DocentesAsync(CancellationToken ct = default);
}
