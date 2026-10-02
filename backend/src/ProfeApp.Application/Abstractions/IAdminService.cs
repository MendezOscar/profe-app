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

    Task<Result<PaginaDocentes>> DocentesAsync(string? buscar, int pagina, CancellationToken ct = default);
    Task<Result<CobroDto>> FijarPlanAsync(TipoCuenta tipo, Guid id, PlanCobroRequest request, CancellationToken ct = default);
    Task<Result<CobroDto>> RegistrarPagoAsync(TipoCuenta tipo, Guid id, RegistrarPagoRequest request, CancellationToken ct = default);
    Task<Result<IReadOnlyList<PagoDto>>> PagosAsync(TipoCuenta tipo, Guid id, CancellationToken ct = default);
    Task<Result> CambiarEstadoAsync(TipoCuenta tipo, Guid id, bool activa, CancellationToken ct = default);

    /// <summary>Del docente personal, o del administrador del centro.</summary>
    Task<Result<CuentaCreada>> ReponerClaveAsync(TipoCuenta tipo, Guid id, CancellationToken ct = default);
}

/// <summary>A quién se le cobra: al docente del plan personal (por su usuario) o al centro.</summary>
public enum TipoCuenta { Docente, Centro }

/// <summary>
/// El cobro de la cuenta del usuario que llama, y el candado que frena la sincronización
/// cuando venció y pasó la gracia, o cuando una asignatura nueva pasa el tope del plan.
/// </summary>
public interface ICobroService
{
    Task<CobroDto> MioAsync(CancellationToken ct = default);
    Task<Error?> BloqueoDeSyncAsync(SyncPushRequest request, CancellationToken ct = default);

    /// <summary>Tras cambiarle el plan o registrar un pago: el aviso cambia ya, no en cinco minutos.</summary>
    void Olvidar(Guid cuentaId);
}
