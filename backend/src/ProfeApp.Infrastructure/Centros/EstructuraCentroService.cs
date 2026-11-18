using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;
using ProfeApp.Domain.Centros;
using ProfeApp.Domain.Cobros;
using ProfeApp.Domain.Common;
using ProfeApp.Domain.Instituciones;
using ProfeApp.Infrastructure.Identity;
using ProfeApp.Infrastructure.Instituciones;
using ProfeApp.Infrastructure.Persistence;

namespace ProfeApp.Infrastructure.Centros;

/// <summary>
/// La organización académica de un centro. Todo se filtra por la institución de quien
/// llama: un centro nunca ve ni toca filas de otro.
/// </summary>
public sealed class EstructuraCentroService(
    AppDbContext db,
    UserManager<AppUser> users,
    ICurrentUser currentUser,
    AdminService admin,
    IClock clock) : IEstructuraCentroService
{
    internal const string SinCentro = "Tu cuenta no administra un centro.";

    // ── Lectura ──────────────────────────────────────────────────────────────

    public async Task<Result<EstructuraDto>> ObtenerAsync(Guid? anioId, CancellationToken ct = default)
    {
        var (centro, yo) = await ContextoAsync(ct);
        if (centro is null) return Result<EstructuraDto>.Fail(Error.Forbidden(SinCentro));
        var id = centro.Id;

        var anios = await db.AniosLectivos.AsNoTracking().Where(a => a.InstitucionId == id)
            .OrderByDescending(a => a.Anio).ToListAsync(ct);
        var anio = anios.FirstOrDefault(a => a.Id == anioId) ?? anios.FirstOrDefault(a => a.Actual) ?? anios.FirstOrDefault();

        var grados = await db.Grados.AsNoTracking().Where(g => g.InstitucionId == id).ToListAsync(ct);
        var asignaturas = (await db.AsignaturasGrado.AsNoTracking().Where(a => a.InstitucionId == id).ToListAsync(ct))
            .ToLookup(a => a.GradoId);
        var aulas = await db.Aulas.AsNoTracking().Where(a => a.InstitucionId == id).OrderBy(a => a.Nombre).ToListAsync(ct);

        var secciones = anio is null
            ? []
            : await db.Secciones.AsNoTracking().Where(s => s.AnioLectivoId == anio.Id).ToListAsync(ct);
        var idsSecciones = secciones.Select(s => s.Id).ToList();
        var carga = (await db.CargasDocentes.AsNoTracking().Where(c => idsSecciones.Contains(c.SeccionId)).ToListAsync(ct))
            .ToLookup(c => c.SeccionId);
        var matriculados = await db.Matriculas
            .Where(m => idsSecciones.Contains(m.SeccionId) && m.Estado == EstadosMatricula.Activa)
            .GroupBy(m => m.SeccionId).Select(g => new { g.Key, N = g.Count() })
            .ToDictionaryAsync(x => x.Key, x => x.N, ct);

        var ordenGrado = grados.ToDictionary(g => g.Id, g => (g.Orden, g.Nombre));
        var docentes = await DocentesQuery(id).OrderBy(u => u.FullName)
            .Select(u => new DocenteBreveDto(u.Id, u.FullName, u.IsActive)).ToListAsync(ct);

        return new EstructuraDto(
            Cargos.Administra(yo!.Cargo),
            anios.Select(ADto).ToList(),
            anio?.Id,
            grados.OrderBy(g => g.Orden).ThenBy(g => g.Nombre)
                .Select(g => ADto(g, asignaturas[g.Id])).ToList(),
            aulas.Select(a => new AulaDto(a.Id, a.Nombre, a.Capacidad)).ToList(),
            secciones
                .OrderBy(s => ordenGrado.GetValueOrDefault(s.GradoId).Orden).ThenBy(s => s.Jornada).ThenBy(s => s.Nombre)
                .Select(s => ADto(s, carga[s.Id], matriculados.GetValueOrDefault(s.Id))).ToList(),
            docentes);
    }

    // ── Año lectivo ──────────────────────────────────────────────────────────

    public async Task<Result<AnioLectivoDto>> GuardarAnioAsync(Guid? id, AnioLectivoRequest r, CancellationToken ct = default)
    {
        var (centro, error) = await EditorAsync(ct);
        if (centro is null) return Result<AnioLectivoDto>.Fail(error!);

        if (r.Anio is < 2000 or > 2100) return Result<AnioLectivoDto>.Fail(Error.Validation("El año no es válido."));
        if (r.Fin <= r.Inicio) return Result<AnioLectivoDto>.Fail(Error.Validation("El fin debe ser después del inicio."));
        var cierres = (r.Cierres ?? []).Concat(Enumerable.Repeat<DateOnly?>(null, 4)).Take(4).ToList();
        if ((r.Cierres?.Count ?? 0) > 4) return Result<AnioLectivoDto>.Fail(Error.Validation("Son cuatro parciales."));
        DateOnly? previo = null;
        foreach (var c in cierres.Where(c => c is not null))
        {
            if (c < r.Inicio || c > r.Fin)
                return Result<AnioLectivoDto>.Fail(Error.Validation("Cada cierre de parcial va dentro del año lectivo."));
            if (previo is not null && c <= previo)
                return Result<AnioLectivoDto>.Fail(Error.Validation("Los cierres van en orden: I, II, III y IV."));
            previo = c;
        }

        var anio = id is { } aid
            ? await db.AniosLectivos.FirstOrDefaultAsync(a => a.Id == aid && a.InstitucionId == centro.Id, ct)
            : new AnioLectivo { InstitucionId = centro.Id };
        if (anio is null) return Result<AnioLectivoDto>.Fail(Error.NotFound("El año lectivo"));
        if (await db.AniosLectivos.AnyAsync(a => a.InstitucionId == centro.Id && a.Anio == r.Anio && a.Id != anio.Id, ct))
            return Result<AnioLectivoDto>.Fail(Error.Conflict($"Ya existe el año lectivo {r.Anio}."));

        var primero = id is null && !await db.AniosLectivos.AnyAsync(a => a.InstitucionId == centro.Id, ct);
        anio.Anio = r.Anio;
        anio.Inicio = r.Inicio;
        anio.Fin = r.Fin;
        (anio.CierreParcial1, anio.CierreParcial2, anio.CierreParcial3, anio.CierreParcial4) = (cierres[0], cierres[1], cierres[2], cierres[3]);
        // El primero es el actual; el actual deja de serlo sólo al marcar otro.
        anio.Actual = r.Actual || primero || anio.Actual;

        if (anio.Actual)
            // Antes de guardar: el índice único no admite dos años actuales ni por un instante.
            await db.AniosLectivos.Where(a => a.InstitucionId == centro.Id && a.Actual && a.Id != anio.Id)
                .ExecuteUpdateAsync(s => s.SetProperty(a => a.Actual, false), ct);
        if (id is null) db.AniosLectivos.Add(anio);
        await db.SaveChangesAsync(ct);
        return ADto(anio);
    }

    // ── Grados y asignaturas ─────────────────────────────────────────────────

    public async Task<Result<GradoDto>> GuardarGradoAsync(Guid? id, GradoRequest r, CancellationToken ct = default)
    {
        var (centro, error) = await EditorAsync(ct);
        if (centro is null) return Result<GradoDto>.Fail(error!);
        if (!NivelesEducativos.Todos.Contains(r.Nivel)) return Result<GradoDto>.Fail(Error.Validation("Nivel desconocido."));
        var nombre = Limpio(r.Nombre);
        if (nombre is null || nombre.Length > 80) return Result<GradoDto>.Fail(Error.Validation("El nombre del grado es obligatorio (hasta 80 caracteres)."));

        var grado = id is { } gid
            ? await db.Grados.FirstOrDefaultAsync(g => g.Id == gid && g.InstitucionId == centro.Id, ct)
            : new Grado { InstitucionId = centro.Id };
        if (grado is null) return Result<GradoDto>.Fail(Error.NotFound("El grado"));
        if (await db.Grados.AnyAsync(g => g.InstitucionId == centro.Id && g.Nombre == nombre && g.Id != grado.Id, ct))
            return Result<GradoDto>.Fail(Error.Conflict($"Ya existe el grado «{nombre}»."));

        grado.Nombre = nombre;
        if (id is null || grado.Nivel != r.Nivel || r.Orden is not null)
            grado.Orden = r.Orden ?? await SiguienteOrdenAsync(centro.Id, r.Nivel, ct);
        grado.Nivel = r.Nivel;
        if (id is null) db.Grados.Add(grado);
        await db.SaveChangesAsync(ct);

        var asignaturas = await db.AsignaturasGrado.AsNoTracking().Where(a => a.GradoId == grado.Id).ToListAsync(ct);
        return ADto(grado, asignaturas);
    }

    /// <summary>Grados de Honduras por nivel. Los nombres se pueden cambiar después.</summary>
    private static readonly Dictionary<string, string[]> GradosPorNivel = new()
    {
        [NivelesEducativos.Prebasica] = ["Prekínder", "Kínder", "Preparatoria"],
        [NivelesEducativos.Basica] = ["1.º grado", "2.º grado", "3.º grado", "4.º grado", "5.º grado", "6.º grado", "7.º grado", "8.º grado", "9.º grado"],
        [NivelesEducativos.Media] = ["10.º grado", "11.º grado", "12.º grado"],
    };

    public async Task<Result<int>> PlantillaGradosAsync(PlantillaGradosRequest r, CancellationToken ct = default)
    {
        var (centro, error) = await EditorAsync(ct);
        if (centro is null) return Result<int>.Fail(error!);
        if (r.Niveles.Count == 0 || r.Niveles.Any(n => !NivelesEducativos.Todos.Contains(n)))
            return Result<int>.Fail(Error.Validation("Elige al menos un nivel."));

        var existentes = (await db.Grados.Where(g => g.InstitucionId == centro.Id).Select(g => g.Nombre).ToListAsync(ct)).ToHashSet();
        var creados = 0;
        foreach (var nivel in NivelesEducativos.Todos.Where(r.Niveles.Contains))
        {
            var orden = BaseOrden(nivel);
            foreach (var nombre in GradosPorNivel[nivel])
            {
                orden++;
                if (!existentes.Add(nombre)) continue;
                db.Grados.Add(new Grado { InstitucionId = centro.Id, Nivel = nivel, Nombre = nombre, Orden = orden });
                creados++;
            }
        }
        await db.SaveChangesAsync(ct);
        return creados;
    }

    public async Task<Result> EliminarGradoAsync(Guid id, CancellationToken ct = default)
    {
        var (centro, error) = await EditorAsync(ct);
        if (centro is null) return Result.Fail(error!);
        var grado = await db.Grados.FirstOrDefaultAsync(g => g.Id == id && g.InstitucionId == centro.Id, ct);
        if (grado is null) return Result.Fail(Error.NotFound("El grado"));
        if (await db.Secciones.AnyAsync(s => s.GradoId == id, ct))
            return Result.Fail(Error.Conflict("El grado tiene secciones. Elimínalas primero.", "grado_con_secciones"));
        db.Grados.Remove(grado);
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    public async Task<Result<int>> AgregarAsignaturasAsync(AgregarAsignaturasRequest r, CancellationToken ct = default)
    {
        var (centro, error) = await EditorAsync(ct);
        if (centro is null) return Result<int>.Fail(error!);
        var nombres = r.Nombres.Select(Limpio).OfType<string>().Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        if (nombres.Count == 0) return Result<int>.Fail(Error.Validation("Escribe al menos una asignatura."));
        if (nombres.Any(n => n.Length > 120)) return Result<int>.Fail(Error.Validation("Cada asignatura admite hasta 120 caracteres."));
        if (nombres.Count > 40 || r.GradoIds.Count > 60) return Result<int>.Fail(Error.Validation("Demasiadas a la vez."));

        var grados = await db.Grados.Where(g => g.InstitucionId == centro.Id && r.GradoIds.Contains(g.Id)).Select(g => g.Id).ToListAsync(ct);
        if (grados.Count == 0 || grados.Count != r.GradoIds.Distinct().Count())
            return Result<int>.Fail(Error.Validation("Elige grados de tu centro."));

        var actuales = (await db.AsignaturasGrado.Where(a => grados.Contains(a.GradoId)).ToListAsync(ct)).ToLookup(a => a.GradoId);
        var creadas = 0;
        foreach (var grado in grados)
        {
            var ya = actuales[grado].Select(a => a.Nombre).ToHashSet(StringComparer.OrdinalIgnoreCase);
            var orden = actuales[grado].Select(a => a.Orden).DefaultIfEmpty(0).Max();
            foreach (var nombre in nombres.Where(ya.Add))
            {
                db.AsignaturasGrado.Add(new AsignaturaGrado { InstitucionId = centro.Id, GradoId = grado, Nombre = nombre, Orden = ++orden });
                creadas++;
            }
        }
        await db.SaveChangesAsync(ct);
        return creadas;
    }

    public async Task<Result> RenombrarAsignaturaAsync(Guid id, NombreRequest r, CancellationToken ct = default)
    {
        var (centro, error) = await EditorAsync(ct);
        if (centro is null) return Result.Fail(error!);
        var nombre = Limpio(r.Nombre);
        if (nombre is null || nombre.Length > 120) return Result.Fail(Error.Validation("El nombre es obligatorio (hasta 120 caracteres)."));
        var asignatura = await db.AsignaturasGrado.FirstOrDefaultAsync(a => a.Id == id && a.InstitucionId == centro.Id, ct);
        if (asignatura is null) return Result.Fail(Error.NotFound("La asignatura"));
        if (await db.AsignaturasGrado.AnyAsync(a => a.GradoId == asignatura.GradoId && a.Nombre == nombre && a.Id != id, ct))
            return Result.Fail(Error.Conflict($"El grado ya tiene «{nombre}»."));
        asignatura.Nombre = nombre;
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    public async Task<Result> EliminarAsignaturaAsync(Guid id, CancellationToken ct = default)
    {
        var (centro, error) = await EditorAsync(ct);
        if (centro is null) return Result.Fail(error!);
        var asignatura = await db.AsignaturasGrado.FirstOrDefaultAsync(a => a.Id == id && a.InstitucionId == centro.Id, ct);
        if (asignatura is null) return Result.Fail(Error.NotFound("La asignatura"));
        // Su carga docente se va con ella (cascada en la base).
        db.AsignaturasGrado.Remove(asignatura);
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    // ── Aulas ────────────────────────────────────────────────────────────────

    public async Task<Result<AulaDto>> GuardarAulaAsync(Guid? id, AulaRequest r, CancellationToken ct = default)
    {
        var (centro, error) = await EditorAsync(ct);
        if (centro is null) return Result<AulaDto>.Fail(error!);
        var nombre = Limpio(r.Nombre);
        if (nombre is null || nombre.Length > 80) return Result<AulaDto>.Fail(Error.Validation("El nombre del aula es obligatorio (hasta 80 caracteres)."));
        if (r.Capacidad is < 1 or > 500) return Result<AulaDto>.Fail(Error.Validation("La capacidad va de 1 a 500."));

        var aula = id is { } aid
            ? await db.Aulas.FirstOrDefaultAsync(a => a.Id == aid && a.InstitucionId == centro.Id, ct)
            : new Aula { InstitucionId = centro.Id };
        if (aula is null) return Result<AulaDto>.Fail(Error.NotFound("El aula"));
        if (await db.Aulas.AnyAsync(a => a.InstitucionId == centro.Id && a.Nombre == nombre && a.Id != aula.Id, ct))
            return Result<AulaDto>.Fail(Error.Conflict($"Ya existe el aula «{nombre}»."));
        aula.Nombre = nombre;
        aula.Capacidad = r.Capacidad;
        if (id is null) db.Aulas.Add(aula);
        await db.SaveChangesAsync(ct);
        return new AulaDto(aula.Id, aula.Nombre, aula.Capacidad);
    }

    public async Task<Result> EliminarAulaAsync(Guid id, CancellationToken ct = default)
    {
        var (centro, error) = await EditorAsync(ct);
        if (centro is null) return Result.Fail(error!);
        var aula = await db.Aulas.FirstOrDefaultAsync(a => a.Id == id && a.InstitucionId == centro.Id, ct);
        if (aula is null) return Result.Fail(Error.NotFound("El aula"));
        // Las secciones que la usaban quedan sin aula (SET NULL en la base).
        db.Aulas.Remove(aula);
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    // ── Secciones y carga docente ────────────────────────────────────────────

    public async Task<Result<SeccionDto>> GuardarSeccionAsync(Guid? id, SeccionRequest r, CancellationToken ct = default)
    {
        var (centro, error) = await EditorAsync(ct);
        if (centro is null) return Result<SeccionDto>.Fail(error!);
        var nombre = Limpio(r.Nombre)?.ToUpperInvariant();
        if (nombre is null || nombre.Length > 20) return Result<SeccionDto>.Fail(Error.Validation("La sección es obligatoria (hasta 20 caracteres)."));
        if (!Jornadas.Todas.Contains(r.Jornada)) return Result<SeccionDto>.Fail(Error.Validation("Jornada desconocida."));
        if (r.Cupo is < 1 or > 200) return Result<SeccionDto>.Fail(Error.Validation("El cupo va de 1 a 200."));
        if (!await db.AniosLectivos.AnyAsync(a => a.Id == r.AnioLectivoId && a.InstitucionId == centro.Id, ct))
            return Result<SeccionDto>.Fail(Error.Validation("El año lectivo no es de tu centro."));
        if (!await db.Grados.AnyAsync(g => g.Id == r.GradoId && g.InstitucionId == centro.Id, ct))
            return Result<SeccionDto>.Fail(Error.Validation("El grado no es de tu centro."));
        if (r.AulaId is { } aula && !await db.Aulas.AnyAsync(a => a.Id == aula && a.InstitucionId == centro.Id, ct))
            return Result<SeccionDto>.Fail(Error.Validation("El aula no es de tu centro."));
        if (r.MaestroGuiaId is { } guia && !await DocentesQuery(centro.Id).AnyAsync(u => u.Id == guia, ct))
            return Result<SeccionDto>.Fail(Error.Validation("El maestro guía debe ser un docente del centro."));

        var seccion = id is { } sid
            ? await db.Secciones.FirstOrDefaultAsync(s => s.Id == sid && s.InstitucionId == centro.Id, ct)
            : new Seccion { InstitucionId = centro.Id };
        if (seccion is null) return Result<SeccionDto>.Fail(Error.NotFound("La sección"));
        if (id is not null && seccion.AnioLectivoId != r.AnioLectivoId && await db.Matriculas.AnyAsync(m => m.SeccionId == seccion.Id, ct))
            return Result<SeccionDto>.Fail(Error.Conflict("La sección tiene alumnos matriculados: no se cambia de año."));
        if (id is not null && seccion.GradoId != r.GradoId && await db.CargasDocentes.AnyAsync(c => c.SeccionId == seccion.Id, ct))
            return Result<SeccionDto>.Fail(Error.Conflict("La sección ya tiene carga docente; para cambiarla de grado, quita primero la carga."));
        if (await db.Secciones.AnyAsync(s => s.AnioLectivoId == r.AnioLectivoId && s.GradoId == r.GradoId
                && s.Jornada == r.Jornada && s.Nombre == nombre && s.Id != seccion.Id, ct))
            return Result<SeccionDto>.Fail(Error.Conflict($"Ya existe la sección {nombre} de ese grado en esa jornada."));

        seccion.AnioLectivoId = r.AnioLectivoId;
        seccion.GradoId = r.GradoId;
        seccion.Nombre = nombre;
        seccion.Jornada = r.Jornada;
        seccion.Cupo = r.Cupo;
        seccion.AulaId = r.AulaId;
        seccion.MaestroGuiaId = r.MaestroGuiaId;
        if (id is null) db.Secciones.Add(seccion);
        await db.SaveChangesAsync(ct);

        var carga = await db.CargasDocentes.AsNoTracking().Where(c => c.SeccionId == seccion.Id).ToListAsync(ct);
        return ADto(seccion, carga);
    }

    public async Task<Result> EliminarSeccionAsync(Guid id, CancellationToken ct = default)
    {
        var (centro, error) = await EditorAsync(ct);
        if (centro is null) return Result.Fail(error!);
        var seccion = await db.Secciones.FirstOrDefaultAsync(s => s.Id == id && s.InstitucionId == centro.Id, ct);
        if (seccion is null) return Result.Fail(Error.NotFound("La sección"));
        if (await db.Matriculas.AnyAsync(m => m.SeccionId == id, ct))
            return Result.Fail(Error.Conflict("La sección tiene alumnos matriculados. Muévelos a otra sección primero.", "seccion_con_alumnos"));
        db.Secciones.Remove(seccion);
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    public async Task<Result<SeccionDto>> GuardarCargaAsync(Guid seccionId, CargaRequest r, CancellationToken ct = default)
    {
        var (centro, error) = await EditorAsync(ct);
        if (centro is null) return Result<SeccionDto>.Fail(error!);
        var seccion = await db.Secciones.AsNoTracking().FirstOrDefaultAsync(s => s.Id == seccionId && s.InstitucionId == centro.Id, ct);
        if (seccion is null) return Result<SeccionDto>.Fail(Error.NotFound("La sección"));

        if (r.Asignaciones.Select(a => a.AsignaturaId).Distinct().Count() != r.Asignaciones.Count)
            return Result<SeccionDto>.Fail(Error.Validation("Cada asignatura lleva un solo docente."));
        var delGrado = await db.AsignaturasGrado.Where(a => a.GradoId == seccion.GradoId).Select(a => a.Id).ToListAsync(ct);
        if (r.Asignaciones.Any(a => !delGrado.Contains(a.AsignaturaId)))
            return Result<SeccionDto>.Fail(Error.Validation("Hay asignaturas que no son de este grado."));
        var pedidos = r.Asignaciones.Select(a => a.DocenteId).Distinct().ToList();
        var validos = await DocentesQuery(centro.Id).Where(u => pedidos.Contains(u.Id)).Select(u => u.Id).ToListAsync(ct);
        if (validos.Count != pedidos.Count)
            return Result<SeccionDto>.Fail(Error.Validation("Cada asignatura se asigna a un docente del centro."));

        var nueva = r.Asignaciones
            .Select(a => new CargaDocente { InstitucionId = centro.Id, SeccionId = seccionId, AsignaturaGradoId = a.AsignaturaId, DocenteId = a.DocenteId })
            .ToList();
        await db.Database.CreateExecutionStrategy().ExecuteAsync(async () =>
        {
            await using var tx = await db.Database.BeginTransactionAsync(ct);
            await db.CargasDocentes.Where(c => c.SeccionId == seccionId).ExecuteDeleteAsync(ct);
            db.CargasDocentes.AddRange(nueva);
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
        });
        return ADto(seccion, nueva);
    }

    // ── Personal ─────────────────────────────────────────────────────────────

    public async Task<Result<IReadOnlyList<PersonalDto>>> PersonalAsync(CancellationToken ct = default)
    {
        var (centro, yo) = await ContextoAsync(ct);
        if (centro is null) return Result<IReadOnlyList<PersonalDto>>.Fail(Error.Forbidden(SinCentro));
        var personal = await PersonalQuery(centro.Id).AsNoTracking().OrderBy(u => u.FullName).ToListAsync(ct);
        return personal.Select(u => new PersonalDto(u.Id, u.FullName, u.Email!, u.Cargo, u.IsActive, u.LastLoginAt, u.Id == yo!.Id)).ToList();
    }

    public async Task<Result<CuentaCreada>> CrearPersonalAsync(CrearPersonalRequest r, CancellationToken ct = default)
    {
        var (centro, error) = await EditorAsync(ct);
        if (centro is null) return Result<CuentaCreada>.Fail(error!);
        if (!Cargos.Todos.Contains(r.Cargo)) return Result<CuentaCreada>.Fail(Error.Validation("Cargo desconocido."));
        if (await PersonalQuery(centro.Id).CountAsync(ct) >= 20)
            return Result<CuentaCreada>.Fail(Error.Conflict("El centro ya tiene 20 cuentas de personal."));
        return await admin.CrearPersonalAsync(r.Email, r.Nombre, r.Cargo, centro.Id, ct);
    }

    public async Task<Result> CambiarCargoAsync(Guid id, CargoRequest r, CancellationToken ct = default)
    {
        var (centro, error) = await EditorAsync(ct);
        if (centro is null) return Result.Fail(error!);
        if (!Cargos.Todos.Contains(r.Cargo)) return Result.Fail(Error.Validation("Cargo desconocido."));
        var persona = await PersonalQuery(centro.Id).FirstOrDefaultAsync(u => u.Id == id, ct);
        if (persona is null) return Result.Fail(Error.NotFound("La cuenta"));
        if (!Cargos.Administra(r.Cargo) && !await QuedaOtroQueAdministraAsync(centro.Id, id, ct))
            return Result.Fail(Error.Conflict("Debe quedar al menos una cuenta que administre el centro."));
        persona.Cargo = r.Cargo;
        await users.UpdateAsync(persona);
        return Result.Success();
    }

    public async Task<Result> CambiarEstadoPersonalAsync(Guid id, bool activo, CancellationToken ct = default)
    {
        var (centro, error) = await EditorAsync(ct);
        if (centro is null) return Result.Fail(error!);
        if (id == currentUser.RequireUserId()) return Result.Fail(Error.Conflict("No puedes desactivar tu propia cuenta."));
        var persona = await PersonalQuery(centro.Id).FirstOrDefaultAsync(u => u.Id == id, ct);
        if (persona is null) return Result.Fail(Error.NotFound("La cuenta"));
        persona.IsActive = activo;
        await users.UpdateAsync(persona);
        if (!activo) await db.RefreshTokens.Where(t => t.UserId == id).ExecuteDeleteAsync(ct);
        return Result.Success();
    }

    public async Task<Result<CuentaCreada>> RestablecerClavePersonalAsync(Guid id, CancellationToken ct = default)
    {
        var (centro, error) = await EditorAsync(ct);
        if (centro is null) return Result<CuentaCreada>.Fail(error!);
        var persona = await PersonalQuery(centro.Id).FirstOrDefaultAsync(u => u.Id == id, ct);
        if (persona is null) return Result<CuentaCreada>.Fail(Error.NotFound("La cuenta"));
        return await admin.ReponerClaveAsync(persona, ct);
    }

    // ── Apoyo ────────────────────────────────────────────────────────────────

    internal async Task<(Institucion? Centro, AppUser? Yo)> ContextoAsync(CancellationToken ct)
    {
        var yo = await users.FindByIdAsync(currentUser.RequireUserId().ToString());
        if (yo?.InstitucionId is not { } id || !await users.IsInRoleAsync(yo, Roles.AdminCentro)) return (null, yo);
        return (await db.Instituciones.FirstOrDefaultAsync(i => i.Id == id, ct), yo);
    }

    /// <summary>El centro de quien llama, si su cargo administra y la licencia está al día.</summary>
    internal async Task<(Institucion? Centro, Error? Error)> EditorAsync(CancellationToken ct)
    {
        var (centro, yo) = await ContextoAsync(ct);
        if (centro is null) return (null, Error.Forbidden(SinCentro));
        if (!Cargos.Administra(yo!.Cargo)) return (null, Error.Forbidden(AdminService.SoloConsulta));
        if (!centro.Activa || SituacionCobro.Para(centro, clock.Today).SoloLectura)
            return (null, Error.Forbidden("La licencia del centro no está al día."));
        return (centro, null);
    }

    private IQueryable<AppUser> ConRol(Guid institucionId, string rol) =>
        from u in db.Users
        join ur in db.UserRoles on u.Id equals ur.UserId
        join r in db.Roles on ur.RoleId equals r.Id
        where r.Name == rol && u.InstitucionId == institucionId
        select u;

    private IQueryable<AppUser> DocentesQuery(Guid institucionId) => ConRol(institucionId, Roles.Docente);
    private IQueryable<AppUser> PersonalQuery(Guid institucionId) => ConRol(institucionId, Roles.AdminCentro);

    private async Task<bool> QuedaOtroQueAdministraAsync(Guid institucionId, Guid sinContar, CancellationToken ct) =>
        await PersonalQuery(institucionId).AnyAsync(u => u.Id != sinContar && u.IsActive
            && (u.Cargo == null || u.Cargo == Cargos.Director || u.Cargo == Cargos.Subdirector || u.Cargo == Cargos.Secretaria), ct);

    private static int BaseOrden(string nivel) => Array.IndexOf(NivelesEducativos.Todos, nivel) * 100;

    private async Task<int> SiguienteOrdenAsync(Guid institucionId, string nivel, CancellationToken ct) =>
        (await db.Grados.Where(g => g.InstitucionId == institucionId && g.Nivel == nivel)
            .MaxAsync(g => (int?)g.Orden, ct) ?? BaseOrden(nivel)) + 1;

    private static string? Limpio(string? texto) => string.IsNullOrWhiteSpace(texto) ? null : texto.Trim();

    private static AnioLectivoDto ADto(AnioLectivo a) =>
        new(a.Id, a.Anio, a.Inicio, a.Fin, [a.CierreParcial1, a.CierreParcial2, a.CierreParcial3, a.CierreParcial4], a.Actual);

    private static GradoDto ADto(Grado g, IEnumerable<AsignaturaGrado> asignaturas) =>
        new(g.Id, g.Nivel, g.Nombre, g.Orden,
            asignaturas.OrderBy(a => a.Orden).ThenBy(a => a.Nombre).Select(a => new AsignaturaGradoDto(a.Id, a.Nombre, a.Orden)).ToList());

    private static SeccionDto ADto(Seccion s, IEnumerable<CargaDocente> carga, int matriculados = 0) =>
        new(s.Id, s.GradoId, s.Nombre, s.Jornada, s.Cupo, s.AulaId, s.MaestroGuiaId,
            carga.Select(c => new AsignacionDto(c.AsignaturaGradoId, c.DocenteId)).ToList(), matriculados);
}
