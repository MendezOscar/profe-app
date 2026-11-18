using Microsoft.EntityFrameworkCore;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;
using ProfeApp.Domain.Centros;
using ProfeApp.Infrastructure.Persistence;

namespace ProfeApp.Infrastructure.Centros;

/// <summary>
/// Reportes del año actual. El rendimiento sale del consolidado de cada sección (lo que
/// cerraron los docentes) y la asistencia, de la lista del día del maestro guía.
/// </summary>
public sealed class ReportesService(
    AppDbContext db, EstructuraCentroService centro, ConsolidadoService consolidado, IConvivenciaService convivencia, IClock clock)
    : IReportesService
{
    /// <summary>Faltas de la lista del día que vuelven "en riesgo" a un alumno: al menos 3 y el 10 % de los días.</summary>
    private const int FaltasMinimas = 3;

    public async Task<Result<ReportesDto>> ResumenAsync(CancellationToken ct = default)
    {
        var (institucion, _) = await centro.ContextoAsync(ct);
        if (institucion is null) return Result<ReportesDto>.Fail(Error.Forbidden(EstructuraCentroService.SinCentro));
        var anio = await db.AniosLectivos.AsNoTracking().FirstOrDefaultAsync(a => a.InstitucionId == institucion.Id && a.Actual, ct);
        if (anio is null) return new ReportesDto(null, new MatriculaReporteDto(0, 0, 0, 0, 0, 0, [], []), [], [], []);

        var secciones = await (from s in db.Secciones.AsNoTracking()
                               join g in db.Grados.AsNoTracking() on s.GradoId equals g.Id
                               where s.AnioLectivoId == anio.Id
                               orderby g.Orden, s.Jornada, s.Nombre
                               select new { s.Id, Nombre = g.Nombre + " " + s.Nombre, s.Jornada, s.Cupo })
            .ToListAsync(ct);
        var matriculas = await (from m in db.Matriculas.AsNoTracking()
                                join a in db.Alumnos.AsNoTracking() on m.AlumnoId equals a.Id
                                where m.AnioLectivoId == anio.Id
                                select new { m.AlumnoId, a.Nombre, m.SeccionId, m.Tipo, m.Estado, a.Sexo, a.FechaNacimiento })
            .ToListAsync(ct);
        var activos = matriculas.Where(m => m.Estado == EstadosMatricula.Activa).ToList();

        // ── Matrícula ──
        var hoy = clock.Today;
        int? Edad(DateOnly? nac) => nac is { } n ? hoy.Year - n.Year - (hoy < n.AddYears(hoy.Year - n.Year) ? 1 : 0) : null;
        var matricula = new MatriculaReporteDto(
            activos.Count,
            matriculas.Count(m => m.Tipo == TiposMatricula.NuevoIngreso),
            matriculas.Count(m => m.Tipo == TiposMatricula.Reingreso),
            matriculas.Count(m => m.Tipo == TiposMatricula.TrasladoEntrante),
            matriculas.Count(m => m.Estado == EstadosMatricula.Retirada),
            matriculas.Count(m => m.Estado == EstadosMatricula.Trasladada),
            secciones.Select(s =>
            {
                var de = matriculas.Where(m => m.SeccionId == s.Id).ToList();
                var act = de.Where(m => m.Estado == EstadosMatricula.Activa).ToList();
                return new MatriculaSeccionDto(s.Id, s.Nombre, s.Jornada, act.Count, act.Count(m => m.Sexo == "F"), act.Count(m => m.Sexo == "M"),
                    act.Count(m => m.Sexo is null), s.Cupo, de.Count(m => m.Estado == EstadosMatricula.Retirada),
                    de.Count(m => m.Estado == EstadosMatricula.Trasladada));
            }).ToList(),
            activos.GroupBy(m => Edad(m.FechaNacimiento)).OrderBy(g => g.Key ?? int.MaxValue)
                .Select(g => new ConteoEdadDto(g.Key, g.Count())).ToList());

        // ── Rendimiento y riesgo académico ──
        var rendimiento = new List<RendimientoSeccionDto>();
        var motivos = new Dictionary<Guid, List<string>>();
        var seccionDe = activos.ToDictionary(m => m.AlumnoId, m => secciones.First(s => s.Id == m.SeccionId).Nombre);
        foreach (var s in secciones)
        {
            var c = await consolidado.DeSeccionAsync(institucion.Id, institucion.Nombre, s.Id, ct);
            if (c is null || c.Asignaturas.Count == 0) continue;
            var filas = c.Alumnos.Where(a => a.EstadoMatricula == EstadosMatricula.Activa).ToList();
            var asignaturas = c.Asignaturas.Select((asig, i) =>
            {
                var valores = filas.Select(f => (f.AlumnoId, Valor: Valor(f.Notas[i]))).Where(x => x.Valor is not null).ToList();
                foreach (var (alumno, valor) in valores.Where(x => x.Valor < ConsolidadoService.NotaMinima))
                    (motivos.TryGetValue(alumno, out var l) ? l : motivos[alumno] = []).Add($"{asig.Nombre}: {valor:0.#}");
                return new RendimientoAsignaturaDto(asig.Nombre, asig.Docente, valores.Count,
                    valores.Count(x => x.Valor >= ConsolidadoService.NotaMinima),
                    valores.Count == 0 ? null : Math.Round(valores.Average(x => x.Valor!.Value), 1));
            }).ToList();
            rendimiento.Add(new RendimientoSeccionDto(s.Id, s.Nombre, asignaturas));
        }

        // ── Asistencia (lista del día) y riesgo por faltas ──
        var ids = secciones.Select(s => s.Id).ToList();
        var dias = await db.TomasAsistenciaDiaria.Where(t => ids.Contains(t.SeccionId))
            .GroupBy(t => t.SeccionId).Select(g => new { g.Key, N = g.Count() }).ToDictionaryAsync(x => x.Key, x => x.N, ct);
        var marcas = await (from m in db.MarcasAsistenciaDiaria.AsNoTracking()
                            join t in db.TomasAsistenciaDiaria.AsNoTracking() on m.TomaId equals t.Id
                            where ids.Contains(t.SeccionId)
                            select new { t.SeccionId, m.AlumnoId, m.Estado })
            .ToListAsync(ct);
        var asistencia = secciones.Select(s =>
        {
            var d = dias.GetValueOrDefault(s.Id);
            var de = marcas.Where(m => m.SeccionId == s.Id).ToList();
            var posibles = d * activos.Count(m => m.SeccionId == s.Id);
            var ausentes = de.Count(m => m.Estado is "A" or "J");
            return new AsistenciaSeccionDto(s.Id, s.Nombre, d, de.Count(m => m.Estado == "A"), de.Count(m => m.Estado == "T"),
                de.Count(m => m.Estado == "J"), posibles == 0 ? null : Math.Round(100m * (posibles - ausentes) / posibles, 1));
        }).ToList();
        foreach (var g in marcas.Where(m => m.Estado == "A").GroupBy(m => (m.AlumnoId, m.SeccionId)))
        {
            var total = dias.GetValueOrDefault(g.Key.SeccionId);
            if (g.Count() >= FaltasMinimas && g.Count() * 10 >= total && seccionDe.ContainsKey(g.Key.AlumnoId))
                (motivos.TryGetValue(g.Key.AlumnoId, out var l) ? l : motivos[g.Key.AlumnoId] = []).Add($"{g.Count()} ausencias de {total} días");
        }

        var nombres = activos.ToDictionary(m => m.AlumnoId, m => m.Nombre);
        var riesgo = motivos.Where(m => nombres.ContainsKey(m.Key))
            .Select(m => new AlumnoRiesgoDto(m.Key, nombres[m.Key], seccionDe[m.Key], m.Value))
            .OrderByDescending(r => r.Motivos.Count).ThenBy(r => r.Seccion).ThenBy(r => r.Nombre).ToList();

        // ── Convivencia ──
        var incidencias = await db.Incidencias.AsNoTracking().Where(i => i.InstitucionId == institucion.Id && i.Fecha >= anio.Inicio)
            .Select(i => new { i.SeccionId, i.Gravedad, i.Cerrada }).ToListAsync(ct);
        var excusas = await db.Excusas.CountAsync(e => e.InstitucionId == institucion.Id && e.Hasta >= anio.Inicio, ct);
        var convivencia = new ConvivenciaReporteDto(
            incidencias.Count(i => i.Gravedad == "leve"), incidencias.Count(i => i.Gravedad == "grave"),
            incidencias.Count(i => i.Gravedad == "muy_grave"), incidencias.Count(i => !i.Cerrada), excusas,
            secciones.Select(sec => (sec.Nombre, De: incidencias.Where(i => i.SeccionId == sec.Id).ToList()))
                .Where(x => x.De.Count > 0)
                .Select(x => new ConvivenciaSeccionDto(x.Nombre, x.De.Count(i => i.Gravedad == "leve"),
                    x.De.Count(i => i.Gravedad == "grave"), x.De.Count(i => i.Gravedad == "muy_grave")))
                .ToList());

        return new ReportesDto(anio.Anio, matricula, rendimiento, riesgo, asistencia, convivencia);
    }

    public async Task<Result<EstadisticasDocentesDto>> DocentesAsync(CancellationToken ct = default)
    {
        var (institucion, _) = await centro.ContextoAsync(ct);
        if (institucion is null) return Result<EstadisticasDocentesDto>.Fail(Error.Forbidden(EstructuraCentroService.SinCentro));
        var anio = await db.AniosLectivos.AsNoTracking().FirstOrDefaultAsync(a => a.InstitucionId == institucion.Id && a.Actual, ct);

        var docentes = await (from u in db.Users.AsNoTracking()
                              join ur in db.UserRoles on u.Id equals ur.UserId
                              join r in db.Roles on ur.RoleId equals r.Id
                              where r.Name == Domain.Common.Roles.Docente && u.InstitucionId == institucion.Id
                              orderby u.FullName
                              select new { u.Id, u.FullName, u.IsActive, u.LastLoginAt, u.TenantId })
            .ToListAsync(ct);
        var tenants = docentes.Where(d => d.TenantId is not null).Select(d => d.TenantId!.Value).ToList();
        var ids = docentes.Select(d => d.Id).ToList();

        // Lo del teléfono de cada docente (está en su tenant): se cuenta sin abrir notas.
        var cuadros = await db.Clases.IgnoreQueryFilters().Where(c => tenants.Contains(c.TenantId) && c.EliminadaEn == null)
            .GroupBy(c => c.TenantId).Select(g => new { g.Key, N = g.Count() }).ToDictionaryAsync(x => x.Key, x => x.N, ct);
        var actividades = await db.Registros.IgnoreQueryFilters()
            .Where(r => tenants.Contains(r.TenantId) && r.Tipo == "actividad" && !r.Eliminado)
            .GroupBy(r => r.TenantId).Select(g => new { g.Key, N = g.Count() }).ToDictionaryAsync(x => x.Key, x => x.N, ct);
        var hace30 = clock.Now.AddDays(-30);
        var listas = await db.Registros.IgnoreQueryFilters()
            .Where(r => tenants.Contains(r.TenantId) && r.Tipo == "sesion" && !r.Eliminado && r.ActualizadoEn >= hace30)
            .GroupBy(r => r.TenantId).Select(g => new { g.Key, N = g.Count() }).ToDictionaryAsync(x => x.Key, x => x.N, ct);
        var parciales = (await db.Database
                .SqlQuery<ConteoTenant>($@"SELECT tenant_id AS ""TenantId"", count(*)::int AS ""N"" FROM registros
                    WHERE tipo = 'parcial' AND tenant_id = ANY({tenants.ToArray()}) AND datos->>'cerradoEn' IS NOT NULL
                    GROUP BY tenant_id")
                .ToListAsync(ct))
            .ToDictionary(x => x.TenantId, x => x.N);
        var ultimoTrabajo = await db.Registros.IgnoreQueryFilters().Where(r => tenants.Contains(r.TenantId))
            .GroupBy(r => r.TenantId).Select(g => new { g.Key, Cuando = g.Max(r => r.ModificadoEn) })
            .ToDictionaryAsync(x => x.Key, x => x.Cuando, ct);
        var conductas = await db.Conductas.Where(c => c.InstitucionId == institucion.Id && ids.Contains(c.PuestaPor))
            .GroupBy(c => c.PuestaPor).Select(g => new { g.Key, N = g.Count() }).ToDictionaryAsync(x => x.Key, x => x.N, ct);
        var inicio = anio?.Inicio ?? clock.Today.AddDays(-365);
        var incidencias = await db.Incidencias.Where(i => i.InstitucionId == institucion.Id && ids.Contains(i.RegistradaPor) && i.Fecha >= inicio)
            .GroupBy(i => i.RegistradaPor).Select(g => new { g.Key, N = g.Count() }).ToDictionaryAsync(x => x.Key, x => x.N, ct);

        // Carga, guías y lista del día del año actual.
        var carga = anio is null ? [] : await (from c in db.CargasDocentes.AsNoTracking()
                                               join s in db.Secciones.AsNoTracking() on c.SeccionId equals s.Id
                                               where s.AnioLectivoId == anio.Id
                                               select new { c.DocenteId, c.SeccionId }).ToListAsync(ct);
        var guias = anio is null ? [] : await db.Secciones.AsNoTracking()
            .Where(s => s.AnioLectivoId == anio.Id && s.MaestroGuiaId != null)
            .Select(s => new { Docente = s.MaestroGuiaId!.Value, s.Id }).ToListAsync(ct);
        var seccionesAnio = carga.Select(c => c.SeccionId).Concat(guias.Select(g => g.Id)).Distinct().ToList();
        var activos = await db.Matriculas.Where(m => seccionesAnio.Contains(m.SeccionId) && m.Estado == EstadosMatricula.Activa)
            .GroupBy(m => m.SeccionId).Select(g => new { g.Key, N = g.Count() }).ToDictionaryAsync(x => x.Key, x => x.N, ct);
        var tomas = await db.TomasAsistenciaDiaria.Where(t => seccionesAnio.Contains(t.SeccionId))
            .GroupBy(t => t.SeccionId).Select(g => new { g.Key, N = g.Count() }).ToDictionaryAsync(x => x.Key, x => x.N, ct);

        // Rendimiento: lo cerrado en las asignaturas de cada docente, por el consolidado de cada sección.
        var claseDeTenant = await db.Clases.IgnoreQueryFilters().Where(c => tenants.Contains(c.TenantId))
            .Select(c => new { c.Id, c.TenantId }).ToDictionaryAsync(c => c.Id, c => c.TenantId, ct);
        var notas = new Dictionary<Guid, List<decimal>>();
        // Todas las secciones del año: el docente puede tener el cuadro sin que le hayan asignado la carga.
        var todas = anio is null ? [] : await db.Secciones.Where(s => s.AnioLectivoId == anio.Id).Select(s => s.Id).ToListAsync(ct);
        foreach (var seccion in todas)
        {
            var c = await consolidado.DeSeccionAsync(institucion.Id, institucion.Nombre, seccion, ct);
            if (c is null) continue;
            var filas = c.Alumnos.Where(a => a.EstadoMatricula == EstadosMatricula.Activa).ToList();
            for (var i = 0; i < c.Asignaturas.Count; i++)
            {
                if (!claseDeTenant.TryGetValue(c.Asignaturas[i].ClaseId, out var tenant)) continue;
                var lista = notas.TryGetValue(tenant, out var l) ? l : notas[tenant] = [];
                lista.AddRange(filas.Select(f => Valor(f.Notas[i])).Where(v => v is not null).Select(v => v!.Value));
            }
        }

        var hoy = clock.Today;
        var fin = anio is null ? hoy : (hoy < anio.Fin ? hoy : anio.Fin);
        var habiles = anio is null ? 0 : DiasHabiles(anio.Inicio, fin);
        int De<TK>(Dictionary<TK, int> d, TK? k) where TK : struct => k is { } v && d.TryGetValue(v, out var n) ? n : 0;

        return new EstadisticasDocentesDto(anio?.Anio, habiles, docentes.Select(d =>
        {
            var suyas = carga.Where(c => c.DocenteId == d.Id).ToList();
            var guiadas = guias.Where(g => g.Docente == d.Id).Select(g => g.Id).ToList();
            var secciones = suyas.Select(c => c.SeccionId).Concat(guiadas).Distinct().ToList();
            var valores = d.TenantId is { } t && notas.TryGetValue(t, out var v) ? v : [];
            return new EstadisticaDocenteDto(d.Id, d.FullName, d.IsActive, d.LastLoginAt,
                d.TenantId is { } t2 && ultimoTrabajo.TryGetValue(t2, out var u) ? u : null,
                secciones.Count, suyas.Count, secciones.Sum(s => activos.GetValueOrDefault(s)),
                De(cuadros, d.TenantId), De(parciales, d.TenantId), De(actividades, d.TenantId), De(listas, d.TenantId),
                guiadas.Count, guiadas.Count == 0 ? null : guiadas.Sum(g => tomas.GetValueOrDefault(g)),
                conductas.GetValueOrDefault(d.Id), incidencias.GetValueOrDefault(d.Id),
                valores.Count, valores.Count(x => x >= ConsolidadoService.NotaMinima),
                valores.Count == 0 ? null : Math.Round(valores.Average(), 1));
        }).ToList());
    }

    private const int DiasSinActividad = 14;
    private const int DiasTendencia = 15;

    public async Task<Result<TableroDto>> TableroAsync(CancellationToken ct = default)
    {
        var (institucion, _) = await centro.ContextoAsync(ct);
        if (institucion is null) return Result<TableroDto>.Fail(Error.Forbidden(EstructuraCentroService.SinCentro));
        var hoy = clock.Today;
        var anio = await db.AniosLectivos.AsNoTracking().FirstOrDefaultAsync(a => a.InstitucionId == institucion.Id && a.Actual, ct);

        var docentes = await (from u in db.Users.AsNoTracking()
                              join ur in db.UserRoles on u.Id equals ur.UserId
                              join r in db.Roles on ur.RoleId equals r.Id
                              where r.Name == Domain.Common.Roles.Docente && u.InstitucionId == institucion.Id && u.IsActive
                              select new { u.Id, u.FullName, u.TenantId })
            .ToListAsync(ct);
        var tenants = docentes.Where(d => d.TenantId is not null).Select(d => d.TenantId!.Value).ToList();
        var ultimo = await db.Registros.IgnoreQueryFilters().Where(r => tenants.Contains(r.TenantId))
            .GroupBy(r => r.TenantId).Select(g => new { g.Key, Cuando = g.Max(r => r.ModificadoEn) })
            .ToDictionaryAsync(x => x.Key, x => x.Cuando, ct);
        var limite = clock.Now.AddDays(-DiasSinActividad);
        var inactivos = docentes
            .Select(d => new DocenteInactivoDto(d.Id, d.FullName, d.TenantId is { } t && ultimo.TryGetValue(t, out var c) ? c : null))
            .Where(d => d.UltimoTrabajo is null || d.UltimoTrabajo < limite)
            .OrderBy(d => d.UltimoTrabajo ?? DateTimeOffset.MinValue).ToList();
        var comunicadosMes = await db.Comunicados.CountAsync(c => c.InstitucionId == institucion.Id && c.PublicadoEn >= clock.Now.AddDays(-30), ct);
        var abiertas = await db.Incidencias.CountAsync(i => i.InstitucionId == institucion.Id && !i.Cerrada, ct);
        var recientes = ((await convivencia.IncidenciasAsync(null, false, ct)).Value ?? []).Take(5).ToList();

        if (anio is null)
            return new TableroDto(null, 0, 0, 0, 0, docentes.Count, institucion.MaxDocentes, 0,
                new HoyDto(hoy, 0, 0, 0, 0, [], 0), [], abiertas, recientes, inactivos, comunicadosMes);

        var secciones = await (from s in db.Secciones.AsNoTracking()
                               join g in db.Grados.AsNoTracking() on s.GradoId equals g.Id
                               where s.AnioLectivoId == anio.Id
                               select new { s.Id, Nombre = g.Nombre + " " + s.Nombre, s.MaestroGuiaId })
            .ToListAsync(ct);
        var ids = secciones.Select(s => s.Id).ToList();
        var activos = await db.Matriculas.Where(m => m.AnioLectivoId == anio.Id && m.Estado == EstadosMatricula.Activa)
            .GroupBy(m => m.SeccionId).Select(g => new { g.Key, N = g.Count() }).ToDictionaryAsync(x => x.Key, x => x.N, ct);
        var alumnosActivos = await db.Matriculas.Where(m => m.AnioLectivoId == anio.Id && m.Estado == EstadosMatricula.Activa)
            .Select(m => m.AlumnoId).ToListAsync(ct);
        var familias = await db.VinculosFamiliares.Where(v => alumnosActivos.Contains(v.AlumnoId)).Select(v => v.AlumnoId).Distinct().CountAsync(ct);

        // Hoy.
        var tomasHoy = await db.TomasAsistenciaDiaria.Where(t => ids.Contains(t.SeccionId) && t.Fecha == hoy).Select(t => t.Id).ToListAsync(ct);
        var faltas = await (from m in db.MarcasAsistenciaDiaria.AsNoTracking()
                            join t in db.TomasAsistenciaDiaria.AsNoTracking() on m.TomaId equals t.Id
                            join a in db.Alumnos.AsNoTracking() on m.AlumnoId equals a.Id
                            where tomasHoy.Contains(t.Id) && m.Estado != "J"
                            orderby a.Nombre
                            select new { a.Id, a.Nombre, t.SeccionId, m.Estado })
            .ToListAsync(ct);
        var nombreSeccion = secciones.ToDictionary(s => s.Id, s => s.Nombre);
        var excusas = await db.Excusas.CountAsync(e => e.InstitucionId == institucion.Id && e.Desde <= hoy && e.Hasta >= hoy, ct);
        var hoyDto = new HoyDto(hoy, secciones.Count(s => s.MaestroGuiaId != null), tomasHoy.Count,
            faltas.Count(f => f.Estado == "A"), faltas.Count(f => f.Estado == "T"),
            faltas.Select(f => new FaltaHoyDto(f.Id, f.Nombre, nombreSeccion[f.SeccionId], f.Estado)).ToList(), excusas);

        // Tendencia: últimos días con lista.
        var desde = hoy.AddDays(-30);
        var tomas = await db.TomasAsistenciaDiaria.AsNoTracking().Where(t => ids.Contains(t.SeccionId) && t.Fecha >= desde && t.Fecha <= hoy)
            .Select(t => new { t.Id, t.Fecha, t.SeccionId }).ToListAsync(ct);
        var tomaIds = tomas.Select(t => t.Id).ToList();
        var ausentes = await db.MarcasAsistenciaDiaria.Where(m => tomaIds.Contains(m.TomaId) && (m.Estado == "A" || m.Estado == "J"))
            .GroupBy(m => m.TomaId).Select(g => new { g.Key, N = g.Count() }).ToDictionaryAsync(x => x.Key, x => x.N, ct);
        var tendencia = tomas.GroupBy(t => t.Fecha).OrderByDescending(g => g.Key).Take(DiasTendencia).OrderBy(g => g.Key)
            .Select(g =>
            {
                var posibles = g.Sum(t => activos.GetValueOrDefault(t.SeccionId));
                var fuera = g.Sum(t => ausentes.GetValueOrDefault(t.Id));
                return new DiaAsistenciaDto(g.Key, g.Count(), posibles == 0 ? 100 : Math.Round(100m * (posibles - fuera) / posibles, 1));
            }).ToList();

        var fin = hoy < anio.Fin ? hoy : anio.Fin;
        return new TableroDto(anio.Anio, hoy < anio.Inicio ? 0 : DiasHabiles(anio.Inicio, fin), DiasHabiles(anio.Inicio, anio.Fin),
            alumnosActivos.Count, secciones.Count, docentes.Count, institucion.MaxDocentes, familias,
            hoyDto, tendencia, abiertas, recientes, inactivos, comunicadosMes);
    }

    private sealed record ConteoTenant(Guid TenantId, int N);

    private static int DiasHabiles(DateOnly desde, DateOnly hasta)
    {
        var n = 0;
        for (var d = desde; d <= hasta; d = d.AddDays(1))
            if (d.DayOfWeek is not (DayOfWeek.Saturday or DayOfWeek.Sunday)) n++;
        return n;
    }

    /// <summary>La final si ya está; si no, el promedio de los parciales cerrados.</summary>
    private static decimal? Valor(NotaAsignaturaDto? n)
    {
        if (n is null) return null;
        if (n.Recuperacion is { } r && n.Final < ConsolidadoService.NotaMinima) return r;
        if (n.Final is { } f) return f;
        var cerrados = n.Parciales.Where(p => p is not null).Select(p => (decimal)p!.Value).ToList();
        return cerrados.Count == 0 ? null : Math.Round(cerrados.Average(), 1);
    }
}
