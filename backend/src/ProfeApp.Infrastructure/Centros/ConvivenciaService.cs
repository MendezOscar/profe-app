using Microsoft.EntityFrameworkCore;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;
using ProfeApp.Domain.Centros;
using ProfeApp.Infrastructure.Persistence;

namespace ProfeApp.Infrastructure.Centros;

/// <summary>Excusas y permisos que registra el centro y que ve quien pasa lista; incidencias disciplinarias.</summary>
public sealed class ConvivenciaService(
    AppDbContext db,
    EstructuraCentroService centro,
    ICurrentUser currentUser,
    IClock clock,
    IAvisosPush avisos) : IConvivenciaService
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
        var secciones = SeccionesDelDocente(centroId, yo);
        return await (from e in db.Excusas.AsNoTracking()
                      join a in db.Alumnos.AsNoTracking() on e.AlumnoId equals a.Id
                      where e.InstitucionId == centroId && e.Desde <= fecha && e.Hasta >= fecha
                            && db.Matriculas.Any(m => m.AlumnoId == e.AlumnoId && m.Estado == EstadosMatricula.Activa && secciones.Contains(m.SeccionId))
                      orderby a.Nombre
                      select new ExcusaDocenteDto(a.Identidad, a.Nombre, e.Tipo, e.Desde, e.Hasta, e.Motivo))
            .ToListAsync(ct);
    }

    // ── Incidencias ──────────────────────────────────────────────────────────

    private const int IncidenciasVisibles = 300;

    public async Task<Result<IReadOnlyList<IncidenciaDto>>> IncidenciasAsync(Guid? alumnoId, bool soloAbiertas, CancellationToken ct = default)
    {
        var (institucion, _) = await centro.ContextoAsync(ct);
        if (institucion is null) return Result<IReadOnlyList<IncidenciaDto>>.Fail(Error.Forbidden(EstructuraCentroService.SinCentro));
        var inicio = await InicioDelAnioAsync(institucion.Id, ct);
        return await ListarIncidenciasAsync(db.Incidencias.Where(i => i.InstitucionId == institucion.Id && i.Fecha >= inicio
            && (alumnoId == null || i.AlumnoId == alumnoId) && (!soloAbiertas || !i.Cerrada)), ct);
    }

    public async Task<Result<IncidenciaDto>> RegistrarIncidenciaAsync(IncidenciaRequest r, CancellationToken ct = default)
    {
        var (institucion, error) = await centro.EditorAsync(ct);
        if (institucion is null) return Result<IncidenciaDto>.Fail(error!);
        if (!await db.Alumnos.AnyAsync(a => a.Id == r.AlumnoId && a.InstitucionId == institucion.Id, ct))
            return Result<IncidenciaDto>.Fail(Error.NotFound("El alumno"));
        var seccion = await db.Matriculas.Where(m => m.AlumnoId == r.AlumnoId && m.Estado == EstadosMatricula.Activa)
            .Join(db.Secciones, m => m.SeccionId, s => s.Id, (m, s) => new { s.Id, s.AnioLectivoId })
            .Join(db.AniosLectivos.Where(a => a.Actual), x => x.AnioLectivoId, a => a.Id, (x, _) => (Guid?)x.Id)
            .FirstOrDefaultAsync(ct);
        return await GuardarIncidenciaAsync(institucion.Id, r.AlumnoId, seccion, r.Fecha, r.Gravedad, r.Descripcion, r.Medida, ct);
    }

    public async Task<Result<IncidenciaDto>> RegistrarIncidenciaDocenteAsync(IncidenciaDocenteRequest r, CancellationToken ct = default)
    {
        var yo = currentUser.RequireUserId();
        var institucionId = await db.Users.Where(u => u.Id == yo).Select(u => u.InstitucionId).FirstOrDefaultAsync(ct);
        if (institucionId is not { } centroId) return Result<IncidenciaDto>.Fail(Error.Forbidden("Tu cuenta no es de un centro."));
        if (!await SeccionesDelDocente(centroId, yo).AnyAsync(s => s == r.SeccionId, ct))
            return Result<IncidenciaDto>.Fail(Error.NotFound("La sección"));
        var identidad = MatriculaService.Normalizar(r.Identidad);
        var alumno = await (from m in db.Matriculas
                            join a in db.Alumnos on m.AlumnoId equals a.Id
                            where m.SeccionId == r.SeccionId && m.Estado == EstadosMatricula.Activa && a.Identidad == identidad
                            select (Guid?)a.Id).FirstOrDefaultAsync(ct);
        if (alumno is null) return Result<IncidenciaDto>.Fail(Error.Validation("Ese alumno no está matriculado en la sección."));
        return await GuardarIncidenciaAsync(centroId, alumno.Value, r.SeccionId, r.Fecha, r.Gravedad, r.Descripcion, r.Medida, ct);
    }

    public async Task<Result<IncidenciaDto>> SeguimientoAsync(Guid id, SeguimientoIncidenciaRequest r, CancellationToken ct = default)
    {
        var (institucion, error) = await centro.EditorAsync(ct);
        if (institucion is null) return Result<IncidenciaDto>.Fail(error!);
        var incidencia = await db.Incidencias.FirstOrDefaultAsync(i => i.Id == id && i.InstitucionId == institucion.Id, ct);
        if (incidencia is null) return Result<IncidenciaDto>.Fail(Error.NotFound("La incidencia"));
        var medida = Opcional(r.Medida);
        var seguimiento = Opcional(r.Seguimiento);
        if (medida?.Length > 500) return Result<IncidenciaDto>.Fail(Error.Validation("La medida va hasta 500 caracteres."));
        if (seguimiento?.Length > 1000) return Result<IncidenciaDto>.Fail(Error.Validation("El seguimiento va hasta 1000 caracteres."));
        incidencia.Medida = medida;
        incidencia.Seguimiento = seguimiento;
        incidencia.Cerrada = r.Cerrada;
        await db.SaveChangesAsync(ct);
        return (await ListarIncidenciasAsync(db.Incidencias.Where(i => i.Id == id), ct)).Single();
    }

    public async Task<Result> EliminarIncidenciaAsync(Guid id, CancellationToken ct = default)
    {
        var (institucion, error) = await centro.EditorAsync(ct);
        if (institucion is null) return Result.Fail(error!);
        var borradas = await db.Incidencias.Where(i => i.Id == id && i.InstitucionId == institucion.Id).ExecuteDeleteAsync(ct);
        return borradas == 0 ? Result.Fail(Error.NotFound("La incidencia")) : Result.Success();
    }

    public async Task<IReadOnlyList<IncidenciaDto>> IncidenciasDelDocenteAsync(CancellationToken ct = default)
    {
        var yo = currentUser.RequireUserId();
        var institucionId = await db.Users.Where(u => u.Id == yo).Select(u => u.InstitucionId).FirstOrDefaultAsync(ct);
        if (institucionId is not { } centroId) return [];
        var inicio = await InicioDelAnioAsync(centroId, ct);
        var lista = await ListarIncidenciasAsync(db.Incidencias.Where(i => i.InstitucionId == centroId && i.RegistradaPor == yo && i.Fecha >= inicio), ct);
        // El seguimiento es del centro.
        return lista.Select(i => i with { Seguimiento = null }).ToList();
    }

    private async Task<Result<IncidenciaDto>> GuardarIncidenciaAsync(
        Guid institucionId, Guid alumnoId, Guid? seccionId, DateOnly fecha, string? gravedad, string? descripcion, string? medida, CancellationToken ct)
    {
        var g = (gravedad ?? "").Trim().ToLowerInvariant();
        var texto = (descripcion ?? "").Trim();
        var tomada = Opcional(medida);
        if (!GravedadesIncidencia.Todas.Contains(g)) return Result<IncidenciaDto>.Fail(Error.Validation("Elige si la falta es leve, grave o muy grave."));
        if (texto.Length is 0 or > 1000) return Result<IncidenciaDto>.Fail(Error.Validation("Describe lo que pasó (hasta 1000 caracteres)."));
        if (tomada?.Length > 500) return Result<IncidenciaDto>.Fail(Error.Validation("La medida va hasta 500 caracteres."));
        if (fecha > clock.Today) return Result<IncidenciaDto>.Fail(Error.Validation("La fecha no puede ser futura."));
        if (fecha < clock.Today.AddDays(-60)) return Result<IncidenciaDto>.Fail(Error.Validation("Solo se registran incidencias de los últimos 60 días."));

        var incidencia = new Incidencia
        {
            InstitucionId = institucionId, AlumnoId = alumnoId, SeccionId = seccionId, Fecha = fecha,
            Gravedad = g, Descripcion = texto, Medida = tomada, RegistradaPor = currentUser.RequireUserId(),
        };
        db.Incidencias.Add(incidencia);
        await db.SaveChangesAsync(ct);

        var familias = await db.VinculosFamiliares.AsNoTracking().Where(v => v.AlumnoId == alumnoId).Select(v => v.UsuarioId).ToListAsync(ct);
        var dto = (await ListarIncidenciasAsync(db.Incidencias.Where(i => i.Id == incidencia.Id), ct)).Single();
        if (familias.Count > 0)
            avisos.Encolar(new AvisoPush(familias, $"Incidencia de {dto.Alumno}: falta {GravedadesIncidencia.Nombre(g)}",
                texto.Length > 140 ? texto[..137] + "…" : texto, "/familia"));
        return dto;
    }

    private async Task<List<IncidenciaDto>> ListarIncidenciasAsync(IQueryable<Incidencia> consulta, CancellationToken ct)
    {
        var filas = await (from i in consulta.AsNoTracking()
                           join a in db.Alumnos.AsNoTracking() on i.AlumnoId equals a.Id
                           join s in db.Secciones.AsNoTracking() on i.SeccionId equals s.Id into ss
                           from s in ss.DefaultIfEmpty()
                           join g in db.Grados.AsNoTracking() on s.GradoId equals g.Id into gg
                           from g in gg.DefaultIfEmpty()
                           join u in db.Users.AsNoTracking() on i.RegistradaPor equals u.Id into autores
                           from u in autores.DefaultIfEmpty()
                           orderby i.Fecha descending, i.CreatedAt descending
                           select new { i, Alumno = a.Nombre, Seccion = g == null ? null : g.Nombre + " " + s.Nombre, Autor = u == null ? null : u.FullName })
            .Take(IncidenciasVisibles).ToListAsync(ct);
        return filas.Select(f => new IncidenciaDto(f.i.Id, f.i.AlumnoId, f.Alumno, f.Seccion, f.i.Fecha, f.i.Gravedad, f.i.Descripcion,
            f.i.Medida, f.i.Seguimiento, f.i.Cerrada, f.Autor, f.i.CreatedAt)).ToList();
    }

    private async Task<DateOnly> InicioDelAnioAsync(Guid institucionId, CancellationToken ct) =>
        await db.AniosLectivos.Where(a => a.InstitucionId == institucionId && a.Actual).Select(a => (DateOnly?)a.Inicio).FirstOrDefaultAsync(ct)
        ?? clock.Today.AddDays(-365);

    /// <summary>Secciones del año actual donde el docente da clase o es guía.</summary>
    private IQueryable<Guid> SeccionesDelDocente(Guid institucionId, Guid docente) =>
        from s in db.Secciones
        join a in db.AniosLectivos on s.AnioLectivoId equals a.Id
        where a.InstitucionId == institucionId && a.Actual
              && (s.MaestroGuiaId == docente || db.CargasDocentes.Any(c => c.SeccionId == s.Id && c.DocenteId == docente))
        select s.Id;

    private static string? Opcional(string? texto) => string.IsNullOrWhiteSpace(texto) ? null : texto.Trim();

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
