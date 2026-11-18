using Microsoft.EntityFrameworkCore;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;
using ProfeApp.Domain.Centros;
using ProfeApp.Infrastructure.Persistence;

namespace ProfeApp.Infrastructure.Centros;

/// <summary>
/// Alumnos, matrícula por año y ficha. Todo va filtrado por la institución de quien llama;
/// la ficha (salud, encargados) la ve el personal del centro, no los docentes.
/// </summary>
public sealed class MatriculaService(AppDbContext db, EstructuraCentroService centro, IClock clock) : IMatriculaService
{
    private const int PorPagina = 50;
    private const int MaxImportar = 300;

    public async Task<Result<IReadOnlyList<AlumnoSeccionDto>>> AlumnosDeSeccionAsync(Guid seccionId, CancellationToken ct = default)
    {
        var (institucion, _) = await centro.ContextoAsync(ct);
        if (institucion is null) return Result<IReadOnlyList<AlumnoSeccionDto>>.Fail(Error.Forbidden(EstructuraCentroService.SinCentro));
        if (!await db.Secciones.AnyAsync(s => s.Id == seccionId && s.InstitucionId == institucion.Id, ct))
            return Result<IReadOnlyList<AlumnoSeccionDto>>.Fail(Error.NotFound("La sección"));

        var filas = await (from m in db.Matriculas.AsNoTracking()
                           join a in db.Alumnos.AsNoTracking() on m.AlumnoId equals a.Id
                           where m.SeccionId == seccionId
                           orderby a.Nombre
                           select new AlumnoSeccionDto(m.Id, a.Id, a.Identidad, a.Nombre, a.Sexo, m.Tipo, m.Estado,
                               m.FechaIngreso, m.FechaBaja, m.MotivoBaja))
            .ToListAsync(ct);
        return filas;
    }

    public async Task<Result<ImportacionDto>> ImportarAsync(Guid seccionId, ImportarAlumnosRequest r, CancellationToken ct = default)
    {
        var (institucion, error) = await centro.EditorAsync(ct);
        if (institucion is null) return Result<ImportacionDto>.Fail(error!);
        var seccion = await db.Secciones.AsNoTracking().FirstOrDefaultAsync(s => s.Id == seccionId && s.InstitucionId == institucion.Id, ct);
        if (seccion is null) return Result<ImportacionDto>.Fail(Error.NotFound("La sección"));
        var ingreso = await FechaIngresoAsync(seccion.AnioLectivoId, ct);

        var entrada = r.Alumnos
            .Select(a => (Identidad: Normalizar(a.Identidad), Nombre: (a.Nombre ?? "").Trim()))
            .Where(a => a.Identidad.Length > 0 && a.Nombre.Length > 0)
            .DistinctBy(a => a.Identidad)
            .ToList();
        if (entrada.Count == 0) return Result<ImportacionDto>.Fail(Error.Validation("El archivo no trae alumnos."));
        if (entrada.Count > MaxImportar) return Result<ImportacionDto>.Fail(Error.Validation($"Se importan hasta {MaxImportar} alumnos a la vez."));
        if (entrada.Any(a => a.Identidad.Length > 30 || a.Nombre.Length > 160))
            return Result<ImportacionDto>.Fail(Error.Validation("Hay identidades o nombres demasiado largos."));

        var identidades = entrada.Select(a => a.Identidad).ToList();
        var alumnos = await db.Alumnos.Where(a => a.InstitucionId == institucion.Id && identidades.Contains(a.Identidad))
            .ToDictionaryAsync(a => a.Identidad, ct);
        var ids = alumnos.Values.Select(a => a.Id).ToList();
        var delAnio = await db.Matriculas.Where(m => ids.Contains(m.AlumnoId) && m.AnioLectivoId == seccion.AnioLectivoId)
            .ToDictionaryAsync(m => m.AlumnoId, ct);
        // Quien estuvo matriculado otro año vuelve como reingreso.
        var conHistoria = (await db.Matriculas.Where(m => ids.Contains(m.AlumnoId) && m.AnioLectivoId != seccion.AnioLectivoId)
            .Select(m => m.AlumnoId).Distinct().ToListAsync(ct)).ToHashSet();
        var nombres = await NombresSeccionesAsync(institucion.Id, delAnio.Values.Select(m => m.SeccionId).Distinct().ToList(), ct);

        int nuevos = 0, yaEstaban = 0, movidos = 0;
        var conflictos = new List<ConflictoMatriculaDto>();
        foreach (var (identidad, nombre) in entrada)
        {
            if (!alumnos.TryGetValue(identidad, out var alumno))
            {
                alumno = new Alumno { InstitucionId = institucion.Id, Identidad = identidad, Nombre = nombre };
                db.Alumnos.Add(alumno);
                alumnos[identidad] = alumno;
            }
            else if (alumno.Nombre != nombre)
            {
                alumno.Nombre = nombre; // SACE manda en el nombre.
            }

            if (!delAnio.TryGetValue(alumno.Id, out var matricula))
            {
                db.Matriculas.Add(new Matricula
                {
                    InstitucionId = institucion.Id,
                    AlumnoId = alumno.Id,
                    AnioLectivoId = seccion.AnioLectivoId,
                    SeccionId = seccion.Id,
                    Tipo = conHistoria.Contains(alumno.Id) ? TiposMatricula.Reingreso : TiposMatricula.NuevoIngreso,
                    FechaIngreso = ingreso,
                });
                nuevos++;
            }
            else if (matricula.SeccionId == seccion.Id)
            {
                yaEstaban++;
            }
            else if (r.MoverDeSeccion)
            {
                matricula.SeccionId = seccion.Id;
                movidos++;
            }
            else
            {
                conflictos.Add(new ConflictoMatriculaDto(identidad, nombre, nombres.GetValueOrDefault(matricula.SeccionId) ?? "otra sección"));
            }
        }
        await db.SaveChangesAsync(ct);

        var activos = await db.Matriculas.CountAsync(m => m.SeccionId == seccion.Id && m.Estado == EstadosMatricula.Activa, ct);
        return new ImportacionDto(nuevos, yaEstaban, movidos, conflictos, activos, seccion.Cupo);
    }

    public async Task<Result<AlumnoSeccionDto>> MatricularAsync(Guid seccionId, MatricularRequest r, CancellationToken ct = default)
    {
        var (institucion, error) = await centro.EditorAsync(ct);
        if (institucion is null) return Result<AlumnoSeccionDto>.Fail(error!);
        var seccion = await db.Secciones.AsNoTracking().FirstOrDefaultAsync(s => s.Id == seccionId && s.InstitucionId == institucion.Id, ct);
        if (seccion is null) return Result<AlumnoSeccionDto>.Fail(Error.NotFound("La sección"));
        var identidad = Normalizar(r.Identidad);
        var nombre = (r.Nombre ?? "").Trim();
        if (identidad.Length is 0 or > 30) return Result<AlumnoSeccionDto>.Fail(Error.Validation("La identidad es obligatoria."));
        if (nombre.Length is 0 or > 160) return Result<AlumnoSeccionDto>.Fail(Error.Validation("El nombre es obligatorio."));
        if (!TiposMatricula.Todos.Contains(r.Tipo)) return Result<AlumnoSeccionDto>.Fail(Error.Validation("Tipo de matrícula desconocido."));

        var alumno = await db.Alumnos.FirstOrDefaultAsync(a => a.InstitucionId == institucion.Id && a.Identidad == identidad, ct);
        if (alumno is null)
        {
            alumno = new Alumno { InstitucionId = institucion.Id, Identidad = identidad, Nombre = nombre };
            db.Alumnos.Add(alumno);
        }
        else
        {
            var ya = await db.Matriculas.AsNoTracking()
                .FirstOrDefaultAsync(m => m.AlumnoId == alumno.Id && m.AnioLectivoId == seccion.AnioLectivoId, ct);
            if (ya is not null)
            {
                var donde = (await NombresSeccionesAsync(institucion.Id, [ya.SeccionId], ct)).GetValueOrDefault(ya.SeccionId);
                return Result<AlumnoSeccionDto>.Fail(Error.Conflict($"{alumno.Nombre} ya está matriculado este año en {donde}.", "ya_matriculado"));
            }
        }

        var matricula = new Matricula
        {
            InstitucionId = institucion.Id,
            AlumnoId = alumno.Id,
            AnioLectivoId = seccion.AnioLectivoId,
            SeccionId = seccion.Id,
            Tipo = r.Tipo,
            FechaIngreso = r.FechaIngreso ?? await FechaIngresoAsync(seccion.AnioLectivoId, ct),
        };
        db.Matriculas.Add(matricula);
        await db.SaveChangesAsync(ct);
        return new AlumnoSeccionDto(matricula.Id, alumno.Id, alumno.Identidad, alumno.Nombre, alumno.Sexo, matricula.Tipo,
            matricula.Estado, matricula.FechaIngreso, null, null);
    }

    public async Task<Result<PaginaAlumnosDto>> BuscarAsync(string? buscar, int pagina, CancellationToken ct = default)
    {
        var (institucion, _) = await centro.ContextoAsync(ct);
        if (institucion is null) return Result<PaginaAlumnosDto>.Fail(Error.Forbidden(EstructuraCentroService.SinCentro));
        pagina = Math.Max(0, pagina);

        var consulta = db.Alumnos.AsNoTracking().Where(a => a.InstitucionId == institucion.Id);
        if (!string.IsNullOrWhiteSpace(buscar))
        {
            var texto = buscar.Trim();
            var patron = $"%{texto.Replace("\\", "\\\\").Replace("%", "\\%").Replace("_", "\\_")}%";
            var identidad = Normalizar(texto);
            consulta = consulta.Where(a => EF.Functions.ILike(a.Nombre, patron) || (identidad.Length > 0 && a.Identidad.StartsWith(identidad)));
        }

        var total = await consulta.CountAsync(ct);
        var filas = await consulta.OrderBy(a => a.Nombre).ThenBy(a => a.Id)
            .Skip(pagina * PorPagina).Take(PorPagina)
            .Select(a => new { a.Id, a.Identidad, a.Nombre })
            .ToListAsync(ct);

        // Su matrícula del año actual, si tiene.
        var actual = await db.AniosLectivos.Where(a => a.InstitucionId == institucion.Id && a.Actual).Select(a => (Guid?)a.Id).FirstOrDefaultAsync(ct);
        var idsAlumnos = filas.Select(f => f.Id).ToList();
        var matriculas = actual is null
            ? []
            : await db.Matriculas.AsNoTracking().Where(m => idsAlumnos.Contains(m.AlumnoId) && m.AnioLectivoId == actual)
                .ToDictionaryAsync(m => m.AlumnoId, ct);
        var nombres = await NombresSeccionesAsync(institucion.Id, matriculas.Values.Select(m => m.SeccionId).Distinct().ToList(), ct);

        return new PaginaAlumnosDto(
            filas.Select(f => matriculas.TryGetValue(f.Id, out var m)
                    ? new AlumnoBuscadoDto(f.Id, f.Identidad, f.Nombre, nombres.GetValueOrDefault(m.SeccionId), m.Estado)
                    : new AlumnoBuscadoDto(f.Id, f.Identidad, f.Nombre, null, null))
                .ToList(),
            total,
            (pagina + 1) * PorPagina < total);
    }

    public async Task<Result<FichaAlumnoDto>> FichaAsync(Guid alumnoId, CancellationToken ct = default)
    {
        var (institucion, yo) = await centro.ContextoAsync(ct);
        if (institucion is null) return Result<FichaAlumnoDto>.Fail(Error.Forbidden(EstructuraCentroService.SinCentro));
        var alumno = await db.Alumnos.AsNoTracking().FirstOrDefaultAsync(a => a.Id == alumnoId && a.InstitucionId == institucion.Id, ct);
        if (alumno is null) return Result<FichaAlumnoDto>.Fail(Error.NotFound("El alumno"));
        return await ArmarFichaAsync(alumno, institucion.Id, Cargos.Administra(yo!.Cargo), ct);
    }

    public async Task<Result<FichaAlumnoDto>> GuardarFichaAsync(Guid alumnoId, FichaAlumnoRequest r, CancellationToken ct = default)
    {
        var (institucion, error) = await centro.EditorAsync(ct);
        if (institucion is null) return Result<FichaAlumnoDto>.Fail(error!);
        var alumno = await db.Alumnos.FirstOrDefaultAsync(a => a.Id == alumnoId && a.InstitucionId == institucion.Id, ct);
        if (alumno is null) return Result<FichaAlumnoDto>.Fail(Error.NotFound("El alumno"));

        var identidad = Normalizar(r.Identidad);
        var nombre = (r.Nombre ?? "").Trim();
        if (identidad.Length is 0 or > 30) return Result<FichaAlumnoDto>.Fail(Error.Validation("La identidad es obligatoria."));
        if (nombre.Length is 0 or > 160) return Result<FichaAlumnoDto>.Fail(Error.Validation("El nombre es obligatorio."));
        if (r.Sexo is not (null or "F" or "M")) return Result<FichaAlumnoDto>.Fail(Error.Validation("Sexo: F o M."));
        if (r.FechaNacimiento is { } nac && (nac > clock.Today || nac.Year < 1950))
            return Result<FichaAlumnoDto>.Fail(Error.Validation("La fecha de nacimiento no es válida."));
        if (Largo(r.Direccion) > 300 || Largo(r.Salud) > 1000 || Largo(r.Notas) > 1000)
            return Result<FichaAlumnoDto>.Fail(Error.Validation("Algún texto es demasiado largo."));
        var encargados = r.Encargados.Where(e => !string.IsNullOrWhiteSpace(e.Nombre)).ToList();
        if (encargados.Count > 4) return Result<FichaAlumnoDto>.Fail(Error.Validation("Hasta cuatro encargados."));
        if (encargados.Any(e => e.Nombre.Trim().Length > 160 || Largo(e.Parentesco) > 40 || Largo(e.Telefono) > 30 || Largo(e.Correo) > 160))
            return Result<FichaAlumnoDto>.Fail(Error.Validation("Algún dato del encargado es demasiado largo."));
        if (identidad != alumno.Identidad
            && await db.Alumnos.AnyAsync(a => a.InstitucionId == institucion.Id && a.Identidad == identidad && a.Id != alumno.Id, ct))
            return Result<FichaAlumnoDto>.Fail(Error.Conflict("Ya hay otro alumno con esa identidad."));

        alumno.Identidad = identidad;
        alumno.Nombre = nombre;
        alumno.FechaNacimiento = r.FechaNacimiento;
        alumno.Sexo = r.Sexo;
        alumno.Direccion = Limpio(r.Direccion);
        alumno.Salud = Limpio(r.Salud);
        alumno.Notas = Limpio(r.Notas);

        // Un solo principal: el marcado, o el primero si nadie lo está.
        var principal = encargados.FindIndex(e => e.Principal);
        if (principal < 0) principal = 0;
        await db.Database.CreateExecutionStrategy().ExecuteAsync(async () =>
        {
            await using var tx = await db.Database.BeginTransactionAsync(ct);
            await db.Encargados.Where(e => e.AlumnoId == alumno.Id).ExecuteDeleteAsync(ct);
            db.Encargados.AddRange(encargados.Select((e, i) => new Encargado
            {
                InstitucionId = institucion.Id,
                AlumnoId = alumno.Id,
                Nombre = e.Nombre.Trim(),
                Parentesco = Limpio(e.Parentesco),
                Telefono = Limpio(e.Telefono),
                Correo = Limpio(e.Correo)?.ToLowerInvariant(),
                Principal = i == principal,
            }));
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
        });
        return await ArmarFichaAsync(alumno, institucion.Id, true, ct);
    }

    public async Task<Result> DarDeBajaAsync(Guid matriculaId, BajaRequest r, CancellationToken ct = default)
    {
        var (institucion, error) = await centro.EditorAsync(ct);
        if (institucion is null) return Result.Fail(error!);
        if (!EstadosMatricula.Bajas.Contains(r.Estado)) return Result.Fail(Error.Validation("La baja es retiro o traslado."));
        if (Largo(r.Motivo) > 300) return Result.Fail(Error.Validation("El motivo admite hasta 300 caracteres."));
        var matricula = await db.Matriculas.FirstOrDefaultAsync(m => m.Id == matriculaId && m.InstitucionId == institucion.Id, ct);
        if (matricula is null) return Result.Fail(Error.NotFound("La matrícula"));
        if (r.Fecha < matricula.FechaIngreso) return Result.Fail(Error.Validation("La baja no puede ser antes del ingreso."));
        matricula.Estado = r.Estado;
        matricula.FechaBaja = r.Fecha;
        matricula.MotivoBaja = Limpio(r.Motivo);
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    public async Task<Result> ReactivarAsync(Guid matriculaId, CancellationToken ct = default)
    {
        var (institucion, error) = await centro.EditorAsync(ct);
        if (institucion is null) return Result.Fail(error!);
        var matricula = await db.Matriculas.FirstOrDefaultAsync(m => m.Id == matriculaId && m.InstitucionId == institucion.Id, ct);
        if (matricula is null) return Result.Fail(Error.NotFound("La matrícula"));
        matricula.Estado = EstadosMatricula.Activa;
        matricula.FechaBaja = null;
        matricula.MotivoBaja = null;
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    public async Task<Result> CambiarSeccionAsync(Guid matriculaId, CambioSeccionRequest r, CancellationToken ct = default)
    {
        var (institucion, error) = await centro.EditorAsync(ct);
        if (institucion is null) return Result.Fail(error!);
        var matricula = await db.Matriculas.FirstOrDefaultAsync(m => m.Id == matriculaId && m.InstitucionId == institucion.Id, ct);
        if (matricula is null) return Result.Fail(Error.NotFound("La matrícula"));
        var destino = await db.Secciones.AsNoTracking().FirstOrDefaultAsync(s => s.Id == r.SeccionId && s.InstitucionId == institucion.Id, ct);
        if (destino is null) return Result.Fail(Error.NotFound("La sección"));
        if (destino.AnioLectivoId != matricula.AnioLectivoId)
            return Result.Fail(Error.Validation("La sección nueva debe ser del mismo año lectivo."));
        matricula.SeccionId = destino.Id;
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    // ── Apoyo ────────────────────────────────────────────────────────────────

    private async Task<FichaAlumnoDto> ArmarFichaAsync(Alumno a, Guid institucionId, bool puedeEditar, CancellationToken ct)
    {
        var encargados = await db.Encargados.AsNoTracking().Where(e => e.AlumnoId == a.Id)
            .OrderByDescending(e => e.Principal).ThenBy(e => e.Nombre)
            .Select(e => new EncargadoDto(e.Nombre, e.Parentesco, e.Telefono, e.Correo, e.Principal))
            .ToListAsync(ct);
        var matriculas = await (from m in db.Matriculas.AsNoTracking()
                                join an in db.AniosLectivos.AsNoTracking() on m.AnioLectivoId equals an.Id
                                where m.AlumnoId == a.Id
                                orderby an.Anio descending
                                select new { m, an.Anio })
            .ToListAsync(ct);
        var nombres = await NombresSeccionesAsync(institucionId, matriculas.Select(x => x.m.SeccionId).Distinct().ToList(), ct);
        return new FichaAlumnoDto(a.Id, a.Identidad, a.Nombre, a.FechaNacimiento, a.Sexo, a.Direccion, a.Salud, a.Notas,
            encargados,
            matriculas.Select(x => new MatriculaHistorialDto(x.m.Id, x.Anio, x.m.SeccionId, nombres.GetValueOrDefault(x.m.SeccionId) ?? "",
                x.m.Tipo, x.m.Estado, x.m.FechaIngreso, x.m.FechaBaja, x.m.MotivoBaja)).ToList(),
            puedeEditar);
    }

    /// <summary>Hoy, o el inicio del año lectivo si se matricula antes de que empiece.</summary>
    private async Task<DateOnly> FechaIngresoAsync(Guid anioLectivoId, CancellationToken ct)
    {
        var inicio = await db.AniosLectivos.Where(a => a.Id == anioLectivoId).Select(a => a.Inicio).FirstAsync(ct);
        return inicio > clock.Today ? inicio : clock.Today;
    }

    /// <summary>"7.º grado A (matutina)" de cada sección pedida.</summary>
    private async Task<Dictionary<Guid, string>> NombresSeccionesAsync(Guid institucionId, List<Guid> secciones, CancellationToken ct) =>
        (await (from s in db.Secciones.AsNoTracking()
                join g in db.Grados.AsNoTracking() on s.GradoId equals g.Id
                where s.InstitucionId == institucionId && secciones.Contains(s.Id)
                select new { s.Id, Grado = g.Nombre, s.Nombre, s.Jornada })
            .ToListAsync(ct))
        .ToDictionary(x => x.Id, x => $"{x.Grado} {x.Nombre} ({x.Jornada})");

    /// <summary>Sin espacios ni guiones, en mayúsculas: "0801-2012-01234" → "0801201201234".</summary>
    internal static string Normalizar(string? identidad) =>
        new((identidad ?? "").Where(char.IsLetterOrDigit).Select(char.ToUpperInvariant).ToArray());

    private static int Largo(string? texto) => texto?.Trim().Length ?? 0;
    private static string? Limpio(string? texto) => string.IsNullOrWhiteSpace(texto) ? null : texto.Trim();
}
