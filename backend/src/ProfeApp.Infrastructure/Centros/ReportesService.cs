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
public sealed class ReportesService(AppDbContext db, EstructuraCentroService centro, ConsolidadoService consolidado, IClock clock)
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

        return new ReportesDto(anio.Anio, matricula, rendimiento, riesgo, asistencia);
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
