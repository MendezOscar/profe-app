using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;

namespace ProfeApp.Application.Abstractions;

/// <summary>
/// Matrícula y fichas de los alumnos del centro. SACE es la fuente: la lista de una sección
/// se importa de su archivo. Orientación consulta; dirección y secretaría editan.
/// </summary>
public interface IMatriculaService
{
    Task<Result<IReadOnlyList<AlumnoSeccionDto>>> AlumnosDeSeccionAsync(Guid seccionId, CancellationToken ct = default);
    Task<Result<ImportacionDto>> ImportarAsync(Guid seccionId, ImportarAlumnosRequest request, CancellationToken ct = default);
    Task<Result<AlumnoSeccionDto>> MatricularAsync(Guid seccionId, MatricularRequest request, CancellationToken ct = default);

    Task<Result<PaginaAlumnosDto>> BuscarAsync(string? buscar, int pagina, CancellationToken ct = default);
    Task<Result<FichaAlumnoDto>> FichaAsync(Guid alumnoId, CancellationToken ct = default);
    Task<Result<FichaAlumnoDto>> GuardarFichaAsync(Guid alumnoId, FichaAlumnoRequest request, CancellationToken ct = default);

    Task<Result> DarDeBajaAsync(Guid matriculaId, BajaRequest request, CancellationToken ct = default);
    Task<Result> ReactivarAsync(Guid matriculaId, CancellationToken ct = default);
    Task<Result> CambiarSeccionAsync(Guid matriculaId, CambioSeccionRequest request, CancellationToken ct = default);
}
