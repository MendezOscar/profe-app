using System.IO.Compression;
using Microsoft.EntityFrameworkCore;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;
using ProfeApp.Domain.Centros;
using ProfeApp.Domain.Common;
using ProfeApp.Domain.Cuadros;
using ProfeApp.Infrastructure.Persistence;

namespace ProfeApp.Infrastructure.Centros;

/// <summary>
/// Consolidado de una sección con las notas que los docentes del centro cerraron en sus
/// cuadros de SACE. Una clase de un docente es de la sección si al menos la mitad de su
/// lista está matriculada en ella. Solo lee: no cambia nada del docente.
/// </summary>
public sealed class ConsolidadoService(AppDbContext db, EstructuraCentroService centro, ICuadroSaceWriter writer)
    : IConsolidadoService
{
    public const int NotaMinima = 70;

    private sealed record ClaseDeSeccion(
        Clase Clase, string Docente, List<ClaseColumna> Columnas, Dictionary<string, string> ClavePorIdentidad);

    public async Task<Result<ConsolidadoDto>> SeccionAsync(Guid seccionId, CancellationToken ct = default)
    {
        var (institucion, _) = await centro.ContextoAsync(ct);
        if (institucion is null) return Result<ConsolidadoDto>.Fail(Error.Forbidden(EstructuraCentroService.SinCentro));
        var consolidado = await DeSeccionAsync(institucion.Id, institucion.Nombre, seccionId, ct);
        return consolidado is null ? Result<ConsolidadoDto>.Fail(Error.NotFound("La sección")) : consolidado;
    }

    /// <summary>El consolidado de una sección del centro (null si no es suya). Lo usan también los reportes.</summary>
    internal async Task<ConsolidadoDto?> DeSeccionAsync(Guid institucionId, string nombreCentro, Guid seccionId, CancellationToken ct)
    {
        var seccion = await (from s in db.Secciones.AsNoTracking()
                             join g in db.Grados.AsNoTracking() on s.GradoId equals g.Id
                             join a in db.AniosLectivos.AsNoTracking() on s.AnioLectivoId equals a.Id
                             where s.Id == seccionId && s.InstitucionId == institucionId
                             select new { s.Id, Nombre = g.Nombre + " " + s.Nombre, s.Jornada, a.Anio })
            .FirstOrDefaultAsync(ct);
        if (seccion is null) return null;

        var alumnos = await (from m in db.Matriculas.AsNoTracking()
                             join a in db.Alumnos.AsNoTracking() on m.AlumnoId equals a.Id
                             where m.SeccionId == seccionId
                             orderby a.Nombre
                             select new { a.Id, a.Identidad, a.Nombre, m.Estado })
            .ToListAsync(ct);
        var clases = await ClasesDeSeccionAsync(institucionId, alumnos.Select(a => a.Identidad).ToHashSet(), ct);
        var ids = clases.Select(c => c.Clase.Id).ToList();
        var valores = (await db.ClaseValores.IgnoreQueryFilters().AsNoTracking()
                .Where(v => ids.Contains(v.ClaseId) && v.Valor != null)
                .Select(v => new { v.ClaseId, v.AlumnoClave, v.ColumnaClave, v.Valor })
                .ToListAsync(ct))
            .ToDictionary(v => (v.ClaseId, v.AlumnoClave, v.ColumnaClave), v => v.Valor!.Value);
        var conArchivo = (await db.Set<ClaseArchivo>().AsNoTracking().Where(a => ids.Contains(a.Id) && a.Contenido.Length > 0)
            .Select(a => a.Id).ToListAsync(ct)).ToHashSet();

        var conducta = (await db.Conductas.AsNoTracking().Where(c => c.SeccionId == seccionId).ToListAsync(ct))
            .ToLookup(c => c.AlumnoId);
        // En la boleta va el comentario del último parcial que lo tenga.
        var comentarios = (await db.ComentariosBoleta.AsNoTracking().Where(c => c.SeccionId == seccionId)
                .Select(c => new { c.AlumnoId, c.Parcial, c.Texto }).ToListAsync(ct))
            .GroupBy(c => c.AlumnoId).ToDictionary(g => g.Key, g => g.OrderByDescending(c => c.Parcial).First().Texto);
        var estructuras = clases.Select(c => (c, Estructura: Estructura(c.Columnas))).ToList();
        var filas = alumnos.Select(a =>
        {
            var notas = estructuras.Select(x =>
            {
                if (!x.c.ClavePorIdentidad.TryGetValue(a.Identidad, out var clave)) return null;
                int? V(ClaseColumna? col) => col is not null && valores.TryGetValue((x.c.Clase.Id, clave, col.Clave), out var v) ? v : null;
                var parciales = x.Estructura.Parciales.Select(p => V(p.Nota) is { } n ? n + (V(p.Nivelacion) ?? 0) : (int?)null).ToList();
                var inasistencias = x.Estructura.Parciales.Sum(p => V(p.Inasistencias) ?? 0);
                return Calificar(parciales, V(x.Estructura.Recuperacion), inasistencias);
            }).ToList();
            var letras = Enumerable.Range(1, 4).Select(p => conducta[a.Id].FirstOrDefault(c => c.Parcial == p)?.Nota).ToList();
            return new AlumnoConsolidadoDto(a.Id, a.Identidad, a.Nombre, a.Estado, notas, Resultado(notas), letras,
                comentarios.GetValueOrDefault(a.Id));
        }).ToList();

        return new ConsolidadoDto(seccion.Id, seccion.Nombre, seccion.Jornada, nombreCentro, seccion.Anio, NotaMinima,
            estructuras.Select(x => new AsignaturaConsolidadoDto(x.c.Clase.Id, x.c.Clase.Asignatura ?? "Asignatura", x.c.Docente,
                x.Estructura.Parciales.Select(p => p.Nombre).ToList(), conArchivo.Contains(x.c.Clase.Id))).ToList(),
            filas);
    }

    public async Task<Result<CuadroExportado>> CuadrosSaceAsync(Guid seccionId, CancellationToken ct = default)
    {
        var (institucion, _) = await centro.ContextoAsync(ct);
        if (institucion is null) return Result<CuadroExportado>.Fail(Error.Forbidden(EstructuraCentroService.SinCentro));
        var seccion = await (from s in db.Secciones.AsNoTracking()
                             join g in db.Grados.AsNoTracking() on s.GradoId equals g.Id
                             where s.Id == seccionId && s.InstitucionId == institucion.Id
                             select new { s.Id, Nombre = g.Nombre + " " + s.Nombre })
            .FirstOrDefaultAsync(ct);
        if (seccion is null) return Result<CuadroExportado>.Fail(Error.NotFound("La sección"));

        var identidades = (await (from m in db.Matriculas.AsNoTracking()
                                  join a in db.Alumnos.AsNoTracking() on m.AlumnoId equals a.Id
                                  where m.SeccionId == seccionId
                                  select a.Identidad).ToListAsync(ct)).ToHashSet();
        var clases = await ClasesDeSeccionAsync(institucion.Id, identidades, ct);
        if (clases.Count == 0)
            return Result<CuadroExportado>.Fail(Error.NotFound("Ningún cuadro de SACE de la sección"));

        using var zip = new MemoryStream();
        var nombres = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        using (var archivo = new ZipArchive(zip, ZipArchiveMode.Create, leaveOpen: true))
        {
            foreach (var c in clases)
            {
                var original = await db.Set<ClaseArchivo>().AsNoTracking().Where(a => a.Id == c.Clase.Id)
                    .Select(a => a.Contenido).FirstOrDefaultAsync(ct);
                if (original is not { Length: > 0 }) continue;
                var alumnos = await db.ClaseAlumnos.IgnoreQueryFilters().AsNoTracking()
                    .Where(a => a.ClaseId == c.Clase.Id).Select(a => new { a.Clave, a.Fila }).ToListAsync(ct);
                var valores = (await db.ClaseValores.IgnoreQueryFilters().AsNoTracking().Where(v => v.ClaseId == c.Clase.Id)
                        .Select(v => new { v.AlumnoClave, v.ColumnaClave, v.Valor }).ToListAsync(ct))
                    .ToDictionary(v => (v.AlumnoClave, v.ColumnaClave), v => v.Valor);
                // Cada celda editable: con su valor o vacía, igual que exporta el docente.
                var celdas = (from a in alumnos
                              from col in c.Columnas
                              select new CeldaCuadro(a.Fila, col.Col, valores.GetValueOrDefault((a.Clave, col.Clave)))).ToList();
                var lleno = writer.Rellenar(new ExportarCuadroRequest(
                    Convert.ToBase64String(original), c.Clase.ArchivoNombre, c.Clase.Hoja, celdas));
                if (!lleno.IsSuccess) continue;

                var nombre = Path.GetFileNameWithoutExtension(lleno.Value.NombreArchivo);
                var ext = Path.GetExtension(lleno.Value.NombreArchivo);
                var unico = nombre + ext;
                for (var n = 2; !nombres.Add(unico); n++) unico = $"{nombre} ({n}){ext}";
                var entrada = archivo.CreateEntry(unico, CompressionLevel.Optimal);
                await using var destino = entrada.Open();
                await destino.WriteAsync(lleno.Value.Contenido, ct);
            }
        }
        if (nombres.Count == 0) return Result<CuadroExportado>.Fail(Error.NotFound("Ningún cuadro de SACE con archivo"));
        var limpio = string.Concat(seccion.Nombre.Split(Path.GetInvalidFileNameChars()));
        return new CuadroExportado(zip.ToArray(), $"Cuadros SACE {limpio}.zip", "application/zip");
    }

    // ── Apoyo ────────────────────────────────────────────────────────────────

    /// <summary>Clases de los docentes del centro cuya lista es, al menos en la mitad, de esta sección.</summary>
    private async Task<List<ClaseDeSeccion>> ClasesDeSeccionAsync(Guid institucionId, HashSet<string> identidades, CancellationToken ct)
    {
        if (identidades.Count == 0) return [];
        var docentes = await (from u in db.Users.AsNoTracking()
                              join ur in db.UserRoles on u.Id equals ur.UserId
                              join r in db.Roles on ur.RoleId equals r.Id
                              where r.Name == Roles.Docente && u.InstitucionId == institucionId && u.TenantId != null
                              select new { Tenant = u.TenantId!.Value, u.FullName })
            .ToListAsync(ct);
        var tenants = docentes.Select(d => d.Tenant).ToList();
        var lista = identidades.ToList();
        var coinciden = await db.ClaseAlumnos.IgnoreQueryFilters().AsNoTracking()
            .Where(ca => tenants.Contains(ca.TenantId) && ca.Activo
                         && lista.Contains(ca.Identidad.Replace("-", "").Replace(" ", "").ToUpper()))
            .GroupBy(ca => ca.ClaseId).Select(g => new { g.Key, N = g.Count() })
            .ToListAsync(ct);
        if (coinciden.Count == 0) return [];
        var candidatas = coinciden.Select(c => c.Key).ToList();
        var tamanos = await db.ClaseAlumnos.IgnoreQueryFilters().AsNoTracking()
            .Where(ca => candidatas.Contains(ca.ClaseId) && ca.Activo)
            .GroupBy(ca => ca.ClaseId).Select(g => new { g.Key, N = g.Count() })
            .ToDictionaryAsync(x => x.Key, x => x.N, ct);
        var ids = coinciden.Where(c => c.N * 2 >= tamanos.GetValueOrDefault(c.Key)).Select(c => c.Key).ToList();

        var clases = await db.Clases.IgnoreQueryFilters().AsNoTracking()
            .Where(c => ids.Contains(c.Id) && c.EliminadaEn == null).OrderBy(c => c.Asignatura).ToListAsync(ct);
        var columnas = (await db.ClaseColumnas.IgnoreQueryFilters().AsNoTracking().Where(c => ids.Contains(c.ClaseId))
            .OrderBy(c => c.Orden).ToListAsync(ct)).ToLookup(c => c.ClaseId);
        var claves = (await db.ClaseAlumnos.IgnoreQueryFilters().AsNoTracking().Where(ca => ids.Contains(ca.ClaseId))
                .Select(ca => new { ca.ClaseId, ca.Identidad, ca.Clave }).ToListAsync(ct))
            .ToLookup(x => x.ClaseId);
        var nombre = docentes.ToDictionary(d => d.Tenant, d => d.FullName);
        return clases.Select(c => new ClaseDeSeccion(
                c, nombre.GetValueOrDefault(c.TenantId) ?? "", columnas[c.Id].ToList(),
                claves[c.Id].GroupBy(x => MatriculaService.Normalizar(x.Identidad)).ToDictionary(g => g.Key, g => g.First().Clave)))
            .ToList();
    }

    private sealed record Parcial(string Nombre, ClaseColumna? Nota, ClaseColumna? Nivelacion, ClaseColumna? Inasistencias);

    private sealed record EstructuraCuadro(List<Parcial> Parciales, ClaseColumna? Recuperacion);

    /// <summary>Parciales del cuadro por su grupo (PARCIAL I…), con sus columnas, y la de recuperación.</summary>
    private static EstructuraCuadro Estructura(List<ClaseColumna> columnas)
    {
        var parciales = columnas.Where(c => c.Grupo.Contains("PARCIAL", StringComparison.OrdinalIgnoreCase))
            .GroupBy(c => c.Grupo.Trim().ToUpperInvariant())
            .Select(g => new Parcial(g.Key,
                g.FirstOrDefault(c => c.Tipo == "nota"),
                g.FirstOrDefault(c => c.Tipo == "nivelacion"),
                g.FirstOrDefault(c => c.Tipo == "inasistencias")))
            .Where(p => p.Nota is not null)
            .ToList();
        var recuperacion = columnas.FirstOrDefault(c => c.Tipo == "nota"
            && (c.Grupo.Contains("RECUPERA", StringComparison.OrdinalIgnoreCase) || c.Nombre.Contains("RECUPERA", StringComparison.OrdinalIgnoreCase)));
        return new EstructuraCuadro(parciales, recuperacion);
    }

    internal static NotaAsignaturaDto Calificar(List<int?> parciales, int? recuperacion, int inasistencias)
    {
        if (parciales.Count == 0 || parciales.Any(p => p is null))
            return new NotaAsignaturaDto(parciales, null, recuperacion, inasistencias, "en_curso");
        var final = (int)Math.Round(parciales.Average(p => p!.Value), MidpointRounding.AwayFromZero);
        var estado = final >= NotaMinima ? "aprobada"
            : recuperacion is null ? "recuperacion"
            : recuperacion >= NotaMinima ? "aprobada"
            : "reprobada";
        return new NotaAsignaturaDto(parciales, final, recuperacion, inasistencias, estado);
    }

    private static string Resultado(List<NotaAsignaturaDto?> notas)
    {
        var con = notas.OfType<NotaAsignaturaDto>().ToList();
        if (con.Count == 0) return "sin_notas";
        if (con.Any(n => n.Estado == "reprobada")) return "reprobado";
        if (con.Any(n => n.Estado == "en_curso")) return "en_curso";
        if (con.Any(n => n.Estado == "recuperacion")) return "recuperacion";
        return "aprobado";
    }
}
