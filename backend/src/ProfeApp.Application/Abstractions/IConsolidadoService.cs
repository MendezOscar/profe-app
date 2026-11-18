using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;

namespace ProfeApp.Application.Abstractions;

public interface IConsolidadoService
{
    Task<Result<ConsolidadoDto>> SeccionAsync(Guid seccionId, CancellationToken ct = default);

    /// <summary>Los cuadros de SACE de la sección, llenos, en un .zip (uno por asignatura).</summary>
    Task<Result<CuadroExportado>> CuadrosSaceAsync(Guid seccionId, CancellationToken ct = default);
}
