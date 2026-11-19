using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;
using ProfeApp.Domain.Common;
using ProfeApp.Infrastructure.Persistence;

namespace ProfeApp.Infrastructure.Ia;

/// <summary>
/// Asistente del docente con plan Pro. Arma la petición, valida lo que vuelve y anota el uso
/// (sin el texto) para el tope del mes. No recibe nombres ni identidades de alumnos.
/// </summary>
public sealed class AsistenteIaService(
    AppDbContext db,
    ClienteIa ia,
    ICurrentUser currentUser,
    IClock clock) : IAsistenteIaService
{
    /// <summary>Planes del parcial y exámenes por docente al mes.</summary>
    public const int LimiteGeneraciones = 60;

    /// <summary>Comentarios de alumnos por docente al mes (son cortos y baratos).</summary>
    public const int LimiteComentarios = 400;

    /// <summary>Trabajos calificados desde una foto por docente al mes.</summary>
    public const int LimiteCalificaciones = 300;

    private const int MaxFoto = 2 * 1024 * 1024;

    private const string Contexto = ClienteIa.Contexto;

    private static readonly string[] TiposPregunta = ["opcion_multiple", "verdadero_falso", "respuesta_corta", "desarrollo"];

    public async Task<EstadoIaDto> EstadoAsync(CancellationToken ct = default)
    {
        var (habilitada, _) = await HabilitadaAsync(ct);
        var (generaciones, comentarios, calificaciones) = await UsadosAsync(ct);
        return new EstadoIaDto(habilitada, ia.Disponible, generaciones, LimiteGeneraciones, comentarios, LimiteComentarios,
            calificaciones, LimiteCalificaciones);
    }

    // ── Plan del parcial ─────────────────────────────────────────────────────

    public async Task<Result<PlanIaDto>> PlanAsync(PlanIaRequest r, CancellationToken ct = default)
    {
        var asignatura = Texto(r.Asignatura, 120);
        var temas = Texto(r.Temas, 2000);
        if (asignatura is null) return Result<PlanIaDto>.Fail(Error.Validation("Falta la asignatura."));
        if (temas is null) return Result<PlanIaDto>.Fail(Error.Validation("Escribe los temas del parcial (hasta 2000 caracteres)."));
        if (r.Semanas is < 1 or > 12) return Result<PlanIaDto>.Fail(Error.Validation("El parcial dura de 1 a 12 semanas."));
        if (r.Total is <= 0 or > 1000) return Result<PlanIaDto>.Fail(Error.Validation("El total de puntos no es válido."));
        var rubros = (r.Rubros ?? []).Where(x => !string.IsNullOrWhiteSpace(x.Nombre)).Take(15).ToList();

        var permiso = await PuedeAsync(FuncionesIa.Plan, ct);
        if (permiso is not null) return Result<PlanIaDto>.Fail(permiso);

        var usuario =
            $"Asignatura: {asignatura}\nGrado: {Texto(r.Grado, 120) ?? "no indicado"}\nParcial: {Texto(r.Parcial, 60) ?? "no indicado"}\n" +
            $"Duración: {r.Semanas} semanas\nTotal del parcial: {r.Total} puntos\n\nTemas:\n{temas}\n\n" +
            (rubros.Count > 0
                ? "Usa exactamente estos rubros con sus puntos y reparte cada uno en actividades:\n" +
                  string.Join("\n", rubros.Select(x => $"- {Texto(x.Nombre, 80)}: {x.Puntos} puntos"))
                : $"Propón de 3 a 5 rubros (por ejemplo tareas, trabajo en clase, proyecto, examen) que sumen {r.Total} puntos.");
        var sistema = Contexto + "\n\nArma el plan de evaluación de un parcial: rubros con puntos y, en cada rubro, " +
            "actividades concretas con título corto, puntos, una descripción de una o dos oraciones para el estudiante y " +
            "la semana del parcial en que va. Los puntos de las actividades de un rubro suman exactamente los del rubro. " +
            "Reparte las actividades a lo largo de las semanas y deja el examen para la última.";

        var resultado = await LlamarAsync<PlanIaDto>(FuncionesIa.Plan, new PeticionIa(sistema, usuario, EsquemaPlan, 8000, Breve: false), ct);
        if (!resultado.IsSuccess) return resultado;

        // Lo que el docente ya tiene manda: nombres y puntos de sus rubros.
        var plan = resultado.Value;
        if (rubros.Count > 0)
        {
            var propios = rubros.ToDictionary(x => Clave(x.Nombre), x => x);
            plan = new PlanIaDto(plan.Rubros
                .Where(x => propios.ContainsKey(Clave(x.Nombre)))
                .Select(x => x with { Nombre = propios[Clave(x.Nombre)].Nombre, Puntos = propios[Clave(x.Nombre)].Puntos })
                .ToList());
        }
        return new PlanIaDto(plan.Rubros.Select(x => x with
        {
            Actividades = x.Actividades.Select(a => a with { Semana = Math.Clamp(a.Semana, 1, r.Semanas) }).ToList(),
        }).ToList());
    }

    // ── Examen ───────────────────────────────────────────────────────────────

    public async Task<Result<ExamenIaDto>> ExamenAsync(ExamenIaRequest r, CancellationToken ct = default)
    {
        var asignatura = Texto(r.Asignatura, 120);
        var temas = Texto(r.Temas, 2000);
        if (asignatura is null) return Result<ExamenIaDto>.Fail(Error.Validation("Falta la asignatura."));
        if (temas is null) return Result<ExamenIaDto>.Fail(Error.Validation("Escribe los temas del examen (hasta 2000 caracteres)."));
        if (r.Preguntas is < 3 or > 40) return Result<ExamenIaDto>.Fail(Error.Validation("El examen lleva de 3 a 40 preguntas."));
        if (r.Puntos is <= 0 or > 100) return Result<ExamenIaDto>.Fail(Error.Validation("El examen vale de 1 a 100 puntos."));
        var tipos = (r.Tipos ?? []).Where(TiposPregunta.Contains).Distinct().ToList();
        if (tipos.Count == 0) return Result<ExamenIaDto>.Fail(Error.Validation("Elige al menos un tipo de pregunta."));

        var permiso = await PuedeAsync(FuncionesIa.Examen, ct);
        if (permiso is not null) return Result<ExamenIaDto>.Fail(permiso);

        var usuario =
            $"Asignatura: {asignatura}\nGrado: {Texto(r.Grado, 120) ?? "no indicado"}\nPreguntas: {r.Preguntas}\n" +
            $"Valor total: {r.Puntos} puntos\nTipos de pregunta: {string.Join(", ", tipos)}\n\nTemas:\n{temas}";
        var sistema = Contexto + "\n\nRedacta un examen escrito para imprimir. Usa solo los tipos de pregunta pedidos, " +
            "mezclados y de dificultad progresiva, adecuados al grado. Opción múltiple: cuatro opciones sin letras, una sola " +
            "correcta, y en la respuesta el texto de la correcta. Verdadero o falso: sin opciones; respuesta «Verdadero» o " +
            "«Falso». Respuesta corta y desarrollo: sin opciones; en la respuesta, lo que se espera para dar todos los puntos. " +
            "Los puntos de las preguntas suman exactamente el valor total. Instrucciones generales breves.";

        var resultado = await LlamarAsync<ExamenIaDto>(FuncionesIa.Examen, new PeticionIa(sistema, usuario, EsquemaExamen, 12000, Breve: false), ct);
        if (!resultado.IsSuccess) return resultado;
        var examen = resultado.Value;
        return examen with
        {
            Preguntas = examen.Preguntas.Where(p => TiposPregunta.Contains(p.Tipo))
                .Select(p => p.Tipo == "opcion_multiple" ? p : p with { Opciones = [] }).ToList(),
        };
    }

    // ── Comentario de un alumno ──────────────────────────────────────────────

    public async Task<Result<ComentarioIaDto>> ComentarioAsync(ComentarioIaRequest r, CancellationToken ct = default)
    {
        var asignatura = Texto(r.Asignatura, 120);
        if (asignatura is null) return Result<ComentarioIaDto>.Fail(Error.Validation("Falta la asignatura."));
        var rubros = (r.Rubros ?? []).Take(15).ToList();
        if (rubros.Count == 0 && r.Nota is null)
            return Result<ComentarioIaDto>.Fail(Error.Validation("El alumno aún no tiene notas en este parcial."));

        var permiso = await PuedeAsync(FuncionesIa.Comentario, ct);
        if (permiso is not null) return Result<ComentarioIaDto>.Fail(permiso);

        var usuario =
            $"Asignatura: {asignatura}\nGrado: {Texto(r.Grado, 120) ?? "no indicado"}\nParcial: {Texto(r.Parcial, 60) ?? "no indicado"}\n" +
            (r.Nota is { } nota ? $"Nota del parcial hasta ahora: {nota} de 100 (mínima para aprobar: 70)\n" : "") +
            $"Ausencias: {r.Ausencias}. Llegadas tarde: {r.Tardes}.\n" +
            (rubros.Count > 0 ? "Por rubro:\n" + string.Join("\n", rubros.Select(x => $"- {Texto(x.Nombre, 80)}: {x.Obtenido} de {x.Posible}")) + "\n" : "") +
            (Texto(r.Enfoque, 300) is { } enfoque ? $"El docente quiere destacar: {enfoque}\n" : "");
        var sistema = Contexto + "\n\nRedacta el comentario del docente sobre el desempeño de un estudiante en el parcial, " +
            "para la familia. De 2 a 4 oraciones, en tercera persona, llamándolo «el estudiante». Empieza por un logro, señala " +
            "con respeto en qué debe mejorar según los rubros más bajos y cierra con una recomendación concreta. Sin cifras " +
            "exactas salvo la nota si aporta. Sin saludos ni firma. Responde solo con el comentario.";

        var resultado = await LlamarAsync(FuncionesIa.Comentario, new PeticionIa(sistema, usuario, null, 800, Breve: true), ct);
        return resultado.IsSuccess
            ? new ComentarioIaDto(resultado.Value.Trim())
            : Result<ComentarioIaDto>.Fail(resultado.Error!);
    }

    // ── Calificar desde una foto ─────────────────────────────────────────────

    public async Task<Result<CalificacionIaDto>> CalificarAsync(CalificarIaRequest r, CancellationToken ct = default)
    {
        var actividad = Texto(r.Actividad, 160);
        if (actividad is null) return Result<CalificacionIaDto>.Fail(Error.Validation("Falta la actividad."));
        if (r.Puntos is <= 0 or > 100) return Result<CalificacionIaDto>.Fail(Error.Validation("La actividad debe valer de 1 a 100 puntos."));
        var fotos = new List<byte[]>();
        foreach (var b64 in (r.Imagenes ?? []).Take(5))
        {
            byte[] foto;
            try { foto = Convert.FromBase64String(b64); }
            catch (FormatException) { return Result<CalificacionIaDto>.Fail(Error.Validation("Una de las fotos no se pudo leer.")); }
            if (foto.Length is < 4 or > MaxFoto || foto[0] != 0xFF || foto[1] != 0xD8)
                return Result<CalificacionIaDto>.Fail(Error.Validation("Las fotos deben ser JPG de hasta 2 MB."));
            fotos.Add(foto);
        }
        if (fotos.Count is < 1 or > 4) return Result<CalificacionIaDto>.Fail(Error.Validation("Envía de 1 a 4 fotos del trabajo."));

        var permiso = await PuedeAsync(FuncionesIa.Calificar, ct);
        if (permiso is not null) return Result<CalificacionIaDto>.Fail(permiso);

        var usuario =
            $"Asignatura: {Texto(r.Asignatura, 120) ?? "no indicada"}\nGrado: {Texto(r.Grado, 120) ?? "no indicado"}\n" +
            $"Actividad: {actividad}\nValor: {r.Puntos} puntos\n" +
            (Texto(r.Descripcion, 1000) is { } d ? $"Descripción de la actividad: {d}\n" : "") +
            (Texto(r.Criterios, 3000) is { } c ? $"Criterios o clave del docente:\n{c}\n" : "Sin clave: evalúa con lo que se espera para el grado.\n");
        var sistema = Contexto + "\n\nAyudas a un docente a calificar el trabajo escrito de un estudiante a partir de fotos. " +
            "Lee el trabajo, compáralo con los criterios o la clave del docente y sugiere una nota entre 0 y el valor de la " +
            "actividad, en múltiplos de 0.5. En la justificación (de 2 a 4 oraciones, para el docente) di qué está bien, qué " +
            "falta o está mal y por qué esa nota. No menciones nombres que aparezcan en la hoja. Si las fotos no se leen o no " +
            "son un trabajo escolar, marca legible como falso.";
        var resultado = await LlamarAsync<CalificacionLeida>(FuncionesIa.Calificar,
            new PeticionIa(sistema, usuario, EsquemaCalificacion, 3000, Breve: false, Imagenes: fotos), ct);
        if (!resultado.IsSuccess) return Result<CalificacionIaDto>.Fail(resultado.Error!);
        var leida = resultado.Value;
        if (!leida.Legible)
            return Result<CalificacionIaDto>.Fail(Error.Validation("No se pudo leer el trabajo en las fotos. Toma otra con buena luz y de frente."));
        var nota = Math.Clamp(Math.Round(leida.Nota * 2, MidpointRounding.AwayFromZero) / 2, 0, r.Puntos);
        return new CalificacionIaDto(nota, leida.Justificacion.Trim());
    }

    private sealed record CalificacionLeida(bool Legible, decimal Nota, string Justificacion);

    private static readonly Dictionary<string, JsonElement> EsquemaCalificacion = Esquema(new
    {
        type = "object",
        additionalProperties = false,
        required = new[] { "legible", "nota", "justificacion" },
        properties = new
        {
            legible = new { type = "boolean" },
            nota = new { type = "number" },
            justificacion = new { type = "string" },
        },
    });

    // ── Apoyo ────────────────────────────────────────────────────────────────

    /// <summary>Pro por su cuenta personal o por su centro.</summary>
    private async Task<(bool Habilitada, Guid? Institucion)> HabilitadaAsync(CancellationToken ct)
    {
        var yo = currentUser.RequireUserId();
        var cuenta = await db.Users.AsNoTracking().Where(u => u.Id == yo)
            .Select(u => new { u.TenantId, u.InstitucionId }).FirstAsync(ct);
        var porCentro = cuenta.InstitucionId is { } i && await db.Instituciones.AnyAsync(x => x.Id == i && x.Activa && x.ConIa, ct);
        var porCuenta = cuenta.TenantId is { } t && await db.Tenants.IgnoreQueryFilters().AnyAsync(x => x.Id == t && x.IsActive && x.ConIa, ct);
        return (porCentro || porCuenta, cuenta.InstitucionId);
    }

    private DateTimeOffset InicioDelMes()
    {
        return ClienteIa.InicioDelMes(clock.Today);
    }

    private async Task<(int Generaciones, int Comentarios, int Calificaciones)> UsadosAsync(CancellationToken ct)
    {
        var yo = currentUser.RequireUserId();
        var desde = InicioDelMes();
        var usos = await db.UsosIa.Where(u => u.UsuarioId == yo && u.CreatedAt >= desde)
            .GroupBy(u => u.Funcion).Select(g => new { g.Key, N = g.Count() }).ToDictionaryAsync(x => x.Key, x => x.N, ct);
        return (usos.GetValueOrDefault(FuncionesIa.Plan) + usos.GetValueOrDefault(FuncionesIa.Examen),
            usos.GetValueOrDefault(FuncionesIa.Comentario), usos.GetValueOrDefault(FuncionesIa.Calificar));
    }

    private async Task<Error?> PuedeAsync(string funcion, CancellationToken ct)
    {
        if (!ia.Disponible) return Error.Forbidden("El asistente con IA no está disponible en este momento.");
        var (habilitada, _) = await HabilitadaAsync(ct);
        if (!habilitada) return Error.Forbidden("El asistente con IA es parte del plan Pro.");
        var (generaciones, comentarios, calificaciones) = await UsadosAsync(ct);
        return funcion switch
        {
            FuncionesIa.Comentario => comentarios >= LimiteComentarios ? Error.Validation($"Ya usaste los {LimiteComentarios} comentarios de este mes.") : null,
            FuncionesIa.Calificar => calificaciones >= LimiteCalificaciones ? Error.Validation($"Ya usaste las {LimiteCalificaciones} calificaciones con foto de este mes.") : null,
            _ => generaciones >= LimiteGeneraciones ? Error.Validation($"Ya usaste las {LimiteGeneraciones} generaciones de este mes.") : null,
        };
    }

    private async Task<Result<T>> LlamarAsync<T>(string funcion, PeticionIa peticion, CancellationToken ct)
    {
        var (_, institucion) = await HabilitadaAsync(ct);
        return await ia.JsonAsync<T>(funcion, peticion, currentUser.RequireUserId(), institucion, ct);
    }

    private async Task<Result<string>> LlamarAsync(string funcion, PeticionIa peticion, CancellationToken ct)
    {
        var (_, institucion) = await HabilitadaAsync(ct);
        return await ia.TextoAsync(funcion, peticion, currentUser.RequireUserId(), institucion, ct);
    }

    private static string? Texto(string? valor, int maximo) => ClienteIa.Texto(valor, maximo);

    private static string Clave(string nombre) => nombre.Trim().ToUpperInvariant();

    private static Dictionary<string, JsonElement> Esquema(object schema) => ClienteIa.Esquema(schema);

    private static readonly Dictionary<string, JsonElement> EsquemaPlan = Esquema(new
    {
        type = "object",
        additionalProperties = false,
        required = new[] { "rubros" },
        properties = new
        {
            rubros = new
            {
                type = "array",
                items = new
                {
                    type = "object",
                    additionalProperties = false,
                    required = new[] { "nombre", "puntos", "actividades" },
                    properties = new
                    {
                        nombre = new { type = "string" },
                        puntos = new { type = "number" },
                        actividades = new
                        {
                            type = "array",
                            items = new
                            {
                                type = "object",
                                additionalProperties = false,
                                required = new[] { "titulo", "puntos", "descripcion", "semana" },
                                properties = new
                                {
                                    titulo = new { type = "string" },
                                    puntos = new { type = "number" },
                                    descripcion = new { type = "string" },
                                    semana = new { type = "integer" },
                                },
                            },
                        },
                    },
                },
            },
        },
    });

    private static readonly Dictionary<string, JsonElement> EsquemaExamen = Esquema(new
    {
        type = "object",
        additionalProperties = false,
        required = new[] { "titulo", "instrucciones", "preguntas" },
        properties = new
        {
            titulo = new { type = "string" },
            instrucciones = new { type = "string" },
            preguntas = new
            {
                type = "array",
                items = new
                {
                    type = "object",
                    additionalProperties = false,
                    required = new[] { "tipo", "enunciado", "opciones", "respuesta", "puntos" },
                    properties = new
                    {
                        tipo = new { type = "string", @enum = TiposPregunta },
                        enunciado = new { type = "string" },
                        opciones = new { type = "array", items = new { type = "string" } },
                        respuesta = new { type = "string" },
                        puntos = new { type = "number" },
                    },
                },
            },
        },
    });
}
