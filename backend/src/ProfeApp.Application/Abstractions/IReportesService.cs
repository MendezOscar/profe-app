using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;

namespace ProfeApp.Application.Abstractions;

public interface IReportesService
{
    Task<Result<ReportesDto>> ResumenAsync(CancellationToken ct = default);
}
