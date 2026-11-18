using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;
using ProfeApp.Domain.Centros;
using ProfeApp.Infrastructure.Persistence;

namespace ProfeApp.Infrastructure.Centros;

/// <summary>Fotos de los alumnos, logo y color del centro, y los datos para imprimir carnets.</summary>
public sealed partial class CarnetService(AppDbContext db, EstructuraCentroService centro) : ICarnetService
{
    // La app las reduce antes de subirlas (foto ~400 px, logo ~400 px): esto es solo un tope.
    private const int MaxFoto = 200 * 1024;
    private const int MaxLogo = 300 * 1024;

    [GeneratedRegex("^#[0-9A-Fa-f]{6}$")]
    private static partial Regex ColorHex();

    public async Task<Result<MarcaCentroDto>> MarcaAsync(CancellationToken ct = default)
    {
        var (institucion, _) = await centro.ContextoAsync(ct);
        if (institucion is null) return Result<MarcaCentroDto>.Fail(Error.Forbidden(EstructuraCentroService.SinCentro));
        var marca = await db.MarcasCentro.AsNoTracking().Where(m => m.InstitucionId == institucion.Id)
            .Select(m => new MarcaCentroDto(m.Color, m.Lema, m.Logo != null)).FirstOrDefaultAsync(ct);
        return marca ?? new MarcaCentroDto(MarcasCentro.ColorPorDefecto, null, false);
    }

    public async Task<Result<MarcaCentroDto>> GuardarMarcaAsync(MarcaRequest r, CancellationToken ct = default)
    {
        var (institucion, error) = await centro.EditorAsync(ct);
        if (institucion is null) return Result<MarcaCentroDto>.Fail(error!);
        var color = (r.Color ?? "").Trim();
        var lema = string.IsNullOrWhiteSpace(r.Lema) ? null : r.Lema.Trim();
        if (!ColorHex().IsMatch(color)) return Result<MarcaCentroDto>.Fail(Error.Validation("El color va como #RRGGBB."));
        if (lema?.Length > 120) return Result<MarcaCentroDto>.Fail(Error.Validation("El lema va hasta 120 caracteres."));
        var marca = await MarcaEditableAsync(institucion.Id, ct);
        marca.Color = color.ToUpperInvariant();
        marca.Lema = lema;
        await db.SaveChangesAsync(ct);
        return new MarcaCentroDto(marca.Color, marca.Lema, marca.Logo != null);
    }

    public async Task<Result<MarcaCentroDto>> GuardarLogoAsync(ImagenRequest r, CancellationToken ct = default)
    {
        var (institucion, error) = await centro.EditorAsync(ct);
        if (institucion is null) return Result<MarcaCentroDto>.Fail(error!);
        var bytes = Decodificar(r.Base64);
        var tipo = bytes is null ? null : TipoImagen(bytes);
        if (bytes is null || tipo is null) return Result<MarcaCentroDto>.Fail(Error.Validation("El logo debe ser una imagen PNG o JPG."));
        if (bytes.Length > MaxLogo) return Result<MarcaCentroDto>.Fail(Error.Validation("El logo pesa demasiado (máximo 300 KB)."));
        var marca = await MarcaEditableAsync(institucion.Id, ct);
        marca.Logo = bytes;
        marca.TipoLogo = tipo;
        await db.SaveChangesAsync(ct);
        return new MarcaCentroDto(marca.Color, marca.Lema, true);
    }

    public async Task<Result<MarcaCentroDto>> QuitarLogoAsync(CancellationToken ct = default)
    {
        var (institucion, error) = await centro.EditorAsync(ct);
        if (institucion is null) return Result<MarcaCentroDto>.Fail(error!);
        var marca = await MarcaEditableAsync(institucion.Id, ct);
        marca.Logo = null;
        marca.TipoLogo = null;
        await db.SaveChangesAsync(ct);
        return new MarcaCentroDto(marca.Color, marca.Lema, false);
    }

    public async Task<Result<CuadroExportado>> LogoAsync(CancellationToken ct = default)
    {
        var (institucion, _) = await centro.ContextoAsync(ct);
        if (institucion is null) return Result<CuadroExportado>.Fail(Error.Forbidden(EstructuraCentroService.SinCentro));
        var logo = await db.MarcasCentro.AsNoTracking().Where(m => m.InstitucionId == institucion.Id && m.Logo != null)
            .Select(m => new { m.Logo, m.TipoLogo }).FirstOrDefaultAsync(ct);
        return logo is null
            ? Result<CuadroExportado>.Fail(Error.NotFound("El logo"))
            : new CuadroExportado(logo.Logo!, "logo", logo.TipoLogo ?? "image/png");
    }

    public async Task<Result<CuadroExportado>> FotoAsync(Guid alumnoId, CancellationToken ct = default)
    {
        var (institucion, _) = await centro.ContextoAsync(ct);
        if (institucion is null) return Result<CuadroExportado>.Fail(Error.Forbidden(EstructuraCentroService.SinCentro));
        var foto = await db.FotosAlumno.AsNoTracking().Where(f => f.AlumnoId == alumnoId && f.InstitucionId == institucion.Id)
            .Select(f => f.Contenido).FirstOrDefaultAsync(ct);
        return foto is null ? Result<CuadroExportado>.Fail(Error.NotFound("La foto")) : new CuadroExportado(foto, "foto.jpg", "image/jpeg");
    }

    public async Task<Result> GuardarFotoAsync(Guid alumnoId, ImagenRequest r, CancellationToken ct = default)
    {
        var (institucion, error) = await centro.EditorAsync(ct);
        if (institucion is null) return Result.Fail(error!);
        if (!await db.Alumnos.AnyAsync(a => a.Id == alumnoId && a.InstitucionId == institucion.Id, ct))
            return Result.Fail(Error.NotFound("El alumno"));
        var bytes = Decodificar(r.Base64);
        if (bytes is null || TipoImagen(bytes) != "image/jpeg") return Result.Fail(Error.Validation("La foto debe ser JPG."));
        if (bytes.Length > MaxFoto) return Result.Fail(Error.Validation("La foto pesa demasiado (máximo 200 KB)."));
        var foto = await db.FotosAlumno.FirstOrDefaultAsync(f => f.AlumnoId == alumnoId, ct)
                   ?? db.FotosAlumno.Add(new FotoAlumno { InstitucionId = institucion.Id, AlumnoId = alumnoId }).Entity;
        foto.Contenido = bytes;
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    public async Task<Result> QuitarFotoAsync(Guid alumnoId, CancellationToken ct = default)
    {
        var (institucion, error) = await centro.EditorAsync(ct);
        if (institucion is null) return Result.Fail(error!);
        var borradas = await db.FotosAlumno.Where(f => f.AlumnoId == alumnoId && f.InstitucionId == institucion.Id).ExecuteDeleteAsync(ct);
        return borradas == 0 ? Result.Fail(Error.NotFound("La foto")) : Result.Success();
    }

    public async Task<Result<CarnetsDto>> CarnetsSeccionAsync(Guid seccionId, CancellationToken ct = default)
    {
        var (institucion, _) = await centro.ContextoAsync(ct);
        if (institucion is null) return Result<CarnetsDto>.Fail(Error.Forbidden(EstructuraCentroService.SinCentro));
        if (!await db.Secciones.AnyAsync(s => s.Id == seccionId && s.InstitucionId == institucion.Id, ct))
            return Result<CarnetsDto>.Fail(Error.NotFound("La sección"));
        return await ArmarAsync(institucion.Id, institucion.Nombre, db.Matriculas.Where(m => m.SeccionId == seccionId), ct);
    }

    public async Task<Result<CarnetsDto>> CarnetAlumnoAsync(Guid alumnoId, CancellationToken ct = default)
    {
        var (institucion, _) = await centro.ContextoAsync(ct);
        if (institucion is null) return Result<CarnetsDto>.Fail(Error.Forbidden(EstructuraCentroService.SinCentro));
        var carnets = await ArmarAsync(institucion.Id, institucion.Nombre,
            db.Matriculas.Where(m => m.AlumnoId == alumnoId && db.AniosLectivos.Any(a => a.Id == m.AnioLectivoId && a.Actual)), ct);
        return carnets.Alumnos.Count == 0
            ? Result<CarnetsDto>.Fail(Error.Validation("El alumno no tiene matrícula activa este año."))
            : carnets;
    }

    private async Task<CarnetsDto> ArmarAsync(Guid institucionId, string nombreCentro, IQueryable<Matricula> matriculas, CancellationToken ct)
    {
        var filas = await (from m in matriculas.Where(m => m.Estado == EstadosMatricula.Activa)
                           join a in db.Alumnos.AsNoTracking() on m.AlumnoId equals a.Id
                           join s in db.Secciones.AsNoTracking() on m.SeccionId equals s.Id
                           join g in db.Grados.AsNoTracking() on s.GradoId equals g.Id
                           join an in db.AniosLectivos.AsNoTracking() on m.AnioLectivoId equals an.Id
                           where a.InstitucionId == institucionId
                           orderby a.Nombre
                           select new { a.Id, a.Nombre, a.Identidad, Seccion = g.Nombre + " " + s.Nombre, s.Jornada, an.Anio })
            .ToListAsync(ct);
        var ids = filas.Select(f => f.Id).ToList();
        var fotos = await db.FotosAlumno.AsNoTracking().Where(f => ids.Contains(f.AlumnoId)).ToDictionaryAsync(f => f.AlumnoId, f => f.Contenido, ct);
        var marca = await db.MarcasCentro.AsNoTracking().FirstOrDefaultAsync(m => m.InstitucionId == institucionId, ct);
        var anio = filas.Select(f => (int?)f.Anio).FirstOrDefault()
                   ?? await db.AniosLectivos.Where(a => a.InstitucionId == institucionId && a.Actual).Select(a => a.Anio).FirstOrDefaultAsync(ct);
        return new CarnetsDto(nombreCentro, marca?.Color ?? MarcasCentro.ColorPorDefecto, marca?.Lema,
            marca?.Logo is { } logo ? Convert.ToBase64String(logo) : null, anio,
            filas.Select(f => new CarnetAlumnoDto(f.Id, f.Nombre, f.Identidad, f.Seccion, f.Jornada,
                fotos.TryGetValue(f.Id, out var foto) ? Convert.ToBase64String(foto) : null)).ToList());
    }

    private async Task<MarcaCentro> MarcaEditableAsync(Guid institucionId, CancellationToken ct) =>
        await db.MarcasCentro.FirstOrDefaultAsync(m => m.InstitucionId == institucionId, ct)
        ?? db.MarcasCentro.Add(new MarcaCentro { InstitucionId = institucionId }).Entity;

    private static byte[]? Decodificar(string? base64)
    {
        if (string.IsNullOrWhiteSpace(base64)) return null;
        try { return Convert.FromBase64String(base64); }
        catch (FormatException) { return null; }
    }

    /// <summary>Por los primeros bytes, no por lo que diga el cliente.</summary>
    private static string? TipoImagen(byte[] b) =>
        b.Length > 8 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF ? "image/jpeg"
        : b.Length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47 ? "image/png"
        : null;
}
