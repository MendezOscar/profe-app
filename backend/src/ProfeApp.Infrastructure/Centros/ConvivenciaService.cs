using Microsoft.EntityFrameworkCore;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;
using ProfeApp.Domain.Centros;
using ProfeApp.Infrastructure.Persistence;

namespace ProfeApp.Infrastructure.Centros;

/// <summary>Excusas y permisos que registra el centro y que ve quien pasa lista.</summary>
public sealed class ConvivenciaService(
    AppDbContext db,
    EstructuraCentroService centro,
    ICurrentUser currentUser,
    IClock clock) : IConvivenciaService
{
    private const int ExcusasVisibles = 300;
    private const int DiasMaximos = 180;

    public async Task<Result<IReadOnlyList<ExcusaDto>>> ExcusasAsync(DateOnly? desde, Guid? alumnoId, CancellationToken ct = default)
    {
        var (institucion, _) = await centro.ContextoAsync(ct);
        if (institucion is null) return Result<IReadOnlyList<ExcusaDto>>.Fail(Error.Forbidden(EstructuraCentroService.SinCentro));
        var inicio = desde ?? clock.Today.AddDays(-30);
        var filas = await (from e in db.Excusas.AsNoTracking()
                           join a in db.Alumnos.AsNoTracking() on e.AlumnoId equals a.Id
                           join u in db.Users.AsNoTracking() on e.RegistradaPor equals u.Id into autores
                           from u in autores.DefaultIfEmpty()
                           where e.InstitucionId == institucion.Id && e.Hasta >= inicio && (alumnoId == null || e.AlumnoId == alumnoId)
                           orderby e.Desde descending, a.Nombre
                           select new { e, Alumno = a.Nombre, Autor = u == null ? null : u.FullName })
            .Take(ExcusasVisibles).ToListAsync(ct);
        var secciones = await SeccionesAsync(institucion.Id, filas.Select(f => f.e.AlumnoId).Distinct().ToList(), ct);
        return filas.Select(f => ADto(f.e, f.Alumno, secciones.GetValueOrDefault(f.e.AlumnoId), f.Autor)).ToList();
    }

    public async Task<Result<ExcusaDto>> RegistrarExcusaAsync(ExcusaRequest r, CancellationToken ct = default)
    {
        var (institucion, error) = await centro.EditorAsync(ct);
        if (institucion is null) return Result<ExcusaDto>.Fail(error!);
        var tipo = (r.Tipo ?? "").Trim().ToLowerInvariant();
        var motivo = (r.Motivo ?? "").Trim();
        if (!TiposExcusa.Todos.Contains(tipo)) return Result<ExcusaDto>.Fail(Error.Validation("Elige excusa o permiso."));
        if (motivo.Length is 0 or > 300) return Result<ExcusaDto>.Fail(Error.Validation("El motivo es obligatorio (hasta 300 caracteres)."));
        if (r.Hasta < r.Desde) return Result<ExcusaDto>.Fail(Error.Validation("La fecha final es antes de la inicial."));
        if (r.Hasta.DayNumber - r.Desde.DayNumber >= DiasMaximos)
            return Result<ExcusaDto>.Fail(Error.Validation($"Una excusa cubre hasta {DiasMaximos} días."));
        var alumno = await db.Alumnos.AsNoTracking().Where(a => a.Id == r.AlumnoId && a.InstitucionId == institucion.Id)
            .Select(a => a.Nombre).FirstOrDefaultAsync(ct);
        if (alumno is null) return Result<ExcusaDto>.Fail(Error.NotFound("El alumno"));

        var excusa = new Excusa
        {
            InstitucionId = institucion.Id,
            AlumnoId = r.AlumnoId,
            Tipo = tipo,
            Desde = r.Desde,
            Hasta = r.Hasta,
            Motivo = motivo,
            RegistradaPor = currentUser.RequireUserId(),
        };
        db.Excusas.Add(excusa);
        await db.SaveChangesAsync(ct);
        var secciones = await SeccionesAsync(institucion.Id, [r.AlumnoId], ct);
        return ADto(excusa, alumno, secciones.GetValueOrDefault(r.AlumnoId), null);
    }

    public async Task<Result> EliminarExcusaAsync(Guid id, CancellationToken ct = default)
    {
        var (institucion, error) = await centro.EditorAsync(ct);
        if (institucion is null) return Result.Fail(error!);
        var borradas = await db.Excusas.Where(e => e.Id == id && e.InstitucionId == institucion.Id).ExecuteDeleteAsync(ct);
        return borradas == 0 ? Result.Fail(Error.NotFound("La excusa")) : Result.Success();
    }

    public async Task<IReadOnlyList<ExcusaDocenteDto>> ExcusasDelDocenteAsync(DateOnly fecha, CancellationToken ct = default)
    {
        var yo = currentUser.RequireUserId();
        var institucionId = await db.Users.Where(u => u.Id == yo).Select(u => u.InstitucionId).FirstOrDefaultAsync(ct);
        if (institucionId is not { } centroId) return [];
        var anio = await db.AniosLectivos.Where(a => a.InstitucionId == centroId && a.Actual).Select(a => (Guid?)a.Id).FirstOrDefaultAsync(ct);
        if (anio is null) return [];

        var secciones = db.Secciones.Where(s => s.AnioLectivoId == anio
            && (s.MaestroGuiaId == yo || db.CargasDocentes.Any(c => c.SeccionId == s.Id && c.DocenteId == yo)))
            .Select(s => s.Id);
        return await (from e in db.Excusas.AsNoTracking()
                      join a in db.Alumnos.AsNoTracking() on e.AlumnoId equals a.Id
                      where e.InstitucionId == centroId && e.Desde <= fecha && e.Hasta >= fecha
                            && db.Matriculas.Any(m => m.AlumnoId == e.AlumnoId && m.Estado == EstadosMatricula.Activa && secciones.Contains(m.SeccionId))
                      orderby a.Nombre
                      select new ExcusaDocenteDto(a.Identidad, a.Nombre, e.Tipo, e.Desde, e.Hasta, e.Motivo))
            .ToListAsync(ct);
    }

    /// <summary>Motivo de la excusa de cada alumno que la tenga ese día.</summary>
    internal static async Task<Dictionary<Guid, string>> DelDiaAsync(AppDbContext db, IReadOnlyCollection<Guid> alumnos, DateOnly fecha, CancellationToken ct) =>
        (await db.Excusas.AsNoTracking()
            .Where(e => alumnos.Contains(e.AlumnoId) && e.Desde <= fecha && e.Hasta >= fecha)
            .Select(e => new { e.AlumnoId, e.Tipo, e.Motivo }).ToListAsync(ct))
        .GroupBy(e => e.AlumnoId)
        .ToDictionary(g => g.Key, g => string.Join("; ", g.Select(e => (e.Tipo == TiposExcusa.Permiso ? "Permiso: " : "Excusa: ") + e.Motivo)));

    /// <summary>Sección actual de cada alumno ("7.º A").</summary>
    private async Task<Dictionary<Guid, string>> SeccionesAsync(Guid institucionId, List<Guid> alumnos, CancellationToken ct) =>
        (await (from m in db.Matriculas.AsNoTracking()
                join s in db.Secciones.AsNoTracking() on m.SeccionId equals s.Id
                join g in db.Grados.AsNoTracking() on s.GradoId equals g.Id
                join a in db.AniosLectivos.AsNoTracking() on s.AnioLectivoId equals a.Id
                where a.InstitucionId == institucionId && a.Actual && alumnos.Contains(m.AlumnoId) && m.Estado == EstadosMatricula.Activa
                select new { m.AlumnoId, Nombre = g.Nombre + " " + s.Nombre })
            .ToListAsync(ct))
        .DistinctBy(x => x.AlumnoId).ToDictionary(x => x.AlumnoId, x => x.Nombre);

    private static ExcusaDto ADto(Excusa e, string alumno, string? seccion, string? autor) =>
        new(e.Id, e.AlumnoId, alumno, seccion, e.Tipo, e.Desde, e.Hasta, e.Motivo, autor, e.CreatedAt);
}
