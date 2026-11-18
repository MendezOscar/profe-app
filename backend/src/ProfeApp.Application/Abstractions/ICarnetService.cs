using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;

namespace ProfeApp.Application.Abstractions;

/// <summary>Fotos de los alumnos, marca del centro (logo, color, lema) y datos para los carnets.</summary>
public interface ICarnetService
{
    Task<Result<MarcaCentroDto>> MarcaAsync(CancellationToken ct = default);
    Task<Result<MarcaCentroDto>> GuardarMarcaAsync(MarcaRequest request, CancellationToken ct = default);
    Task<Result<MarcaCentroDto>> GuardarLogoAsync(ImagenRequest request, CancellationToken ct = default);
    Task<Result<MarcaCentroDto>> QuitarLogoAsync(CancellationToken ct = default);
    Task<Result<CuadroExportado>> LogoAsync(CancellationToken ct = default);

    Task<Result<CuadroExportado>> FotoAsync(Guid alumnoId, CancellationToken ct = default);
    Task<Result> GuardarFotoAsync(Guid alumnoId, ImagenRequest request, CancellationToken ct = default);
    Task<Result> QuitarFotoAsync(Guid alumnoId, CancellationToken ct = default);

    /// <summary>Alumnos activos de la sección.</summary>
    Task<Result<CarnetsDto>> CarnetsSeccionAsync(Guid seccionId, CancellationToken ct = default);

    /// <summary>Un alumno, con su matrícula activa del año actual.</summary>
    Task<Result<CarnetsDto>> CarnetAlumnoAsync(Guid alumnoId, CancellationToken ct = default);
}
