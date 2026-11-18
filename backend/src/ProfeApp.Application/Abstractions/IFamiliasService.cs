using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;

namespace ProfeApp.Application.Abstractions;

/// <summary>El centro da acceso a las familias y les publica comunicados.</summary>
public interface IFamiliasCentroService
{
    Task<Result<FamiliaAlumnoDto>> FamiliaAsync(Guid alumnoId, CancellationToken ct = default);
    Task<Result<CodigoFamiliaDto>> GenerarCodigoAsync(Guid alumnoId, CancellationToken ct = default);
    Task<Result> QuitarAccesoAsync(Guid alumnoId, Guid usuarioId, CancellationToken ct = default);

    Task<Result<IReadOnlyList<ComunicadoCentroDto>>> ComunicadosAsync(CancellationToken ct = default);
    Task<Result<ComunicadoCentroDto>> PublicarAsync(ComunicadoRequest request, CancellationToken ct = default);
    Task<Result> EliminarComunicadoAsync(Guid id, CancellationToken ct = default);
}

/// <summary>Lo que ve el padre: sus hijos vinculados, su avance y los comunicados.</summary>
public interface IPadresService
{
    Task<Result<HijoDto>> VincularAsync(CodigoRequest request, CancellationToken ct = default);
    Task<IReadOnlyList<HijoDto>> HijosAsync(CancellationToken ct = default);
    Task<Result<ResumenHijoDto>> ResumenAsync(Guid alumnoId, CancellationToken ct = default);
    Task<IReadOnlyList<ComunicadoPadreDto>> ComunicadosAsync(CancellationToken ct = default);
    Task<Result> MarcarLeidoAsync(Guid comunicadoId, CancellationToken ct = default);
}
