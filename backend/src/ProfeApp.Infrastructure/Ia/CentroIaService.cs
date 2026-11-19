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
    private const string SinPro = "El asistente con IA es parte del plan Pro del centro.";

    public async Task<Result<EstadoIaCentroDto>> EstadoAsync(CancellationToken ct = default)
    {
        var (institucion, _) = await centro.ContextoAsync(ct);
        if (institucion is null) return Result<EstadoIaCentroDto>.Fail(Error.Forbidden(EstructuraCentroService.SinCentro));
        var (docentes, saldo) = await SaldoAsync(institucion, ct);
        return new EstadoIaCentroDto(Habilitada(institucion), ia.Disponible,
            CreditosIa.Creditos(await UsadosAsync(institucion.Id, ct)), saldo / 2, docentes);
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
        if (await NoAlcanzaAsync(institucion, alumnos * CreditosIa.Medios(FuncionesIa.Boleta), ct) is { } falta)
            return Result<ComentariosSeccionDto>.Fail(falta);

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
        if (await NoAlcanzaAsync(institucion, CreditosIa.Medios(FuncionesIa.Informe), ct) is { } falta)
            return Result<InformeIaDto>.Fail(falta);

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
        if (await NoAlcanzaAsync(institucion, CreditosIa.Medios(FuncionesIa.Comunicado), ct) is { } falta)
            return Result<ComunicadoIaDto>.Fail(falta);

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

    // ── Preguntas de la dirección ────────────────────────────────────────────

    private static readonly string[] Meses =
        ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"];

    public async Task<Result<RespuestaIaDto>> PreguntarAsync(PreguntaIaRequest r, CancellationToken ct = default)
    {
        var pregunta = ClienteIa.Texto(r.Pregunta, 500);
        if (pregunta is null) return Result<RespuestaIaDto>.Fail(Error.Validation("Escribe tu pregunta (hasta 500 caracteres)."));
        var (institucion, _) = await centro.ContextoAsync(ct);
        if (institucion is null) return Result<RespuestaIaDto>.Fail(Error.Forbidden(EstructuraCentroService.SinCentro));
        if (Permiso(institucion) is { } sin) return Result<RespuestaIaDto>.Fail(sin);
        if (await NoAlcanzaAsync(institucion, CreditosIa.Medios(FuncionesIa.Pregunta), ct) is { } falta)
            return Result<RespuestaIaDto>.Fail(falta);

        var datos = await DatosCentroAsync(institucion.Id, ct);
        if (datos is null) return Result<RespuestaIaDto>.Fail(Error.Validation("Falta el año lectivo actual con secciones y alumnos."));
        var sistema = ClienteIa.Contexto + "\n\nRespondes preguntas de la dirección de un centro educativo usando SOLO los datos " +
            "de abajo (cifras del año actual hasta hoy). Responde en pocas oraciones o una lista corta, con las cifras que " +
            "respaldan la respuesta. Si los datos no alcanzan para responder, dilo y sugiere dónde verlo en ProfeApp (Reportes, " +
            "Asistencia, Incidencias o Estadísticas docentes). No tienes nombres de alumnos: si te los piden, explica que por " +
            "privacidad se ven en esas pestañas. Sin tablas en formato markdown.\n\nDATOS DEL CENTRO\n" + datos;
        var historial = (r.Historial ?? []).TakeLast(6)
            .Select(t => (ClienteIa.Texto(t.Pregunta, 500) ?? "", ClienteIa.Texto(t.Respuesta, 3000) ?? ""))
            .Where(t => t.Item1.Length > 0 && t.Item2.Length > 0).ToList();
        var texto = await ia.TextoAsync(FuncionesIa.Pregunta,
            new PeticionIa(sistema, pregunta, null, 3000, Breve: false, Historial: historial), currentUser.RequireUserId(), institucion.Id, ct);
        return texto.IsSuccess ? new RespuestaIaDto(texto.Value.Trim()) : Result<RespuestaIaDto>.Fail(texto.Error!);
    }

    /// <summary>
    /// Cifras del año por sección y por mes, y el avance de cada docente. Nombres de docentes
    /// sí (son el personal del centro); de alumnos, nunca.
    /// </summary>
    private async Task<string?> DatosCentroAsync(Guid institucionId, CancellationToken ct)
    {
        var reporte = await reportes.ResumenAsync(ct);
        if (!reporte.IsSuccess || reporte.Value.Anio is null) return null;
        var r = reporte.Value;
        var anio = await db.AniosLectivos.AsNoTracking().FirstAsync(a => a.InstitucionId == institucionId && a.Actual, ct);
        var l = new List<string> { $"Hoy: {clock.Today:yyyy-MM-dd}. Año lectivo {r.Anio}, del {anio.Inicio:yyyy-MM-dd} al {anio.Fin:yyyy-MM-dd}." };

        var m = r.Matricula;
        l.Add($"Matrícula activa: {m.Activos}; nuevos {m.Nuevos}, reingresos {m.Reingresos}, traslados entrantes {m.TrasladosEntrantes}, retirados {m.Retirados}, trasladados {m.Trasladados}.");
        l.Add("Por sección (activos, mujeres, hombres, cupo, retirados):");
        l.AddRange(m.PorSeccion.Select(s => $"- {s.Seccion} ({s.Jornada}): {s.Activos}, F {s.Femenino}, M {s.Masculino}, cupo {s.Cupo?.ToString() ?? "sin cupo"}, retirados {s.Retirados}"));

        l.Add("Rendimiento con lo cerrado (sección · asignatura · docente: aprobados de evaluados, promedio):");
        foreach (var s in r.Rendimiento)
            foreach (var a in s.Asignaturas)
                l.Add($"- {s.Seccion} · {a.Asignatura} · {a.Docente}: {a.Aprobados} de {a.Evaluados}, promedio {a.Promedio?.ToString() ?? "sin notas"}");
        l.Add($"Alumnos en riesgo: {r.Riesgo.Count}. Por sección: {string.Join(", ", r.Riesgo.GroupBy(x => x.Seccion).Select(g => $"{g.Key} {g.Count()}"))}");

        // Lista del día por sección y mes.
        var ids = m.PorSeccion.Select(s => s.SeccionId).ToList();
        var nombre = m.PorSeccion.ToDictionary(s => s.SeccionId, s => s.Seccion);
        var tomas = await db.TomasAsistenciaDiaria.AsNoTracking().Where(t => ids.Contains(t.SeccionId) && t.Fecha >= anio.Inicio)
            .Select(t => new { t.Id, t.SeccionId, t.Fecha }).ToListAsync(ct);
        var tomaIds = tomas.Select(t => t.Id).ToList();
        var marcas = (await db.MarcasAsistenciaDiaria.AsNoTracking().Where(x => tomaIds.Contains(x.TomaId))
            .Select(x => new { x.TomaId, x.Estado }).ToListAsync(ct)).ToLookup(x => x.TomaId, x => x.Estado);
        l.Add("Lista del día por sección y mes (días con lista, ausencias, tardes, justificadas):");
        foreach (var g in tomas.GroupBy(t => (t.SeccionId, t.Fecha.Year, t.Fecha.Month)).OrderBy(g => nombre[g.Key.SeccionId]).ThenBy(g => g.Key.Year).ThenBy(g => g.Key.Month))
        {
            var estados = g.SelectMany(t => marcas[t.Id]).ToList();
            l.Add($"- {nombre[g.Key.SeccionId]}, {Meses[g.Key.Month - 1]} {g.Key.Year}: {g.Count()} días, {estados.Count(e => e == "A")} ausencias, {estados.Count(e => e == "T")} tardes, {estados.Count(e => e == "J")} justificadas");
        }

        var incidencias = await db.Incidencias.AsNoTracking().Where(i => i.InstitucionId == institucionId && i.Fecha >= anio.Inicio)
            .Select(i => new { i.SeccionId, i.Fecha, i.Gravedad, i.Cerrada }).ToListAsync(ct);
        l.Add("Incidencias por sección y mes (leves, graves, muy graves; abiertas):");
        foreach (var g in incidencias.GroupBy(i => (Seccion: i.SeccionId is { } s && nombre.TryGetValue(s, out var n) ? n : "sin sección", i.Fecha.Year, i.Fecha.Month))
                     .OrderBy(g => g.Key.Seccion).ThenBy(g => g.Key.Year).ThenBy(g => g.Key.Month))
            l.Add($"- {g.Key.Seccion}, {Meses[g.Key.Month - 1]} {g.Key.Year}: {g.Count(i => i.Gravedad == "leve")}, {g.Count(i => i.Gravedad == "grave")}, {g.Count(i => i.Gravedad == "muy_grave")}; abiertas {g.Count(i => !i.Cerrada)}");
        var excusas = await db.Excusas.AsNoTracking().Where(e => e.InstitucionId == institucionId && e.Hasta >= anio.Inicio)
            .Select(e => e.Desde).ToListAsync(ct);
        l.Add("Excusas y permisos registrados por mes: " +
              string.Join(", ", excusas.GroupBy(d => (d.Year, d.Month)).OrderBy(g => g.Key).Select(g => $"{Meses[g.Key.Month - 1]} {g.Key.Year} {g.Count()}")));

        var docentes = await reportes.DocentesAsync(ct);
        if (docentes.IsSuccess)
        {
            l.Add($"Docentes (días hábiles del año hasta hoy: {docentes.Value.DiasHabiles}). Nombre: asignaturas asignadas, cuadros en la app, parciales cerrados, listas de clase en 30 días, días con lista del día si es guía, incidencias registradas, aprobados de evaluados, promedio, último trabajo:");
            foreach (var d in docentes.Value.Docentes.Where(d => d.Activo))
                l.Add($"- {d.Nombre}: {d.AsignaturasCarga}, {d.CuadrosEnApp}, {d.ParcialesCerrados}, {d.ListasRecientes}, " +
                      $"{(d.DiasListaDelDia is { } dl ? dl.ToString() : "no es guía")}, {d.Incidencias}, {d.Aprobados} de {d.Evaluados}, " +
                      $"{d.Promedio?.ToString() ?? "sin notas"}, {(d.UltimoTrabajo is { } u ? $"hace {(clock.Now - u).Days} días" : "nunca")}");
        }
        return string.Join("\n", l);
    }

    // ── Apoyo ────────────────────────────────────────────────────────────────

    private static bool Habilitada(Institucion i) => i.Activa && i.ConIa;

    private static int Multiplicador(Institucion i) => Math.Max(1, i.IaMultiplicador);

    private Error? Permiso(Institucion i) =>
        !ia.Disponible ? Error.Forbidden("El asistente con IA no está disponible en este momento.")
        : !Habilitada(i) ? Error.Forbidden(SinPro)
        : null;

    /// <summary>Medios créditos que usó la dirección este mes (lo de los docentes va por su saldo).</summary>
    private async Task<int> UsadosAsync(Guid institucionId, CancellationToken ct)
    {
        var desde = ClienteIa.InicioDelMes(clock.Today);
        return await db.UsosIa
            .Where(u => u.InstitucionId == institucionId && u.CreatedAt >= desde && CreditosIa.DeLaDireccion.Contains(u.Funcion))
            .SumAsync(u => u.Medios, ct);
    }

    /// <summary>25 créditos por docente activo (al menos uno), por el multiplicador del centro.</summary>
    private async Task<(int Docentes, int Saldo)> SaldoAsync(Institucion i, CancellationToken ct)
    {
        var docentes = await (from u in db.Users.AsNoTracking()
                              join ur in db.UserRoles on u.Id equals ur.UserId
                              join r in db.Roles on ur.RoleId equals r.Id
                              where r.Name == Roles.Docente && u.InstitucionId == i.Id && u.IsActive
                              select u.Id).CountAsync(ct);
        return (docentes, CreditosIa.SaldoDireccionPorDocente * Math.Max(1, docentes) * Multiplicador(i));
    }

    private async Task<Error?> NoAlcanzaAsync(Institucion i, int medios, CancellationToken ct)
    {
        var (_, saldo) = await SaldoAsync(i, ct);
        var quedan = saldo - await UsadosAsync(i.Id, ct);
        if (medios <= quedan) return null;
        return Error.Validation(quedan <= 0
            ? $"El centro ya usó los {saldo / 2} créditos de IA de este mes.{AsistenteIaService.Ampliar}"
            : $"No alcanzan los créditos: esto usa {CreditosIa.Creditos(medios)} y al centro le quedan {CreditosIa.Creditos(quedan)} de {saldo / 2}.{AsistenteIaService.Ampliar}");
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
