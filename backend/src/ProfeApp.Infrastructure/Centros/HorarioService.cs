using Microsoft.EntityFrameworkCore;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;
using ProfeApp.Domain.Centros;
using ProfeApp.Infrastructure.Persistence;

namespace ProfeApp.Infrastructure.Centros;

/// <summary>
/// Horario del centro. El docente de cada clase sale de la carga docente; el aula, de la
/// sección salvo que la celda indique otra. Un choque es el mismo docente o la misma aula en
/// dos secciones a la vez (mismo día y horas que se cruzan, aunque sean de otra jornada).
/// </summary>
public sealed class HorarioService(
    AppDbContext db,
    EstructuraCentroService centro,
    ICurrentUser currentUser,
    IClock clock,
    IAvisosPush avisos) : IHorarioService
{
    private static readonly string[] Dias = ["", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"];
    private const int ChoquesMostrados = 8;

    // ── Bloques ──────────────────────────────────────────────────────────────

    public async Task<Result<IReadOnlyList<BloqueDto>>> BloquesAsync(CancellationToken ct = default)
    {
        var (institucion, _) = await centro.ContextoAsync(ct);
        if (institucion is null) return Result<IReadOnlyList<BloqueDto>>.Fail(Error.Forbidden(EstructuraCentroService.SinCentro));
        return (await db.BloquesHorario.AsNoTracking().Where(b => b.InstitucionId == institucion.Id)
                .OrderBy(b => b.Jornada).ThenBy(b => b.Inicio).ToListAsync(ct))
            .Select(ADto).ToList();
    }

    public async Task<Result<BloqueDto>> GuardarBloqueAsync(Guid? id, BloqueRequest r, CancellationToken ct = default)
    {
        var (institucion, error) = await centro.EditorAsync(ct);
        if (institucion is null) return Result<BloqueDto>.Fail(error!);
        if (!Jornadas.Todas.Contains(r.Jornada)) return Result<BloqueDto>.Fail(Error.Validation("Jornada desconocida."));
        if (r.Fin <= r.Inicio) return Result<BloqueDto>.Fail(Error.Validation("El bloque debe terminar después de empezar."));
        var bloque = id is { } bid
            ? await db.BloquesHorario.FirstOrDefaultAsync(b => b.Id == bid && b.InstitucionId == institucion.Id, ct)
            : new BloqueHorario { InstitucionId = institucion.Id };
        if (bloque is null) return Result<BloqueDto>.Fail(Error.NotFound("El bloque"));
        if (await db.BloquesHorario.AnyAsync(b => b.InstitucionId == institucion.Id && b.Jornada == r.Jornada && b.Id != bloque.Id
                                                 && b.Inicio < r.Fin && r.Inicio < b.Fin, ct))
            return Result<BloqueDto>.Fail(Error.Conflict("Se cruza con otro bloque de esa jornada."));
        if (id is not null && bloque.Jornada != r.Jornada && await db.HorariosClase.AnyAsync(h => h.BloqueId == bloque.Id, ct))
            return Result<BloqueDto>.Fail(Error.Conflict("El bloque ya tiene clases: no se cambia de jornada."));
        if (r.EsReceso && id is not null && await db.HorariosClase.AnyAsync(h => h.BloqueId == bloque.Id, ct))
            return Result<BloqueDto>.Fail(Error.Conflict("El bloque ya tiene clases: quítalas antes de volverlo receso."));

        bloque.Jornada = r.Jornada;
        bloque.Inicio = r.Inicio;
        bloque.Fin = r.Fin;
        bloque.EsReceso = r.EsReceso;
        if (id is null) db.BloquesHorario.Add(bloque);
        await db.SaveChangesAsync(ct);

        // El orden sigue a la hora de inicio.
        var deJornada = await db.BloquesHorario.Where(b => b.InstitucionId == institucion.Id && b.Jornada == r.Jornada)
            .OrderBy(b => b.Inicio).ToListAsync(ct);
        for (var i = 0; i < deJornada.Count; i++) deJornada[i].Orden = i + 1;
        await db.SaveChangesAsync(ct);
        return ADto(bloque);
    }

    public async Task<Result> EliminarBloqueAsync(Guid id, CancellationToken ct = default)
    {
        var (institucion, error) = await centro.EditorAsync(ct);
        if (institucion is null) return Result.Fail(error!);
        if (await db.HorariosClase.AnyAsync(h => h.BloqueId == id, ct))
            return Result.Fail(Error.Conflict("El bloque tiene clases en el horario. Quítalas primero."));
        var borrados = await db.BloquesHorario.Where(b => b.Id == id && b.InstitucionId == institucion.Id).ExecuteDeleteAsync(ct);
        return borrados == 0 ? Result.Fail(Error.NotFound("El bloque")) : Result.Success();
    }

    // ── Horario de secciones ─────────────────────────────────────────────────

    public async Task<Result<HorarioSeccionDto>> HorarioSeccionAsync(Guid seccionId, CancellationToken ct = default)
    {
        var (institucion, _) = await centro.ContextoAsync(ct);
        if (institucion is null) return Result<HorarioSeccionDto>.Fail(Error.Forbidden(EstructuraCentroService.SinCentro));
        var seccion = await db.Secciones.AsNoTracking().FirstOrDefaultAsync(s => s.Id == seccionId && s.InstitucionId == institucion.Id, ct);
        if (seccion is null) return Result<HorarioSeccionDto>.Fail(Error.NotFound("La sección"));
        var anio = await CeldasDelAnioAsync(seccion.AnioLectivoId, ct);
        return new HorarioSeccionDto(seccionId,
            anio.Where(c => c.SeccionId == seccionId).Select(c => new CeldaHorarioDto(c.Dia, c.BloqueId, c.AsignaturaId, c.AulaPropia, c.DocenteId)).ToList(),
            Choques(anio, seccionId).Take(ChoquesMostrados).ToList());
    }

    public async Task<Result<HorarioSeccionDto>> GuardarHorarioAsync(Guid seccionId, HorarioSeccionRequest r, CancellationToken ct = default)
    {
        var (institucion, error) = await centro.EditorAsync(ct);
        if (institucion is null) return Result<HorarioSeccionDto>.Fail(error!);
        var seccion = await db.Secciones.AsNoTracking().FirstOrDefaultAsync(s => s.Id == seccionId && s.InstitucionId == institucion.Id, ct);
        if (seccion is null) return Result<HorarioSeccionDto>.Fail(Error.NotFound("La sección"));

        if (r.Celdas.Any(c => c.Dia is < 1 or > 6)) return Result<HorarioSeccionDto>.Fail(Error.Validation("Los días van de lunes a sábado."));
        if (r.Celdas.GroupBy(c => (c.Dia, c.BloqueId)).Any(g => g.Count() > 1))
            return Result<HorarioSeccionDto>.Fail(Error.Validation("Una sola asignatura por día y bloque."));
        var bloques = await db.BloquesHorario.AsNoTracking()
            .Where(b => b.InstitucionId == institucion.Id && b.Jornada == seccion.Jornada && !b.EsReceso).Select(b => b.Id).ToListAsync(ct);
        if (r.Celdas.Any(c => !bloques.Contains(c.BloqueId)))
            return Result<HorarioSeccionDto>.Fail(Error.Validation("Hay bloques que no son de la jornada de la sección o son receso."));
        var asignaturas = await db.AsignaturasGrado.AsNoTracking().Where(a => a.GradoId == seccion.GradoId).Select(a => a.Id).ToListAsync(ct);
        if (r.Celdas.Any(c => !asignaturas.Contains(c.AsignaturaId)))
            return Result<HorarioSeccionDto>.Fail(Error.Validation("Hay asignaturas que no son del grado."));
        var aulas = r.Celdas.Where(c => c.AulaId is not null).Select(c => c.AulaId!.Value).Distinct().ToList();
        if (aulas.Count > 0 && await db.Aulas.CountAsync(a => aulas.Contains(a.Id) && a.InstitucionId == institucion.Id, ct) != aulas.Count)
            return Result<HorarioSeccionDto>.Fail(Error.Validation("Hay aulas que no son del centro."));

        // Se prueba el horario nuevo contra el resto del año antes de guardarlo.
        var anio = await CeldasDelAnioAsync(seccion.AnioLectivoId, ct);
        var carga = await db.CargasDocentes.AsNoTracking().Where(c => c.SeccionId == seccionId)
            .ToDictionaryAsync(c => c.AsignaturaGradoId, c => c.DocenteId, ct);
        var tiempos = await db.BloquesHorario.AsNoTracking().Where(b => bloques.Contains(b.Id)).ToDictionaryAsync(b => b.Id, ct);
        var nombre = anio.FirstOrDefault(c => c.SeccionId == seccionId)?.Seccion ?? await NombreSeccionAsync(seccion, ct);
        var prueba = anio.Where(c => c.SeccionId != seccionId)
            .Concat(r.Celdas.Select(c => new Celda(seccionId, nombre, c.Dia, c.BloqueId, tiempos[c.BloqueId].Inicio, tiempos[c.BloqueId].Fin,
                c.AsignaturaId, "", carga.TryGetValue(c.AsignaturaId, out var d) ? d : null, null, c.AulaId, c.AulaId ?? seccion.AulaId, null)))
            .ToList();
        var nombres = await NombresAsync(prueba, ct);
        var choques = Choques(prueba, seccionId, nombres).ToList();
        if (choques.Count > 0)
            return Result<HorarioSeccionDto>.Fail(Error.Conflict(
                "No se guardó: " + string.Join(" ", choques.Take(ChoquesMostrados)), "choque_horario"));

        var nuevas = r.Celdas.Select(c => new HorarioClase
        {
            InstitucionId = institucion.Id, SeccionId = seccionId, Dia = c.Dia, BloqueId = c.BloqueId,
            AsignaturaGradoId = c.AsignaturaId, AulaId = c.AulaId,
        }).ToList();
        await db.Database.CreateExecutionStrategy().ExecuteAsync(async () =>
        {
            await using var tx = await db.Database.BeginTransactionAsync(ct);
            await db.HorariosClase.Where(h => h.SeccionId == seccionId).ExecuteDeleteAsync(ct);
            db.HorariosClase.AddRange(nuevas);
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
        });
        return new HorarioSeccionDto(seccionId,
            r.Celdas.Select(c => new CeldaHorarioDto(c.Dia, c.BloqueId, c.AsignaturaId, c.AulaId, carga.TryGetValue(c.AsignaturaId, out var d) ? d : null)).ToList(),
            []);
    }

    public async Task<Result<IReadOnlyList<ClaseHorarioDto>>> HorarioDocenteAsync(Guid docenteId, CancellationToken ct = default)
    {
        var (institucion, _) = await centro.ContextoAsync(ct);
        if (institucion is null) return Result<IReadOnlyList<ClaseHorarioDto>>.Fail(Error.Forbidden(EstructuraCentroService.SinCentro));
        var anio = await AnioActualAsync(institucion.Id, ct);
        if (anio is null) return Array.Empty<ClaseHorarioDto>();
        return (await DelDocenteAsync(anio.Value, docenteId, ct)).ToList();
    }

    public async Task<Result<IReadOnlyList<string>>> ChoquesAsync(CancellationToken ct = default)
    {
        var (institucion, _) = await centro.ContextoAsync(ct);
        if (institucion is null) return Result<IReadOnlyList<string>>.Fail(Error.Forbidden(EstructuraCentroService.SinCentro));
        var anio = await AnioActualAsync(institucion.Id, ct);
        if (anio is null) return Array.Empty<string>();
        var celdas = await CeldasDelAnioAsync(anio.Value, ct);
        return Choques(celdas, null).Take(50).ToList();
    }

    // ── Asistencia diaria ────────────────────────────────────────────────────

    public async Task<Result<AsistenciaDelDiaDto>> AsistenciaDelDiaAsync(DateOnly fecha, CancellationToken ct = default)
    {
        var (institucion, _) = await centro.ContextoAsync(ct);
        if (institucion is null) return Result<AsistenciaDelDiaDto>.Fail(Error.Forbidden(EstructuraCentroService.SinCentro));
        var anio = await AnioActualAsync(institucion.Id, ct);
        if (anio is null) return new AsistenciaDelDiaDto(fecha, []);

        var secciones = await (from s in db.Secciones.AsNoTracking()
                               join g in db.Grados.AsNoTracking() on s.GradoId equals g.Id
                               join u in db.Users.AsNoTracking() on s.MaestroGuiaId equals u.Id into guias
                               from u in guias.DefaultIfEmpty()
                               where s.AnioLectivoId == anio
                               orderby g.Orden, s.Jornada, s.Nombre
                               select new { s.Id, Nombre = g.Nombre + " " + s.Nombre + " (" + s.Jornada + ")", Guia = u == null ? null : u.FullName })
            .ToListAsync(ct);
        var ids = secciones.Select(s => s.Id).ToList();
        var activos = await db.Matriculas.Where(m => ids.Contains(m.SeccionId) && m.Estado == EstadosMatricula.Activa)
            .GroupBy(m => m.SeccionId).Select(g => new { g.Key, N = g.Count() }).ToDictionaryAsync(x => x.Key, x => x.N, ct);
        var tomas = await db.TomasAsistenciaDiaria.AsNoTracking().Where(t => ids.Contains(t.SeccionId) && t.Fecha == fecha)
            .ToDictionaryAsync(t => t.SeccionId, t => t.Id, ct);
        var tomaIds = tomas.Values.ToList();
        var faltas = (await (from m in db.MarcasAsistenciaDiaria.AsNoTracking()
                             join a in db.Alumnos.AsNoTracking() on m.AlumnoId equals a.Id
                             where tomaIds.Contains(m.TomaId)
                             orderby a.Nombre
                             select new { m.TomaId, a.Id, a.Nombre, m.Estado })
                .ToListAsync(ct))
            .ToLookup(x => x.TomaId);

        return new AsistenciaDelDiaDto(fecha, secciones.Select(s => new SeccionDelDiaDto(
                s.Id, s.Nombre, s.Guia, tomas.ContainsKey(s.Id), activos.GetValueOrDefault(s.Id),
                tomas.TryGetValue(s.Id, out var toma)
                    ? faltas[toma].Select(f => new AlumnoDiaDto(f.Id, f.Nombre, f.Estado)).ToList()
                    : []))
            .ToList());
    }

    public async Task<Result<ListaDiariaDto>> ListaDiariaAsync(Guid seccionId, DateOnly fecha, CancellationToken ct = default)
    {
        var (seccion, error) = await SeccionDeGuiaAsync(seccionId, ct);
        if (seccion is null) return Result<ListaDiariaDto>.Fail(error!);
        return await ArmarListaAsync(seccion, fecha, ct);
    }

    public async Task<Result<ListaDiariaDto>> GuardarListaDiariaAsync(Guid seccionId, ListaDiariaRequest r, CancellationToken ct = default)
    {
        var (seccion, error) = await SeccionDeGuiaAsync(seccionId, ct);
        if (seccion is null) return Result<ListaDiariaDto>.Fail(error!);
        if (r.Fecha > clock.Today) return Result<ListaDiariaDto>.Fail(Error.Validation("No se pasa lista de días que no han llegado."));
        var anio = await db.AniosLectivos.AsNoTracking().FirstAsync(a => a.Id == seccion.AnioLectivoId, ct);
        if (r.Fecha < anio.Inicio || r.Fecha > anio.Fin) return Result<ListaDiariaDto>.Fail(Error.Validation("La fecha no es del año lectivo."));
        if (r.Marcas.Any(m => m.Estado is not ("A" or "T" or "J"))) return Result<ListaDiariaDto>.Fail(Error.Validation("Estado desconocido."));
        if (r.Marcas.Select(m => m.AlumnoId).Distinct().Count() != r.Marcas.Count)
            return Result<ListaDiariaDto>.Fail(Error.Validation("Un alumno aparece dos veces."));
        var alumnos = await db.Matriculas.Where(m => m.SeccionId == seccionId && m.Estado == EstadosMatricula.Activa)
            .Select(m => m.AlumnoId).ToListAsync(ct);
        if (r.Marcas.Any(m => !alumnos.Contains(m.AlumnoId)))
            return Result<ListaDiariaDto>.Fail(Error.Validation("Hay alumnos que no están en la sección."));

        var yo = currentUser.RequireUserId();
        // Las faltas que ya estaban no se vuelven a avisar al corregir la lista.
        var antes = await (from m in db.MarcasAsistenciaDiaria.AsNoTracking()
                           join t in db.TomasAsistenciaDiaria.AsNoTracking() on m.TomaId equals t.Id
                           where t.SeccionId == seccionId && t.Fecha == r.Fecha
                           select new { m.AlumnoId, m.Estado })
            .ToDictionaryAsync(m => m.AlumnoId, m => m.Estado, ct);
        await db.Database.CreateExecutionStrategy().ExecuteAsync(async () =>
        {
            await using var tx = await db.Database.BeginTransactionAsync(ct);
            var toma = await db.TomasAsistenciaDiaria.FirstOrDefaultAsync(t => t.SeccionId == seccionId && t.Fecha == r.Fecha, ct);
            if (toma is null)
            {
                toma = new TomaAsistenciaDiaria { InstitucionId = seccion.InstitucionId, SeccionId = seccionId, Fecha = r.Fecha };
                db.TomasAsistenciaDiaria.Add(toma);
            }
            toma.TomadaPor = yo;
            toma.TomadaEn = clock.Now;
            await db.SaveChangesAsync(ct);
            await db.MarcasAsistenciaDiaria.Where(m => m.TomaId == toma.Id).ExecuteDeleteAsync(ct);
            db.MarcasAsistenciaDiaria.AddRange(r.Marcas.Select(m => new MarcaAsistenciaDiaria
            {
                InstitucionId = seccion.InstitucionId, TomaId = toma.Id, AlumnoId = m.AlumnoId, Estado = m.Estado,
            }));
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
        });
        if (r.Fecha == clock.Today) await AvisarFaltasAsync(r.Marcas.Where(m => m.Estado is "A" or "T" && antes.GetValueOrDefault(m.AlumnoId) != m.Estado).ToList(), ct);
        return await ArmarListaAsync(seccion, r.Fecha, ct);
    }

    // ── Conducta ─────────────────────────────────────────────────────────────

    public async Task<Result<ConductaSeccionDto>> ConductaAsync(Guid seccionId, int parcial, CancellationToken ct = default)
    {
        if (parcial is < 1 or > 4) return Result<ConductaSeccionDto>.Fail(Error.Validation("Los parciales van del I al IV."));
        var (seccion, error) = await SeccionDeGuiaAsync(seccionId, ct);
        if (seccion is null) return Result<ConductaSeccionDto>.Fail(error!);
        return await ArmarConductaAsync(seccion, parcial, ct);
    }

    public async Task<Result<ConductaSeccionDto>> GuardarConductaAsync(Guid seccionId, ConductaRequest r, CancellationToken ct = default)
    {
        if (r.Parcial is < 1 or > 4) return Result<ConductaSeccionDto>.Fail(Error.Validation("Los parciales van del I al IV."));
        var (seccion, error) = await SeccionDeGuiaAsync(seccionId, ct);
        if (seccion is null) return Result<ConductaSeccionDto>.Fail(error!);
        if (r.Notas.Any(n => n.Nota is not null && !NotasConducta.Todas.Contains(n.Nota)))
            return Result<ConductaSeccionDto>.Fail(Error.Validation("La conducta va de A a E."));
        if (r.Notas.Select(n => n.AlumnoId).Distinct().Count() != r.Notas.Count)
            return Result<ConductaSeccionDto>.Fail(Error.Validation("Un alumno aparece dos veces."));
        var alumnos = await db.Matriculas.Where(m => m.SeccionId == seccionId && m.Estado == EstadosMatricula.Activa)
            .Select(m => m.AlumnoId).ToListAsync(ct);
        if (r.Notas.Any(n => !alumnos.Contains(n.AlumnoId)))
            return Result<ConductaSeccionDto>.Fail(Error.Validation("Hay alumnos que no están en la sección."));

        var yo = currentUser.RequireUserId();
        var ids = r.Notas.Select(n => n.AlumnoId).ToList();
        var actuales = await db.Conductas.Where(c => c.SeccionId == seccionId && c.Parcial == r.Parcial && ids.Contains(c.AlumnoId))
            .ToDictionaryAsync(c => c.AlumnoId, ct);
        foreach (var n in r.Notas)
        {
            actuales.TryGetValue(n.AlumnoId, out var fila);
            if (n.Nota is null)
            {
                if (fila is not null) db.Conductas.Remove(fila);
                continue;
            }
            fila ??= db.Conductas.Add(new ConductaParcial
            {
                InstitucionId = seccion.InstitucionId, SeccionId = seccionId, AlumnoId = n.AlumnoId, Parcial = r.Parcial,
            }).Entity;
            fila.Nota = n.Nota;
            fila.PuestaPor = yo;
        }
        await db.SaveChangesAsync(ct);
        return await ArmarConductaAsync(seccion, r.Parcial, ct);
    }

    private async Task<ConductaSeccionDto> ArmarConductaAsync(Seccion seccion, int parcial, CancellationToken ct)
    {
        var notas = await db.Conductas.AsNoTracking().Where(c => c.SeccionId == seccion.Id && c.Parcial == parcial)
            .ToDictionaryAsync(c => c.AlumnoId, c => c.Nota, ct);
        var alumnos = await (from m in db.Matriculas.AsNoTracking()
                             join a in db.Alumnos.AsNoTracking() on m.AlumnoId equals a.Id
                             where m.SeccionId == seccion.Id && m.Estado == EstadosMatricula.Activa
                             orderby a.Nombre
                             select new { a.Id, a.Nombre })
            .ToListAsync(ct);
        return new ConductaSeccionDto(seccion.Id, await NombreSeccionAsync(seccion, ct), parcial,
            alumnos.Select(a => new ConductaAlumnoDto(a.Id, a.Nombre, notas.GetValueOrDefault(a.Id))).ToList());
    }

    // ── Para la app del docente y del padre ──────────────────────────────────

    /// <summary>Clases del docente en el año, ordenadas por día y hora.</summary>
    internal async Task<IReadOnlyList<ClaseHorarioDto>> DelDocenteAsync(Guid anioId, Guid docenteId, CancellationToken ct) =>
        (await CeldasDelAnioAsync(anioId, ct)).Where(c => c.DocenteId == docenteId)
        .OrderBy(c => c.Dia).ThenBy(c => c.Inicio)
        .Select(c => new ClaseHorarioDto(c.Dia, c.Inicio, c.Fin, c.Asignatura, c.Seccion, c.Aula)).ToList();

    /// <summary>Clases de una sección, ordenadas por día y hora.</summary>
    internal async Task<IReadOnlyList<ClaseHorarioDto>> DeSeccionAsync(Guid anioId, Guid seccionId, CancellationToken ct) =>
        (await CeldasDelAnioAsync(anioId, ct)).Where(c => c.SeccionId == seccionId)
        .OrderBy(c => c.Dia).ThenBy(c => c.Inicio)
        .Select(c => new ClaseHorarioDto(c.Dia, c.Inicio, c.Fin, c.Asignatura, c.Seccion, c.Aula)).ToList();

    // ── Apoyo ────────────────────────────────────────────────────────────────

    private sealed record Celda(
        Guid SeccionId, string Seccion, int Dia, Guid BloqueId, TimeOnly Inicio, TimeOnly Fin,
        Guid AsignaturaId, string Asignatura, Guid? DocenteId, string? Docente, Guid? AulaPropia, Guid? AulaId, string? Aula);

    /// <summary>Todas las clases del año con su docente (de la carga) y su aula efectiva.</summary>
    private async Task<List<Celda>> CeldasDelAnioAsync(Guid anioId, CancellationToken ct)
    {
        var filas = await (from h in db.HorariosClase.AsNoTracking()
                           join s in db.Secciones.AsNoTracking() on h.SeccionId equals s.Id
                           join g in db.Grados.AsNoTracking() on s.GradoId equals g.Id
                           join b in db.BloquesHorario.AsNoTracking() on h.BloqueId equals b.Id
                           join a in db.AsignaturasGrado.AsNoTracking() on h.AsignaturaGradoId equals a.Id
                           join c in db.CargasDocentes.AsNoTracking() on new { h.SeccionId, h.AsignaturaGradoId } equals new { c.SeccionId, c.AsignaturaGradoId } into cargas
                           from c in cargas.DefaultIfEmpty()
                           where s.AnioLectivoId == anioId
                           select new
                           {
                               h.SeccionId, Seccion = g.Nombre + " " + s.Nombre, h.Dia, h.BloqueId, b.Inicio, b.Fin,
                               h.AsignaturaGradoId, Asignatura = a.Nombre, DocenteId = c == null ? (Guid?)null : c.DocenteId,
                               AulaPropia = h.AulaId, AulaId = h.AulaId ?? s.AulaId,
                           })
            .ToListAsync(ct);
        var ids = filas.Where(f => f.AulaId is not null).Select(f => f.AulaId!.Value).Distinct().ToList();
        var aulas = await db.Aulas.AsNoTracking().Where(a => ids.Contains(a.Id)).ToDictionaryAsync(a => a.Id, a => a.Nombre, ct);
        var docentes = filas.Where(f => f.DocenteId is not null).Select(f => f.DocenteId!.Value).Distinct().ToList();
        var nombres = await db.Users.AsNoTracking().Where(u => docentes.Contains(u.Id)).ToDictionaryAsync(u => u.Id, u => u.FullName, ct);
        return filas.Select(f => new Celda(f.SeccionId, f.Seccion, f.Dia, f.BloqueId, f.Inicio, f.Fin, f.AsignaturaGradoId, f.Asignatura,
                f.DocenteId, f.DocenteId is { } d ? nombres.GetValueOrDefault(d) : null, f.AulaPropia, f.AulaId,
                f.AulaId is { } au ? aulas.GetValueOrDefault(au) : null))
            .ToList();
    }

    private async Task<(Dictionary<Guid, string> Docentes, Dictionary<Guid, string> Aulas)> NombresAsync(List<Celda> celdas, CancellationToken ct)
    {
        var docentes = celdas.Where(c => c.DocenteId is not null).Select(c => c.DocenteId!.Value).Distinct().ToList();
        var aulas = celdas.Where(c => c.AulaId is not null).Select(c => c.AulaId!.Value).Distinct().ToList();
        return (await db.Users.AsNoTracking().Where(u => docentes.Contains(u.Id)).ToDictionaryAsync(u => u.Id, u => u.FullName, ct),
                await db.Aulas.AsNoTracking().Where(a => aulas.Contains(a.Id)).ToDictionaryAsync(a => a.Id, a => a.Nombre, ct));
    }

    /// <summary>Choques del año; con <paramref name="seccion"/>, solo los que la involucran.</summary>
    private static IEnumerable<string> Choques(List<Celda> celdas, Guid? seccion,
        (Dictionary<Guid, string> Docentes, Dictionary<Guid, string> Aulas)? nombres = null)
    {
        foreach (var dia in celdas.GroupBy(c => c.Dia))
        {
            var lista = dia.OrderBy(c => c.Inicio).ToList();
            for (var i = 0; i < lista.Count; i++)
            for (var j = i + 1; j < lista.Count && lista[j].Inicio < lista[i].Fin; j++)
            {
                var (a, b) = (lista[i], lista[j]);
                if (a.SeccionId == b.SeccionId) continue;
                if (seccion is { } s && a.SeccionId != s && b.SeccionId != s) continue;
                var cuando = $"El {Dias[a.Dia]} a las {a.Inicio:HH\\:mm}";
                if (a.DocenteId is { } da && da == b.DocenteId)
                    yield return $"{cuando}, {a.Docente ?? nombres?.Docentes.GetValueOrDefault(da) ?? "un docente"} tendría {a.Seccion} y {b.Seccion} a la vez.";
                if (a.AulaId is { } aa && aa == b.AulaId)
                    yield return $"{cuando}, el aula {a.Aula ?? nombres?.Aulas.GetValueOrDefault(aa) ?? ""} estaría ocupada por {a.Seccion} y {b.Seccion}.";
            }
        }
    }

    private async Task<string> NombreSeccionAsync(Seccion s, CancellationToken ct) =>
        (await db.Grados.Where(g => g.Id == s.GradoId).Select(g => g.Nombre).FirstAsync(ct)) + " " + s.Nombre;

    private Task<Guid?> AnioActualAsync(Guid institucionId, CancellationToken ct) =>
        db.AniosLectivos.Where(a => a.InstitucionId == institucionId && a.Actual).Select(a => (Guid?)a.Id).FirstOrDefaultAsync(ct);

    /// <summary>La sección, si quien llama es su maestro guía y está en el año actual de un centro activo.</summary>
    private async Task<(Seccion? Seccion, Error? Error)> SeccionDeGuiaAsync(Guid seccionId, CancellationToken ct)
    {
        var yo = currentUser.RequireUserId();
        var seccion = await (from s in db.Secciones.AsNoTracking()
                             join a in db.AniosLectivos.AsNoTracking() on s.AnioLectivoId equals a.Id
                             join i in db.Instituciones.AsNoTracking() on s.InstitucionId equals i.Id
                             where s.Id == seccionId && s.MaestroGuiaId == yo && a.Actual && i.Activa
                             select s).FirstOrDefaultAsync(ct);
        return seccion is null ? (null, Error.NotFound("La sección")) : (seccion, null);
    }

    /// <summary>A la familia de cada alumno que faltó o llegó tarde hoy.</summary>
    private async Task AvisarFaltasAsync(List<MarcaDiariaRequest> nuevas, CancellationToken ct)
    {
        if (nuevas.Count == 0) return;
        var ids = nuevas.Select(m => m.AlumnoId).ToList();
        var familias = (await db.VinculosFamiliares.AsNoTracking().Where(v => ids.Contains(v.AlumnoId))
            .Select(v => new { v.AlumnoId, v.UsuarioId }).ToListAsync(ct)).ToLookup(v => v.AlumnoId, v => v.UsuarioId);
        var nombres = await db.Alumnos.AsNoTracking().Where(a => ids.Contains(a.Id)).ToDictionaryAsync(a => a.Id, a => a.Nombre, ct);
        foreach (var m in nuevas.Where(m => familias[m.AlumnoId].Any()))
        {
            var nombre = nombres[m.AlumnoId];
            avisos.Encolar(new AvisoPush(familias[m.AlumnoId].ToList(),
                m.Estado == "A" ? $"{nombre} no llegó hoy a clases" : $"{nombre} llegó tarde hoy",
                "Lo registró su maestro guía en la lista del día.", "/familia"));
        }
    }

    private async Task<ListaDiariaDto> ArmarListaAsync(Seccion seccion, DateOnly fecha, CancellationToken ct)
    {
        var toma = await db.TomasAsistenciaDiaria.AsNoTracking().FirstOrDefaultAsync(t => t.SeccionId == seccion.Id && t.Fecha == fecha, ct);
        var marcas = toma is null
            ? []
            : await db.MarcasAsistenciaDiaria.AsNoTracking().Where(m => m.TomaId == toma.Id).ToDictionaryAsync(m => m.AlumnoId, m => m.Estado, ct);
        var alumnos = await (from m in db.Matriculas.AsNoTracking()
                             join a in db.Alumnos.AsNoTracking() on m.AlumnoId equals a.Id
                             where m.SeccionId == seccion.Id && m.Estado == EstadosMatricula.Activa
                             orderby a.Nombre
                             select new { a.Id, a.Nombre })
            .ToListAsync(ct);
        // Con excusa del centro y sin lista todavía, el alumno aparece ya como justificado.
        var excusas = await ConvivenciaService.DelDiaAsync(db, alumnos.Select(a => a.Id).ToList(), fecha, ct);
        return new ListaDiariaDto(seccion.Id, await NombreSeccionAsync(seccion, ct), fecha, toma is not null,
            alumnos.Select(a => new AlumnoDiaDto(a.Id, a.Nombre,
                    toma is null ? (excusas.ContainsKey(a.Id) ? "J" : null) : marcas.GetValueOrDefault(a.Id),
                    excusas.GetValueOrDefault(a.Id)))
                .ToList());
    }

    private static BloqueDto ADto(BloqueHorario b) => new(b.Id, b.Jornada, b.Orden, b.Inicio, b.Fin, b.EsReceso);
}
