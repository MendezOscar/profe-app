using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;

namespace ProfeApp.Application.Abstractions;

/// <summary>Panel del administrador de un centro: sus docentes y el avance de cada uno.</summary>
public interface ICentroService
{
    Task<Result<CentroDto>> ObtenerAsync(CancellationToken ct = default);
    Task<Result<CuentaCreada>> CrearDocenteAsync(CrearDocenteRequest request, CancellationToken ct = default);
    Task<Result> CambiarEstadoDocenteAsync(Guid docenteId, bool activo, CancellationToken ct = default);
    Task<Result<CuentaCreada>> RestablecerClaveAsync(Guid docenteId, CancellationToken ct = default);
}

/// <summary>Operación de ProfeApp: centros con licencia y cuentas del plan personal.</summary>
public interface IPlataformaService
{
    Task<Result<IReadOnlyList<InstitucionDto>>> InstitucionesAsync(CancellationToken ct = default);
    Task<Result<InstitucionCreada>> CrearInstitucionAsync(CrearInstitucionRequest request, CancellationToken ct = default);
    Task<Result<InstitucionDto>> ActualizarInstitucionAsync(Guid id, ActualizarInstitucionRequest request, CancellationToken ct = default);
    Task<Result<CuentaCreada>> CrearDocentePersonalAsync(CrearDocenteRequest request, CancellationToken ct = default);
}
