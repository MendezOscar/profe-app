using Microsoft.EntityFrameworkCore;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;
using ProfeApp.Domain.Centros;
using ProfeApp.Infrastructure.Persistence;

namespace ProfeApp.Infrastructure.Centros;

/// <summary>Códigos de familia, cuentas vinculadas y comunicados, del lado del centro.</summary>
public sealed class FamiliasCentroService(
    AppDbContext db,
    EstructuraCentroService centro,
    ICurrentUser currentUser,
    IClock clock,
    IAvisosPush avisos) : IFamiliasCentroService
{
    private const int ComunicadosVisibles = 50;

    public async Task<Result<FamiliaAlumnoDto>> FamiliaAsync(Guid alumnoId, CancellationToken ct = default)
    {
        var (institucion, _) = await centro.ContextoAsync(ct);
        if (institucion is null) return Result<FamiliaAlumnoDto>.Fail(Error.Forbidden(EstructuraCentroService.SinCentro));
        if (!await db.Alumnos.AnyAsync(a => a.Id == alumnoId && a.InstitucionId == institucion.Id, ct))
            return Result<FamiliaAlumnoDto>.Fail(Error.NotFound("El alumno"));

        var codigo = await db.CodigosFamilia.AsNoTracking()
            .Where(c => c.AlumnoId == alumnoId && c.ExpiraEn > clock.Now)
            .Select(c => new CodigoFamiliaDto(c.Codigo, c.ExpiraEn)).FirstOrDefaultAsync(ct);
        var vinculos = await (from v in db.VinculosFamiliares.AsNoTracking()
                              join u in db.Users.AsNoTracking() on v.UsuarioId equals u.Id
                              where v.AlumnoId == alumnoId
                              orderby v.CreatedAt
                              select new VinculoDto(u.Id, u.FullName, u.Email!, v.CreatedAt))
            .ToListAsync(ct);
        return new FamiliaAlumnoDto(codigo is null ? null : codigo with { Codigo = CodigosFamilia.Mostrar(codigo.Codigo) }, vinculos);
    }

    public async Task<Result<CodigoFamiliaDto>> GenerarCodigoAsync(Guid alumnoId, CancellationToken ct = default)
    {
        var (institucion, error) = await centro.EditorAsync(ct);
        if (institucion is null) return Result<CodigoFamiliaDto>.Fail(error!);
        if (!await db.Alumnos.AnyAsync(a => a.Id == alumnoId && a.InstitucionId == institucion.Id, ct))
            return Result<CodigoFamiliaDto>.Fail(Error.NotFound("El alumno"));

        var fila = await db.CodigosFamilia.FirstOrDefaultAsync(c => c.AlumnoId == alumnoId, ct)
                   ?? db.CodigosFamilia.Add(new CodigoFamilia { InstitucionId = institucion.Id, AlumnoId = alumnoId }).Entity;
        // Uno nuevo cada vez: el anterior deja de servir. El índice único evita choques.
        string codigo;
        do codigo = CodigosFamilia.Generar();
        while (await db.CodigosFamilia.AnyAsync(c => c.Codigo == codigo, ct));
        fila.Codigo = codigo;
        fila.ExpiraEn = clock.Now.Add(CodigosFamilia.Vigencia);
        await db.SaveChangesAsync(ct);
        return new CodigoFamiliaDto(CodigosFamilia.Mostrar(codigo), fila.ExpiraEn);
    }

    public async Task<Result> QuitarAccesoAsync(Guid alumnoId, Guid usuarioId, CancellationToken ct = default)
    {
        var (institucion, error) = await centro.EditorAsync(ct);
        if (institucion is null) return Result.Fail(error!);
        var borrados = await db.VinculosFamiliares
            .Where(v => v.AlumnoId == alumnoId && v.UsuarioId == usuarioId && v.InstitucionId == institucion.Id)
            .ExecuteDeleteAsync(ct);
        return borrados == 0 ? Result.Fail(Error.NotFound("El acceso")) : Result.Success();
    }

    public async Task<Result<IReadOnlyList<ComunicadoCentroDto>>> ComunicadosAsync(CancellationToken ct = default)
    {
        var (institucion, _) = await centro.ContextoAsync(ct);
        if (institucion is null) return Result<IReadOnlyList<ComunicadoCentroDto>>.Fail(Error.Forbidden(EstructuraCentroService.SinCentro));

        var comunicados = await (from c in db.Comunicados.AsNoTracking()
                                 join u in db.Users.AsNoTracking() on c.AutorId equals u.Id into autores
                                 from u in autores.DefaultIfEmpty()
                                 where c.InstitucionId == institucion.Id
                                 orderby c.PublicadoEn descending
                                 select new { c, Autor = u == null ? null : u.FullName })
            .Take(ComunicadosVisibles).ToListAsync(ct);
        var ids = comunicados.Select(x => x.c.Id).ToList();
        var leidos = await db.LecturasComunicados.Where(l => ids.Contains(l.ComunicadoId))
            .GroupBy(l => l.ComunicadoId).Select(g => new { g.Key, N = g.Count() })
            .ToDictionaryAsync(x => x.Key, x => x.N, ct);
        var familias = await FamiliasPorSeccionAsync(institucion.Id, ct);

        return comunicados.Select(x => ADto(x.c, x.Autor, leidos.GetValueOrDefault(x.c.Id), familias)).ToList();
    }

    public async Task<Result<ComunicadoCentroDto>> PublicarAsync(ComunicadoRequest r, CancellationToken ct = default)
    {
        var (institucion, error) = await centro.EditorAsync(ct);
        if (institucion is null) return Result<ComunicadoCentroDto>.Fail(error!);
        var titulo = (r.Titulo ?? "").Trim();
        var cuerpo = (r.Cuerpo ?? "").Trim();
        if (titulo.Length is 0 or > 160) return Result<ComunicadoCentroDto>.Fail(Error.Validation("El título es obligatorio (hasta 160 caracteres)."));
        if (cuerpo.Length is 0 or > 4000) return Result<ComunicadoCentroDto>.Fail(Error.Validation("El mensaje es obligatorio (hasta 4000 caracteres)."));
        var secciones = (r.SeccionIds ?? []).Distinct().ToList();
        if (secciones.Count > 0
            && await db.Secciones.CountAsync(s => secciones.Contains(s.Id) && s.InstitucionId == institucion.Id, ct) != secciones.Count)
            return Result<ComunicadoCentroDto>.Fail(Error.Validation("Elige secciones de tu centro."));

        var comunicado = new Comunicado
        {
            InstitucionId = institucion.Id,
            Titulo = titulo,
            Cuerpo = cuerpo,
            SeccionIds = secciones,
            AutorId = currentUser.RequireUserId(),
            PublicadoEn = clock.Now,
        };
        db.Comunicados.Add(comunicado);
        await db.SaveChangesAsync(ct);
        var familias = await FamiliasPorSeccionAsync(institucion.Id, ct);
        avisos.Encolar(new AvisoPush(
            familias.Where(f => secciones.Count == 0 || secciones.Contains(f.Seccion)).Select(f => f.Usuario).Distinct().ToList(),
            $"{institucion.Nombre}: {titulo}",
            cuerpo.Length > 140 ? cuerpo[..137] + "…" : cuerpo,
            "/familia"));
        return ADto(comunicado, null, 0, familias);
    }

    public async Task<Result> EliminarComunicadoAsync(Guid id, CancellationToken ct = default)
    {
        var (institucion, error) = await centro.EditorAsync(ct);
        if (institucion is null) return Result.Fail(error!);
        var borrados = await db.Comunicados.Where(c => c.Id == id && c.InstitucionId == institucion.Id).ExecuteDeleteAsync(ct);
        return borrados == 0 ? Result.Fail(Error.NotFound("El comunicado")) : Result.Success();
    }

    /// <summary>Cuentas de familia con hijos matriculados este año, y la sección de cada hijo.</summary>
    private async Task<List<(Guid Usuario, Guid Seccion)>> FamiliasPorSeccionAsync(Guid institucionId, CancellationToken ct)
    {
        var anio = await db.AniosLectivos.Where(a => a.InstitucionId == institucionId && a.Actual).Select(a => (Guid?)a.Id).FirstOrDefaultAsync(ct);
        if (anio is null) return [];
        return (await (from v in db.VinculosFamiliares
                       join m in db.Matriculas on v.AlumnoId equals m.AlumnoId
                       where v.InstitucionId == institucionId && m.AnioLectivoId == anio && m.Estado == EstadosMatricula.Activa
                       select new { v.UsuarioId, m.SeccionId })
                .Distinct().ToListAsync(ct))
            .Select(x => (x.UsuarioId, x.SeccionId)).ToList();
    }

    private static ComunicadoCentroDto ADto(Comunicado c, string? autor, int leidos, List<(Guid Usuario, Guid Seccion)> familias) =>
        new(c.Id, c.Titulo, c.Cuerpo, c.SeccionIds, c.PublicadoEn, autor, leidos,
            familias.Where(f => c.SeccionIds.Count == 0 || c.SeccionIds.Contains(f.Seccion)).Select(f => f.Usuario).Distinct().Count());
}
