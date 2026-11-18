using System.Globalization;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;
using ProfeApp.Domain.Centros;
using ProfeApp.Domain.Common;
using ProfeApp.Infrastructure.Persistence;

namespace ProfeApp.Infrastructure.Centros;

/// <summary>
/// Lo que ve un padre de cada hijo vinculado. Las notas y la asistencia salen del respaldo
/// de los docentes del centro: se buscan las clases cuya lista de SACE trae la identidad
/// del alumno y se leen sólo sus registros (actividades, notas y asistencia del hijo).
/// </summary>
public sealed class PadresService(AppDbContext db, ICurrentUser currentUser, IClock clock, HorarioService horario) : IPadresService
{
    private const int FaltasRecientes = 10;
    private const int ComunicadosVisibles = 50;

    public async Task<Result<HijoDto>> VincularAsync(CodigoRequest r, CancellationToken ct = default)
    {
        var yo = currentUser.RequireUserId();
        var codigo = CodigosFamilia.Normalizar(r.Codigo);
        var vigente = await db.CodigosFamilia.AsNoTracking().FirstOrDefaultAsync(c => c.Codigo == codigo && c.ExpiraEn > clock.Now, ct);
        if (vigente is null || !await db.Instituciones.AnyAsync(i => i.Id == vigente.InstitucionId && i.Activa, ct))
            return Result<HijoDto>.Fail(Error.Validation("El código no es válido o ya venció. Pide uno nuevo en el centro.", "codigo_invalido"));
        if (!await db.VinculosFamiliares.AnyAsync(v => v.AlumnoId == vigente.AlumnoId && v.UsuarioId == yo, ct))
        {
            if (await db.VinculosFamiliares.CountAsync(v => v.AlumnoId == vigente.AlumnoId, ct) >= CodigosFamilia.MaxCuentasPorAlumno)
                return Result<HijoDto>.Fail(Error.Conflict("Este alumno ya tiene el máximo de cuentas de familia. Habla con el centro."));
            db.VinculosFamiliares.Add(new VinculoFamiliar { InstitucionId = vigente.InstitucionId, AlumnoId = vigente.AlumnoId, UsuarioId = yo });
            await db.SaveChangesAsync(ct);
        }
        return (await HijosAsync(ct)).First(h => h.AlumnoId == vigente.AlumnoId);
    }

    public async Task<IReadOnlyList<HijoDto>> HijosAsync(CancellationToken ct = default)
    {
        var yo = currentUser.RequireUserId();
        var hijos = await (from v in db.VinculosFamiliares.AsNoTracking()
                           join a in db.Alumnos.AsNoTracking() on v.AlumnoId equals a.Id
                           join i in db.Instituciones.AsNoTracking() on a.InstitucionId equals i.Id
                           where v.UsuarioId == yo && i.Activa
                           orderby a.Nombre
                           select new { a.Id, a.Nombre, Centro = i.Nombre, a.InstitucionId })
            .ToListAsync(ct);
        var secciones = await SeccionesActualesAsync(hijos.Select(h => h.Id).ToList(), ct);
        return hijos.Select(h => new HijoDto(h.Id, h.Nombre, h.Centro, secciones.GetValueOrDefault(h.Id).Nombre)).ToList();
    }

    public async Task<Result<ResumenHijoDto>> ResumenAsync(Guid alumnoId, CancellationToken ct = default)
    {
        var hijo = (await HijosAsync(ct)).FirstOrDefault(h => h.AlumnoId == alumnoId);
        if (hijo is null) return Result<ResumenHijoDto>.Fail(Error.NotFound("El alumno"));
        var alumno = await db.Alumnos.AsNoTracking().FirstAsync(a => a.Id == alumnoId, ct);

        // Docentes del centro y sus clases cuya lista trae a este alumno.
        var docentes = await (from u in db.Users.AsNoTracking()
                              join ur in db.UserRoles on u.Id equals ur.UserId
                              join r in db.Roles on ur.RoleId equals r.Id
                              where r.Name == Roles.Docente && u.InstitucionId == alumno.InstitucionId && u.TenantId != null
                              select new { Tenant = u.TenantId!.Value, u.FullName })
            .ToListAsync(ct);
        var tenants = docentes.Select(d => d.Tenant).ToList();
        var identidad = alumno.Identidad;
        var enClases = await db.ClaseAlumnos.IgnoreQueryFilters().AsNoTracking()
            .Where(ca => tenants.Contains(ca.TenantId) && ca.Activo
                         && ca.Identidad.Replace("-", "").Replace(" ", "").ToUpper() == identidad)
            .Select(ca => new { ca.ClaseId, ca.TenantId, ca.Clave })
            .ToListAsync(ct);
        var claseIds = enClases.Select(c => c.ClaseId).ToList();
        var clases = await db.Clases.IgnoreQueryFilters().AsNoTracking()
            .Where(c => claseIds.Contains(c.Id) && c.EliminadaEn == null)
            .Select(c => new { c.Id, c.TenantId, c.Clave, c.Asignatura })
            .ToListAsync(ct);

        var nombreDocente = docentes.ToDictionary(d => d.Tenant, d => d.FullName);
        var asignaturas = new List<AsignaturaHijoDto>();
        var proximas = new List<EntregaDto>();
        var faltas = new List<FaltaDto>();
        int sesionesTotal = 0, ausencias = 0, tardes = 0, justificadas = 0;
        var hoy = clock.Today;

        foreach (var clase in clases.OrderBy(c => c.Asignatura))
        {
            var alumnoClave = enClases.First(e => e.ClaseId == clase.Id).Clave;
            var sufijo = "|" + alumnoClave;
            var registros = await db.Registros.IgnoreQueryFilters().AsNoTracking()
                .Where(r => r.TenantId == clase.TenantId && r.ClaseClave == clase.Clave && !r.Eliminado
                            && (r.Tipo == "actividad" || r.Tipo == "sesion" || r.Tipo == "parcial"
                                || ((r.Tipo == "calificacion" || r.Tipo == "asistencia") && r.Clave.EndsWith(sufijo))))
                .Select(r => new { r.Tipo, r.Clave, r.Datos })
                .ToListAsync(ct);
            var nombre = clase.Asignatura ?? "Asignatura";

            var notas = registros.Where(r => r.Tipo == "calificacion")
                .ToDictionary(r => r.Clave[..^sufijo.Length], r => Numero(Leer(r.Datos), "valor"));
            var cerrados = registros.Where(r => r.Tipo == "parcial" && Texto(Leer(r.Datos), "cerradoEn") is not null)
                .Select(r => r.Clave).ToHashSet();
            var actividades = registros.Where(r => r.Tipo == "actividad")
                .Select(r => (Id: r.Clave, Datos: Leer(r.Datos)))
                .Select(a => new
                {
                    Parcial = Texto(a.Datos, "parcial") ?? "",
                    Titulo = Texto(a.Datos, "titulo") ?? "Actividad",
                    Fecha = Fecha(Texto(a.Datos, "fecha")),
                    Puntos = Numero(a.Datos, "puntos") ?? 0,
                    Nota = notas.GetValueOrDefault(a.Id),
                })
                .ToList();

            var parciales = actividades.GroupBy(a => a.Parcial).OrderBy(g => g.Key)
                .Select(g => new ParcialHijoDto(
                    g.Key,
                    cerrados.Contains(g.Key),
                    g.Where(a => a.Nota is not null).Sum(a => a.Nota!.Value),
                    g.Where(a => a.Nota is not null).Sum(a => a.Puntos),
                    g.OrderBy(a => a.Fecha ?? DateOnly.MaxValue).ThenBy(a => a.Titulo)
                        .Select(a => new ActividadHijoDto(a.Titulo, a.Fecha, a.Puntos, a.Nota)).ToList()))
                .ToList();
            asignaturas.Add(new AsignaturaHijoDto(nombre, nombreDocente.GetValueOrDefault(clase.TenantId) ?? "", parciales));
            proximas.AddRange(actividades
                .Where(a => a.Fecha is { } f && f >= hoy && f <= hoy.AddDays(14) && a.Nota is null)
                .Select(a => new EntregaDto(nombre, a.Titulo, a.Fecha!.Value, a.Puntos)));

            // Asistencia: sólo se guardan las faltas; sin marca es presente.
            var sesiones = registros.Where(r => r.Tipo == "sesion")
                .ToDictionary(r => r.Clave, r => Fecha(Texto(Leer(r.Datos), "fecha")));
            sesionesTotal += sesiones.Count;
            foreach (var marca in registros.Where(r => r.Tipo == "asistencia"))
            {
                var sesion = marca.Clave[..^sufijo.Length];
                if (!sesiones.TryGetValue(sesion, out var fecha)) continue;
                var estado = Texto(Leer(marca.Datos), "estado") switch
                {
                    "A" => "ausente",
                    "T" => "tarde",
                    "J" => "justificada",
                    _ => null,
                };
                if (estado is null) continue;
                if (estado == "ausente") ausencias++;
                else if (estado == "tarde") tardes++;
                else justificadas++;
                if (fecha is { } f) faltas.Add(new FaltaDto(f, nombre, estado));
            }
        }

        // Lista del día del maestro guía y horario de su sección, en el año actual.
        var actual = await (from m in db.Matriculas.AsNoTracking()
                            join an in db.AniosLectivos.AsNoTracking() on m.AnioLectivoId equals an.Id
                            where m.AlumnoId == alumnoId && an.Actual && m.Estado == EstadosMatricula.Activa
                            select new { m.SeccionId, m.AnioLectivoId }).FirstOrDefaultAsync(ct);
        AsistenciaHijoDto? diaria = null;
        IReadOnlyList<ClaseHorarioDto>? horarioSeccion = null;
        IReadOnlyList<string?>? conducta = null;
        if (actual is not null)
        {
            var dias = await db.TomasAsistenciaDiaria.CountAsync(t => t.SeccionId == actual.SeccionId, ct);
            var marcas = await (from m in db.MarcasAsistenciaDiaria.AsNoTracking()
                                join t in db.TomasAsistenciaDiaria.AsNoTracking() on m.TomaId equals t.Id
                                where m.AlumnoId == alumnoId && t.SeccionId == actual.SeccionId
                                orderby t.Fecha descending
                                select new { t.Fecha, m.Estado })
                .ToListAsync(ct);
            string Nombre(string e) => e switch { "A" => "ausente", "T" => "tarde", _ => "justificada" };
            diaria = new AsistenciaHijoDto(dias, marcas.Count(m => m.Estado == "A"), marcas.Count(m => m.Estado == "T"),
                marcas.Count(m => m.Estado == "J"),
                marcas.Take(FaltasRecientes).Select(m => new FaltaDto(m.Fecha, "Lista del día", Nombre(m.Estado))).ToList());
            horarioSeccion = await horario.DeSeccionAsync(actual.AnioLectivoId, actual.SeccionId, ct);
            var letras = await db.Conductas.AsNoTracking().Where(c => c.SeccionId == actual.SeccionId && c.AlumnoId == alumnoId)
                .ToDictionaryAsync(c => c.Parcial, c => c.Nota, ct);
            conducta = Enumerable.Range(1, 4).Select(p => letras.GetValueOrDefault(p)).ToList();
        }

        return new ResumenHijoDto(
            hijo.AlumnoId, hijo.Nombre, hijo.Centro, hijo.Seccion, asignaturas,
            new AsistenciaHijoDto(sesionesTotal, ausencias, tardes, justificadas,
                faltas.OrderByDescending(f => f.Fecha).Take(FaltasRecientes).ToList()),
            proximas.OrderBy(p => p.Fecha).ToList(), diaria, horarioSeccion, conducta);
    }

    public async Task<IReadOnlyList<ComunicadoPadreDto>> ComunicadosAsync(CancellationToken ct = default)
    {
        var yo = currentUser.RequireUserId();
        var hijos = await db.VinculosFamiliares.AsNoTracking().Where(v => v.UsuarioId == yo)
            .Select(v => new { v.AlumnoId, v.InstitucionId }).ToListAsync(ct);
        var secciones = await SeccionesActualesAsync(hijos.Select(h => h.AlumnoId).ToList(), ct);
        var centros = hijos.Where(h => secciones.ContainsKey(h.AlumnoId)).Select(h => h.InstitucionId).Distinct().ToList();
        if (centros.Count == 0) return [];
        var mias = secciones.Values.Select(s => s.Id).ToList();

        var candidatos = await (from c in db.Comunicados.AsNoTracking()
                                join i in db.Instituciones.AsNoTracking() on c.InstitucionId equals i.Id
                                where centros.Contains(c.InstitucionId) && i.Activa
                                orderby c.PublicadoEn descending
                                select new { c, Centro = i.Nombre })
            .Take(ComunicadosVisibles * 4).ToListAsync(ct);
        var visibles = candidatos.Where(x => x.c.SeccionIds.Count == 0 || x.c.SeccionIds.Any(mias.Contains)).Take(ComunicadosVisibles).ToList();
        var ids = visibles.Select(x => x.c.Id).ToList();
        var leidos = (await db.LecturasComunicados.Where(l => l.UsuarioId == yo && ids.Contains(l.ComunicadoId))
            .Select(l => l.ComunicadoId).ToListAsync(ct)).ToHashSet();
        return visibles.Select(x => new ComunicadoPadreDto(x.c.Id, x.Centro, x.c.Titulo, x.c.Cuerpo, x.c.PublicadoEn, leidos.Contains(x.c.Id))).ToList();
    }

    public async Task<Result> MarcarLeidoAsync(Guid comunicadoId, CancellationToken ct = default)
    {
        var yo = currentUser.RequireUserId();
        if (!(await ComunicadosAsync(ct)).Any(c => c.Id == comunicadoId)) return Result.Fail(Error.NotFound("El comunicado"));
        if (!await db.LecturasComunicados.AnyAsync(l => l.ComunicadoId == comunicadoId && l.UsuarioId == yo, ct))
        {
            db.LecturasComunicados.Add(new LecturaComunicado { ComunicadoId = comunicadoId, UsuarioId = yo, LeidoEn = clock.Now });
            await db.SaveChangesAsync(ct);
        }
        return Result.Success();
    }

    /// <summary>Sección (id y nombre) de cada alumno con matrícula activa en el año actual de su centro.</summary>
    private async Task<Dictionary<Guid, (Guid Id, string Nombre)>> SeccionesActualesAsync(List<Guid> alumnos, CancellationToken ct) =>
        (await (from m in db.Matriculas.AsNoTracking()
                join an in db.AniosLectivos.AsNoTracking() on m.AnioLectivoId equals an.Id
                join s in db.Secciones.AsNoTracking() on m.SeccionId equals s.Id
                join g in db.Grados.AsNoTracking() on s.GradoId equals g.Id
                where alumnos.Contains(m.AlumnoId) && an.Actual && m.Estado == EstadosMatricula.Activa
                select new { m.AlumnoId, s.Id, Nombre = g.Nombre + " " + s.Nombre })
            .ToListAsync(ct))
        .ToDictionary(x => x.AlumnoId, x => (x.Id, x.Nombre));

    private static JsonElement Leer(string? datos)
    {
        if (string.IsNullOrEmpty(datos)) return default;
        try { return JsonDocument.Parse(datos).RootElement; }
        catch (JsonException) { return default; }
    }

    private static string? Texto(JsonElement e, string campo) =>
        e.ValueKind == JsonValueKind.Object && e.TryGetProperty(campo, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    private static decimal? Numero(JsonElement e, string campo) =>
        e.ValueKind == JsonValueKind.Object && e.TryGetProperty(campo, out var v) && v.ValueKind == JsonValueKind.Number && v.TryGetDecimal(out var n)
            ? n : null;

    private static DateOnly? Fecha(string? texto) =>
        texto is { Length: >= 10 } && DateOnly.TryParseExact(texto[..10], "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var f)
            ? f : null;
}
