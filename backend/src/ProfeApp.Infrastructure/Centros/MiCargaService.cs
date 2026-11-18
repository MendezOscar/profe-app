using Microsoft.EntityFrameworkCore;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Contracts;
using ProfeApp.Infrastructure.Persistence;

namespace ProfeApp.Infrastructure.Centros;

/// <summary>
/// Secciones del año actual donde el docente tiene carga o es maestro guía, con la lista de
/// matrícula. Sólo nombre, identidad y estado: la ficha (salud, encargados) no sale de aquí.
/// </summary>
public sealed class MiCargaService(AppDbContext db, ICurrentUser currentUser, HorarioService horario) : IMiCargaService
{
    private static readonly MiCargaDto SinCentro = new(null, null, []);

    public async Task<MiCargaDto> ObtenerAsync(CancellationToken ct = default)
    {
        var yo = currentUser.RequireUserId();
        var institucionId = await db.Users.Where(u => u.Id == yo).Select(u => u.InstitucionId).FirstOrDefaultAsync(ct);
        if (institucionId is not { } centroId) return SinCentro;

        var centro = await db.Instituciones.Where(i => i.Id == centroId && i.Activa).Select(i => i.Nombre).FirstOrDefaultAsync(ct);
        var anio = await db.AniosLectivos.AsNoTracking().FirstOrDefaultAsync(a => a.InstitucionId == centroId && a.Actual, ct);
        if (centro is null || anio is null) return new MiCargaDto(centro, null, []);

        var carga = await (from c in db.CargasDocentes.AsNoTracking()
                           join a in db.AsignaturasGrado.AsNoTracking() on c.AsignaturaGradoId equals a.Id
                           join s in db.Secciones.AsNoTracking() on c.SeccionId equals s.Id
                           where c.DocenteId == yo && s.AnioLectivoId == anio.Id
                           orderby a.Orden
                           select new { c.SeccionId, a.Nombre })
            .ToListAsync(ct);
        var guia = await db.Secciones.AsNoTracking()
            .Where(s => s.MaestroGuiaId == yo && s.AnioLectivoId == anio.Id).Select(s => s.Id).ToListAsync(ct);

        var ids = carga.Select(c => c.SeccionId).Concat(guia).Distinct().ToList();
        if (ids.Count == 0) return new MiCargaDto(centro, anio.Anio, []);
        var clases = await horario.DelDocenteAsync(anio.Id, yo, ct);

        var secciones = await (from s in db.Secciones.AsNoTracking()
                               join g in db.Grados.AsNoTracking() on s.GradoId equals g.Id
                               where ids.Contains(s.Id)
                               orderby g.Orden, s.Jornada, s.Nombre
                               select new { s.Id, Grado = g.Nombre, s.Nombre, s.Jornada })
            .ToListAsync(ct);
        var alumnos = (await (from m in db.Matriculas.AsNoTracking()
                              join a in db.Alumnos.AsNoTracking() on m.AlumnoId equals a.Id
                              where ids.Contains(m.SeccionId)
                              orderby a.Nombre
                              select new { m.SeccionId, a.Identidad, a.Nombre, m.Estado })
                .ToListAsync(ct))
            .ToLookup(x => x.SeccionId);
        var asignaturas = carga.ToLookup(c => c.SeccionId, c => c.Nombre);

        return new MiCargaDto(centro, anio.Anio, secciones
            .Select(s => new SeccionDocenteDto(s.Id, s.Grado, s.Nombre, s.Jornada, guia.Contains(s.Id),
                asignaturas[s.Id].ToList(),
                alumnos[s.Id].Select(a => new AlumnoListaDto(a.Identidad, a.Nombre, a.Estado)).ToList()))
            .ToList(), clases);
    }
}
