using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;
using ProfeApp.Domain.Centros;
using ProfeApp.Domain.Common;
using ProfeApp.Domain.Instituciones;
using ProfeApp.Infrastructure.Centros;
using ProfeApp.Infrastructure.Persistence;

namespace ProfeApp.Infrastructure.Ia;

/// <summary>
/// Asistente del centro con plan Pro: comentarios de boleta por sección, informe para la
/// dirección y borradores de comunicados. A la IA no van nombres de alumnos ni de docentes.
/// </summary>
public sealed class CentroIaService(
    AppDbContext db,
    EstructuraCentroService centro,
    ClienteIa ia,
    IReportesService reportes,
    ColaBoletas cola,
    ICurrentUser currentUser,
    IClock clock) : ICentroIaService
{
    public const int LimiteBoletas = 3000;
    public const int LimiteInformes = 30;
    public const int LimiteComunicados = 100;

    private const string SinPro = "El asistente con IA es parte del plan Pro del centro.";

    public async Task<Result<EstadoIaCentroDto>> EstadoAsync(CancellationToken ct = default)
    {
        var (institucion, _) = await centro.ContextoAsync(ct);
        if (institucion is null) return Result<EstadoIaCentroDto>.Fail(Error.Forbidden(EstructuraCentroService.SinCentro));
        var usos = await UsosAsync(institucion.Id, ct);
        return new EstadoIaCentroDto(Habilitada(institucion), ia.Disponible,
            usos.GetValueOrDefault(FuncionesIa.Boleta), LimiteBoletas,
            usos.GetValueOrDefault(FuncionesIa.Informe), LimiteInformes,
            usos.GetValueOrDefault(FuncionesIa.Comunicado), LimiteComunicados);
    }

    // ── Comentarios de boleta ────────────────────────────────────────────────

    public async Task<Result<ComentariosSeccionDto>> ComentariosAsync(Guid seccionId, int parcial, CancellationToken ct = default)
    {
        if (parcial is < 1 or > 4) return Result<ComentariosSeccionDto>.Fail(Error.Validation("Los parciales van del I al IV."));
        var (institucion, _) = await centro.ContextoAsync(ct);
        if (institucion is null) return Result<ComentariosSeccionDto>.Fail(Error.Forbidden(EstructuraCentroService.SinCentro));
        if (!await db.Secciones.AnyAsync(s => s.Id == seccionId && s.InstitucionId == institucion.Id, ct))
            return Result<ComentariosSeccionDto>.Fail(Error.NotFound("La sección"));
        return await ArmarComentariosAsync(seccionId, parcial, ct);
    }

    public async Task<Result<ComentariosSeccionDto>> GenerarComentariosAsync(Guid seccionId, GenerarComentariosRequest r, CancellationToken ct = default)
    {
        if (r.Parcial is < 1 or > 4) return Result<ComentariosSeccionDto>.Fail(Error.Validation("Los parciales van del I al IV."));
        var (institucion, error) = await centro.EditorAsync(ct);
        if (institucion is null) return Result<ComentariosSeccionDto>.Fail(error!);
        if (Permiso(institucion) is { } sin) return Result<ComentariosSeccionDto>.Fail(sin);
        if (!await db.Secciones.AnyAsync(s => s.Id == seccionId && s.InstitucionId == institucion.Id, ct))
            return Result<ComentariosSeccionDto>.Fail(Error.NotFound("La sección"));

        var alumnos = await db.Matriculas.CountAsync(m => m.SeccionId == seccionId && m.Estado == EstadosMatricula.Activa, ct);
        var usados = (await UsosAsync(institucion.Id, ct)).GetValueOrDefault(FuncionesIa.Boleta);
        if (usados + alumnos > LimiteBoletas)
            return Result<ComentariosSeccionDto>.Fail(Error.Validation($"Este mes quedan {Math.Max(0, LimiteBoletas - usados)} comentarios de boleta y la sección tiene {alumnos} alumnos."));

        cola.Encolar(new TrabajoBoletas(institucion.Id, institucion.Nombre, seccionId, r.Parcial, r.Todos, currentUser.RequireUserId()));
        return await ArmarComentariosAsync(seccionId, r.Parcial, ct);
    }

    public async Task<Result> EditarComentarioAsync(Guid seccionId, Guid alumnoId, EditarComentarioRequest r, CancellationToken ct = default)
    {
        if (r.Parcial is < 1 or > 4) return Result.Fail(Error.Validation("Los parciales van del I al IV."));
        var (institucion, error) = await centro.EditorAsync(ct);
        if (institucion is null) return Result.Fail(error!);
        if (!await db.Matriculas.AnyAsync(m => m.SeccionId == seccionId && m.AlumnoId == alumnoId && m.InstitucionId == institucion.Id, ct))
            return Result.Fail(Error.NotFound("El alumno"));
        var texto = (r.Texto ?? "").Trim();
        if (texto.Length > 1000) return Result.Fail(Error.Validation("El comentario va hasta 1000 caracteres."));

        var fila = await db.ComentariosBoleta.FirstOrDefaultAsync(c => c.SeccionId == seccionId && c.AlumnoId == alumnoId && c.Parcial == r.Parcial, ct);
        if (texto.Length == 0)
        {
            if (fila is not null) db.ComentariosBoleta.Remove(fila);
        }
        else
        {
            fila ??= db.ComentariosBoleta.Add(new ComentarioBoleta
            {
                InstitucionId = institucion.Id, SeccionId = seccionId, AlumnoId = alumnoId, Parcial = r.Parcial,
            }).Entity;
            fila.Texto = texto;
            fila.DeIa = false;
        }
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    private async Task<ComentariosSeccionDto> ArmarComentariosAsync(Guid seccionId, int parcial, CancellationToken ct)
    {
        var comentarios = await db.ComentariosBoleta.AsNoTracking().Where(c => c.SeccionId == seccionId && c.Parcial == parcial)
            .ToDictionaryAsync(c => c.AlumnoId, ct);
        var alumnos = await (from m in db.Matriculas.AsNoTracking()
                             join a in db.Alumnos.AsNoTracking() on m.AlumnoId equals a.Id
                             where m.SeccionId == seccionId && m.Estado == EstadosMatricula.Activa
                             orderby a.Nombre
                             select new { a.Id, a.Nombre })
            .ToListAsync(ct);
        return new ComentariosSeccionDto(seccionId, parcial, cola.EnProceso(seccionId, parcial), alumnos
            .Select(a => comentarios.TryGetValue(a.Id, out var c)
                ? new ComentarioAlumnoDto(a.Id, a.Nombre, c.Texto, c.DeIa)
                : new ComentarioAlumnoDto(a.Id, a.Nombre, null, false))
            .ToList());
    }

    // ── Informe para la dirección ────────────────────────────────────────────

    public async Task<Result<InformeIaDto>> InformeAsync(CancellationToken ct = default)
    {
        var (institucion, _) = await centro.ContextoAsync(ct);
        if (institucion is null) return Result<InformeIaDto>.Fail(Error.Forbidden(EstructuraCentroService.SinCentro));
        if (Permiso(institucion) is { } sin) return Result<InformeIaDto>.Fail(sin);
        if ((await UsosAsync(institucion.Id, ct)).GetValueOrDefault(FuncionesIa.Informe) >= LimiteInformes)
            return Result<InformeIaDto>.Fail(Error.Validation($"Ya se usaron los {LimiteInformes} informes de este mes."));

        var reporte = await reportes.ResumenAsync(ct);
        if (!reporte.IsSuccess) return Result<InformeIaDto>.Fail(reporte.Error!);
        var r = reporte.Value;
        if (r.Anio is null) return Result<InformeIaDto>.Fail(Error.Validation("Falta el año lectivo actual con secciones y alumnos."));

        var sistema = ClienteIa.Contexto + "\n\nEres asesor pedagógico de la dirección de un centro educativo. Con los datos del " +
            "año (lo que han cerrado los docentes hasta hoy), escribe un informe breve: un resumen de 3 a 5 oraciones, y listas " +
            "cortas de fortalezas, alertas y recomendaciones concretas y realizables (de 3 a 5 cada una). Cita secciones y " +
            "asignaturas por su nombre; no inventes datos que no estén aquí. Si los datos son pocos, dilo.";
        return await ia.JsonAsync<InformeIaDto>(FuncionesIa.Informe,
            new PeticionIa(sistema, DatosInforme(r), EsquemaInforme, 6000, Breve: false), currentUser.RequireUserId(), institucion.Id, ct);
    }

    /// <summary>Solo cifras por sección y asignatura: sin nombres de alumnos ni de docentes.</summary>
    private static string DatosInforme(ReportesDto r)
    {
        var m = r.Matricula;
        var l = new List<string>
        {
            $"Año lectivo {r.Anio}. Matrícula activa: {m.Activos} (nuevos {m.Nuevos}, reingresos {m.Reingresos}, " +
            $"traslados entrantes {m.TrasladosEntrantes}; retirados {m.Retirados}, trasladados {m.Trasladados}).",
            "Rendimiento (evaluados, aprobados con la nota mínima y promedio, con lo cerrado):",
        };
        foreach (var s in r.Rendimiento)
            foreach (var a in s.Asignaturas.Where(a => a.Evaluados > 0))
                l.Add($"- {s.Seccion} · {a.Asignatura}: {a.Aprobados} de {a.Evaluados} aprobados, promedio {a.Promedio}");
        l.Add("Asistencia de la lista del día por sección:");
        l.AddRange(r.Asistencia.Where(a => a.Dias > 0).Select(a =>
            $"- {a.Seccion}: {a.Porcentaje}% en {a.Dias} días ({a.Ausencias} ausencias, {a.Tardes} tardes, {a.Justificadas} justificadas)"));
        l.Add($"Alumnos en riesgo (nota bajo la mínima o muchas ausencias): {r.Riesgo.Count}. Por sección: " +
              string.Join(", ", r.Riesgo.GroupBy(x => x.Seccion).Select(g => $"{g.Key} {g.Count()}")));
        if (r.Convivencia is { } c)
            l.Add($"Convivencia del año: {c.Leves} faltas leves, {c.Graves} graves, {c.MuyGraves} muy graves ({c.Abiertas} casos abiertos); {c.Excusas} excusas o permisos.");
        return string.Join("\n", l);
    }

    // ── Comunicados ──────────────────────────────────────────────────────────

    public async Task<Result<ComunicadoIaDto>> ComunicadoAsync(ComunicadoIaRequest r, CancellationToken ct = default)
    {
        var puntos = ClienteIa.Texto(r.Puntos, 1500);
        if (puntos is null) return Result<ComunicadoIaDto>.Fail(Error.Validation("Escribe lo que quieres comunicar (hasta 1500 caracteres)."));
        var (institucion, error) = await centro.EditorAsync(ct);
        if (institucion is null) return Result<ComunicadoIaDto>.Fail(error!);
        if (Permiso(institucion) is { } sin) return Result<ComunicadoIaDto>.Fail(sin);
        if ((await UsosAsync(institucion.Id, ct)).GetValueOrDefault(FuncionesIa.Comunicado) >= LimiteComunicados)
            return Result<ComunicadoIaDto>.Fail(Error.Validation($"Ya se usaron los {LimiteComunicados} borradores de este mes."));

        var sistema = ClienteIa.Contexto + "\n\nRedacta un comunicado del centro a las familias a partir de los puntos que da la " +
            "dirección. Título corto (hasta 80 caracteres) y un mensaje cordial y claro, de 1 a 3 párrafos breves, que incluya " +
            "todos los datos dados (fechas, horas, lugares) sin inventar otros. Sin firma: el centro aparece como remitente.";
        var usuario = $"Centro: {institucion.Nombre}\nPara: {ClienteIa.Texto(r.Destinatarios, 120) ?? "todas las familias"}\n\nPuntos:\n{puntos}";
        var resultado = await ia.JsonAsync<ComunicadoIaDto>(FuncionesIa.Comunicado,
            new PeticionIa(sistema, usuario, EsquemaComunicado, 2000, Breve: true), currentUser.RequireUserId(), institucion.Id, ct);
        if (!resultado.IsSuccess) return resultado;
        var c = resultado.Value;
        return new ComunicadoIaDto(ClienteIa.Texto(c.Titulo, 160) ?? "Comunicado", ClienteIa.Texto(c.Cuerpo, 4000) ?? "");
    }

    // ── Apoyo ────────────────────────────────────────────────────────────────

    private static bool Habilitada(Institucion i) => i.Activa && i.ConIa;

    private Error? Permiso(Institucion i) =>
        !ia.Disponible ? Error.Forbidden("El asistente con IA no está disponible en este momento.")
        : !Habilitada(i) ? Error.Forbidden(SinPro)
        : null;

    private async Task<Dictionary<string, int>> UsosAsync(Guid institucionId, CancellationToken ct)
    {
        var desde = ClienteIa.InicioDelMes(clock.Today);
        return await db.UsosIa.Where(u => u.InstitucionId == institucionId && u.CreatedAt >= desde)
            .GroupBy(u => u.Funcion).Select(g => new { g.Key, N = g.Count() }).ToDictionaryAsync(x => x.Key, x => x.N, ct);
    }

    private static readonly Dictionary<string, JsonElement> EsquemaInforme = ClienteIa.Esquema(new
    {
        type = "object",
        additionalProperties = false,
        required = new[] { "resumen", "fortalezas", "alertas", "recomendaciones" },
        properties = new
        {
            resumen = new { type = "string" },
            fortalezas = new { type = "array", items = new { type = "string" } },
            alertas = new { type = "array", items = new { type = "string" } },
            recomendaciones = new { type = "array", items = new { type = "string" } },
        },
    });

    private static readonly Dictionary<string, JsonElement> EsquemaComunicado = ClienteIa.Esquema(new
    {
        type = "object",
        additionalProperties = false,
        required = new[] { "titulo", "cuerpo" },
        properties = new { titulo = new { type = "string" }, cuerpo = new { type = "string" } },
    });
}
