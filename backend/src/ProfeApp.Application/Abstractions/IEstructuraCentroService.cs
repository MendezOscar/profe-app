using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;

namespace ProfeApp.Application.Abstractions;

/// <summary>
/// Organización académica del centro (años lectivos, grados y asignaturas, aulas, secciones
/// y carga docente) y su personal. Orientación consulta; dirección y secretaría editan.
/// </summary>
public interface IEstructuraCentroService
{
    Task<Result<EstructuraDto>> ObtenerAsync(Guid? anioId, CancellationToken ct = default);

    Task<Result<AnioLectivoDto>> GuardarAnioAsync(Guid? id, AnioLectivoRequest request, CancellationToken ct = default);

    Task<Result<GradoDto>> GuardarGradoAsync(Guid? id, GradoRequest request, CancellationToken ct = default);
    Task<Result<int>> PlantillaGradosAsync(PlantillaGradosRequest request, CancellationToken ct = default);
    Task<Result> EliminarGradoAsync(Guid id, CancellationToken ct = default);

    Task<Result<int>> AgregarAsignaturasAsync(AgregarAsignaturasRequest request, CancellationToken ct = default);
    Task<Result> RenombrarAsignaturaAsync(Guid id, NombreRequest request, CancellationToken ct = default);
    Task<Result> EliminarAsignaturaAsync(Guid id, CancellationToken ct = default);

    Task<Result<AulaDto>> GuardarAulaAsync(Guid? id, AulaRequest request, CancellationToken ct = default);
    Task<Result> EliminarAulaAsync(Guid id, CancellationToken ct = default);

    Task<Result<SeccionDto>> GuardarSeccionAsync(Guid? id, SeccionRequest request, CancellationToken ct = default);
    Task<Result> EliminarSeccionAsync(Guid id, CancellationToken ct = default);
    Task<Result<SeccionDto>> GuardarCargaAsync(Guid seccionId, CargaRequest request, CancellationToken ct = default);

    Task<Result<IReadOnlyList<PersonalDto>>> PersonalAsync(CancellationToken ct = default);
    Task<Result<CuentaCreada>> CrearPersonalAsync(CrearPersonalRequest request, CancellationToken ct = default);
    Task<Result> CambiarCargoAsync(Guid id, CargoRequest request, CancellationToken ct = default);
    Task<Result> CambiarEstadoPersonalAsync(Guid id, bool activo, CancellationToken ct = default);
    Task<Result<CuentaCreada>> RestablecerClavePersonalAsync(Guid id, CancellationToken ct = default);
}
