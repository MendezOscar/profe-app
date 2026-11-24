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
public sealed partial class AsistenteIaService(
    AppDbContext db,
    ClienteIa ia,
    ICurrentUser currentUser,
    IClock clock,
    IProgramasCurriculares programas) : IAsistenteIaService
{
    /// <summary>Se agrega a los avisos de saldo agotado.</summary>
    public const string Ampliar = " Se renueva el día 1; si necesitas más, escríbenos a ProfeApp.";

    /// <summary>Trabajos por envío de una tanda (cuida el tamaño de la petición).</summary>
    public const int TrabajosPorTanda = 10;

    /// <summary>Días que se guardan las sugerencias de una tanda.</summary>
    public const int DiasTanda = 7;

    private const int MaxFoto = 2 * 1024 * 1024;

    private const string Contexto = ClienteIa.Contexto;

    /// Tablas progresivas de evaluación y ponderación por parcial (Acuerdo 0158-SE-2025).
    private const string Tabla0158 =
        "- Básica I ciclo (1.° a 3.°): Actividades de aula 45, Actividades extra aula 10, Valores y actitudes 10, " +
        "Expresiones artísticas, deportivas y humanísticas 5, Exámenes escritos/prácticos 30.\n" +
        "- Básica II ciclo (4.° a 6.°): Actividades de aula 35, Actividades extra aula 10, Valores y actitudes 10, " +
        "Expresiones artísticas, deportivas y humanísticas 5, Exámenes escritos/prácticos 40.\n" +
        "- Básica III ciclo (7.° a 9.°): Actividades de aula 25, Actividades extra aula 10, Valores y actitudes 10, " +
        "Expresiones artísticas, deportivas y humanísticas 5, Exámenes escritos/prácticos 50.\n" +
        "- Media (10.° a 12.°, Ciencias y Humanidades y formación de fundamento del BTP): Actividades de aula 35, " +
        "Actividades extra aula 10, Valores y actitudes 5, Examen escrito/práctico 50.\n" +
        "- Formación específica (taller o laboratorio) del BTP: Actividades de taller/laboratorio 60, " +
        "Actividades extra aula 10, Valores y actitudes 10, Examen escrito/práctico 20.";

    private static readonly string[] TiposPregunta = ["opcion_multiple", "verdadero_falso", "respuesta_corta", "desarrollo"];

    public async Task<EstadoIaDto> EstadoAsync(CancellationToken ct = default)
    {
        var (habilitada, _, saldo) = await HabilitadaAsync(ct);
        return new EstadoIaDto(habilitada, ia.Disponible, CreditosIa.Creditos(await UsadosAsync(ct)), saldo / 2);
    }

    // ── Plan del parcial ─────────────────────────────────────────────────────

    public async Task<Result<PlanIaDto>> PlanAsync(PlanIaRequest r, CancellationToken ct = default)
    {
        var asignatura = Texto(r.Asignatura, 120);
        var temas = Texto(r.Temas, 2000);
        if (asignatura is null) return Result<PlanIaDto>.Fail(Error.Validation("Falta la asignatura."));
        var programa = programas.Contexto(r.Modalidad, r.Grado, asignatura, r.Parcial, r.Resultados);
        if (temas is null && programa is null)
            return Result<PlanIaDto>.Fail(Error.Validation("Escribe los temas del parcial (hasta 2000 caracteres)."));
        if (r.Semanas is < 1 or > 12) return Result<PlanIaDto>.Fail(Error.Validation("El parcial dura de 1 a 12 semanas."));
        if (r.Total is <= 0 or > 1000) return Result<PlanIaDto>.Fail(Error.Validation("El total de puntos no es válido."));
        var rubros = (r.Rubros ?? []).Where(x => !string.IsNullOrWhiteSpace(x.Nombre)).Take(15).ToList();

        var permiso = await PuedeAsync(CreditosIa.Medios(FuncionesIa.Plan), ct);
        if (permiso is not null) return Result<PlanIaDto>.Fail(permiso);

        var usuario =
            $"Asignatura: {asignatura}\nGrado: {Texto(r.Grado, 120) ?? "no indicado"}\nParcial: {Texto(r.Parcial, 60) ?? "no indicado"}\n" +
            $"Duración: {r.Semanas} semanas\nTotal del parcial: {r.Total} puntos\n\n" +
            (programa is null ? "" : programa + "\n") +
            (temas is null ? "" : $"{(programa is null ? "Temas" : "Indicaciones del docente")}:\n{temas}\n") + "\n" +
            (rubros.Count > 0
                ? "Usa exactamente estos rubros con sus puntos y reparte cada uno en actividades:\n" +
                  string.Join("\n", rubros.Select(x => $"- {Texto(x.Nombre, 80)}: {x.Puntos} puntos"))
                : $"Usa como rubros los de la tabla oficial del Acuerdo 0158-SE-2025 que corresponde al grado, con sus puntos " +
                  $"llevados a {r.Total} en la misma proporción:\n{Tabla0158}\nSi el grado no se puede ubicar en la tabla, " +
                  $"propón de 3 a 5 rubros que sumen {r.Total} puntos.");
        var sistema = Contexto + "\n\nArma el plan de evaluación de un parcial: rubros con puntos y, en cada rubro, " +
            "actividades concretas con título corto, puntos, una descripción de una o dos oraciones para el estudiante y " +
            "la semana del parcial en que va. Los puntos de las actividades de un rubro suman exactamente los del rubro. " +
            "Reparte las actividades a lo largo de las semanas y deja el examen para la última." +
            (programa is null ? "" : " Si viene el programa oficial, las actividades trabajan sus contenidos y criterios de " +
                "evaluación: cubre todos los criterios del parcial y, al final de la descripción de cada actividad, pon entre " +
                "paréntesis los códigos que evalúa, por ejemplo (CE1.2, CE1.3). En Básica, en lugar de códigos, nombra el " +
                "estándar que trabaja.");

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
        var programa = r.Resultados is { Count: > 0 } || r.Parcial is not null
            ? programas.Contexto(r.Modalidad, r.Grado, asignatura, r.Parcial, r.Resultados)
            : null;
        if (temas is null && programa is null)
            return Result<ExamenIaDto>.Fail(Error.Validation("Escribe los temas del examen (hasta 2000 caracteres)."));
        if (r.Preguntas is < 3 or > 40) return Result<ExamenIaDto>.Fail(Error.Validation("El examen lleva de 3 a 40 preguntas."));
        if (r.Puntos is <= 0 or > 100) return Result<ExamenIaDto>.Fail(Error.Validation("El examen vale de 1 a 100 puntos."));
        var tipos = (r.Tipos ?? []).Where(TiposPregunta.Contains).Distinct().ToList();
        if (tipos.Count == 0) return Result<ExamenIaDto>.Fail(Error.Validation("Elige al menos un tipo de pregunta."));

        var permiso = await PuedeAsync(CreditosIa.Medios(FuncionesIa.Examen), ct);
        if (permiso is not null) return Result<ExamenIaDto>.Fail(permiso);

        var usuario =
            $"Asignatura: {asignatura}\nGrado: {Texto(r.Grado, 120) ?? "no indicado"}\nPreguntas: {r.Preguntas}\n" +
            $"Valor total: {r.Puntos} puntos\nTipos de pregunta: {string.Join(", ", tipos)}\n\n" +
            (programa is null ? "" : programa + "\n") +
            (temas is null ? "" : $"{(programa is null ? "Temas" : "Indicaciones del docente")}:\n{temas}");
        var sistema = Contexto + "\n\nRedacta un examen escrito para imprimir. Usa solo los tipos de pregunta pedidos, " +
            "mezclados y de dificultad progresiva, adecuados al grado. Opción múltiple: cuatro opciones sin letras, una sola " +
            "correcta, y en la respuesta el texto de la correcta. Verdadero o falso: sin opciones; respuesta «Verdadero» o " +
            "«Falso». Respuesta corta y desarrollo: sin opciones; en la respuesta, lo que se espera para dar todos los puntos. " +
            "Los puntos de las preguntas suman exactamente el valor total. Instrucciones generales breves." +
            (programa is null ? "" : " Si viene el programa oficial, las preguntas evalúan sus criterios de evaluación y " +
                "contenidos, repartidas entre todos.");

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

        var permiso = await PuedeAsync(CreditosIa.Medios(FuncionesIa.Comentario), ct);
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

    // ── Portafolio docente ───────────────────────────────────────────────────

    public async Task<Result<PresentacionIaDto>> PresentacionAsync(PresentacionIaRequest r, CancellationToken ct = default)
    {
        var asignaturas = (r.Asignaturas ?? []).Select(a => Texto(a, 120)).OfType<string>().Distinct().Take(20).ToList();
        if (asignaturas.Count == 0) return Result<PresentacionIaDto>.Fail(Error.Validation("Importa tus cuadros primero."));
        var permiso = await PuedeAsync(CreditosIa.Medios(FuncionesIa.Presentacion), ct);
        if (permiso is not null) return Result<PresentacionIaDto>.Fail(permiso);

        var usuario = $"Nivel: {Texto(r.Nivel, 40) ?? "no indicado"}\nAsignaturas y grados que imparte:\n" +
            string.Join("\n", asignaturas.Select(a => "- " + a)) +
            (Texto(r.Indicaciones, 500) is { } i ? $"\nEl docente quiere destacar: {i}" : "");
        var sistema = Contexto + "\n\nRedacta la presentación del portafolio docente del año (formato de la Secretaría de " +
            "Educación): una introducción de dos o tres párrafos cortos en primera persona, que explique qué reúne el " +
            "portafolio, para qué sirve (organizar la práctica, evaluar y mejorar) y el compromiso con el aprendizaje de los " +
            "estudiantes de esas asignaturas, y de 3 a 5 objetivos que empiecen con un verbo en infinitivo. Sin nombres de " +
            "personas ni del centro, sin fechas y sin frases de relleno.";
        return await LlamarAsync<PresentacionIaDto>(FuncionesIa.Presentacion,
            new PeticionIa(sistema, usuario, EsquemaPresentacion, 2000, Breve: true), ct);
    }

    public async Task<Result<NivelacionIaDto>> NivelacionAsync(NivelacionIaRequest r, CancellationToken ct = default)
    {
        var asignatura = Texto(r.Asignatura, 120);
        if (asignatura is null) return Result<NivelacionIaDto>.Fail(Error.Validation("Falta la asignatura."));
        var alumnos = (r.Alumnos ?? []).Where(a => IdValido().IsMatch(a.Codigo ?? "")).Take(60).ToList();
        if (alumnos.Count == 0) return Result<NivelacionIaDto>.Fail(Error.Validation("Ningún alumno está bajo 70."));
        var permiso = await PuedeAsync(CreditosIa.Medios(FuncionesIa.Nivelacion), ct);
        if (permiso is not null) return Result<NivelacionIaDto>.Fail(permiso);

        var usuario = $"Asignatura: {asignatura}\nGrado: {Texto(r.Grado, 120) ?? "no indicado"}\nNota mínima para aprobar: 70\n\n" +
            string.Join("\n", alumnos.Select(a =>
                $"{a.Codigo}: {string.Join(", ", (a.Parciales ?? []).Take(4).Select(p => Texto(p, 40)))}; ausencias {a.Ausencias}" +
                ((a.Rubros ?? []).Count > 0
                    ? "; último parcial por rubro: " + string.Join(", ", a.Rubros!.Take(10).Select(x => $"{Texto(x.Nombre, 60)} {x.Obtenido} de {x.Posible}"))
                    : "")));
        var sistema = Contexto + "\n\nPara el plan de nivelación y mejora de los aprendizajes del portafolio docente, escribe " +
            "una acción de mejora concreta para cada estudiante (uno por código): qué va a hacer el docente con él, " +
            "según sus rubros más bajos y su asistencia, en una sola oración de máximo 25 palabras, sin repetir la misma " +
            "acción para todos. Devuelve una acción por cada código recibido.";
        var resultado = await LlamarAsync<NivelacionIaDto>(FuncionesIa.Nivelacion,
            new PeticionIa(sistema, usuario, EsquemaNivelacion, 4000, Breve: true), ct);
        if (!resultado.IsSuccess) return resultado;
        var codigos = alumnos.Select(a => a.Codigo).ToHashSet();
        return new NivelacionIaDto(resultado.Value.Acciones.Where(a => codigos.Contains(a.Codigo)).ToList());
    }

    private static readonly Dictionary<string, JsonElement> EsquemaPresentacion = Esquema(new
    {
        type = "object",
        additionalProperties = false,
        required = new[] { "introduccion", "objetivos" },
        properties = new
        {
            introduccion = new { type = "string" },
            objetivos = new { type = "array", items = new { type = "string" } },
        },
    });

    private static readonly Dictionary<string, JsonElement> EsquemaNivelacion = Esquema(new
    {
        type = "object",
        additionalProperties = false,
        required = new[] { "acciones" },
        properties = new
        {
            acciones = new
            {
                type = "array",
                items = new
                {
                    type = "object",
                    additionalProperties = false,
                    required = new[] { "codigo", "accion" },
                    properties = new { codigo = new { type = "string" }, accion = new { type = "string" } },
                },
            },
        },
    });

    // ── Calificar desde una foto ─────────────────────────────────────────────

    public async Task<Result<CalificacionIaDto>> CalificarAsync(CalificarIaRequest r, CancellationToken ct = default)
    {
        var actividad = Texto(r.Actividad, 160);
        if (actividad is null) return Result<CalificacionIaDto>.Fail(Error.Validation("Falta la actividad."));
        if (r.Puntos is <= 0 or > 100) return Result<CalificacionIaDto>.Fail(Error.Validation("La actividad debe valer de 1 a 100 puntos."));
        var (fotos, error) = Fotos(r.Imagenes);
        if (error is not null) return Result<CalificacionIaDto>.Fail(error);

        var medios = CreditosIa.Trabajo(FuncionesIa.Calificar, fotos.Count);
        var permiso = await PuedeAsync(medios, ct);
        if (permiso is not null) return Result<CalificacionIaDto>.Fail(permiso);

        var resultado = await LlamarAsync<CalificacionLeida>(FuncionesIa.Calificar,
            new PeticionIa(SistemaCalificar, DatosActividad(r.Asignatura, r.Grado, actividad, r.Puntos, r.Descripcion, r.Criterios),
                EsquemaCalificacion, 3000, Breve: false, Imagenes: fotos), ct, medios);
        if (!resultado.IsSuccess) return Result<CalificacionIaDto>.Fail(resultado.Error!);
        var leida = resultado.Value;
        if (!leida.Legible)
            return Result<CalificacionIaDto>.Fail(Error.Validation("No se pudo leer el trabajo en las fotos. Toma otra con buena luz y de frente."));
        return new CalificacionIaDto(Redondear(leida.Nota, r.Puntos), leida.Justificacion.Trim());
    }

    public sealed record CalificacionLeida(bool Legible, decimal Nota, string Justificacion);

    private const string SistemaCalificar = Contexto + "\n\nAyudas a un docente a calificar el trabajo escrito de un estudiante a partir de fotos. " +
        "Lee el trabajo, compáralo con los criterios o la clave del docente y sugiere una nota entre 0 y el valor de la " +
        "actividad, en múltiplos de 0.5. En la justificación (de 2 a 4 oraciones, para el docente) di qué está bien, qué " +
        "falta o está mal y por qué esa nota. No menciones nombres que aparezcan en la hoja. Si las fotos no se leen o no " +
        "son un trabajo escolar, marca legible como falso.";

    private static string DatosActividad(string? asignatura, string? grado, string actividad, decimal puntos, string? descripcion, string? criterios) =>
        $"Asignatura: {Texto(asignatura, 120) ?? "no indicada"}\nGrado: {Texto(grado, 120) ?? "no indicado"}\n" +
        $"Actividad: {actividad}\nValor: {puntos} puntos\n" +
        (Texto(descripcion, 1000) is { } d ? $"Descripción de la actividad: {d}\n" : "") +
        (Texto(criterios, 3000) is { } c ? $"Criterios o clave del docente:\n{c}\n" : "Sin clave: evalúa con lo que se espera para el grado.\n");

    /// <summary>De 1 a 4 fotos JPG de hasta 2 MB.</summary>
    private static (List<byte[]> Fotos, Error? Error) Fotos(IReadOnlyList<string>? imagenes)
    {
        var fotos = new List<byte[]>();
        foreach (var b64 in (imagenes ?? []).Take(5))
        {
            byte[] foto;
            try { foto = Convert.FromBase64String(b64); }
            catch (FormatException) { return (fotos, Error.Validation("Una de las fotos no se pudo leer.")); }
            if (foto.Length is < 4 or > MaxFoto || foto[0] != 0xFF || foto[1] != 0xD8)
                return (fotos, Error.Validation("Las fotos deben ser JPG de hasta 2 MB."));
            fotos.Add(foto);
        }
        return fotos.Count is < 1 or > 4 ? (fotos, Error.Validation("Envía de 1 a 4 fotos de cada trabajo.")) : (fotos, null);
    }

    /// <summary>La nota sugerida en medios puntos, dentro del valor de la actividad.</summary>
    public static decimal Redondear(decimal nota, decimal puntos) =>
        Math.Clamp(Math.Round(nota * 2, MidpointRounding.AwayFromZero) / 2, 0, puntos);

    // ── Calificar en tanda ───────────────────────────────────────────────────

    public async Task<Result<TandaIaDto>> CalificarTandaAsync(CalificarTandaIaRequest r, CancellationToken ct = default)
    {
        var actividadId = Texto(r.ActividadId, 64);
        var actividad = Texto(r.Actividad, 160);
        if (actividadId is null || actividad is null) return Result<TandaIaDto>.Fail(Error.Validation("Falta la actividad."));
        if (r.Puntos is <= 0 or > 100) return Result<TandaIaDto>.Fail(Error.Validation("La actividad debe valer de 1 a 100 puntos."));
        var trabajos = r.Trabajos ?? [];
        if (trabajos.Count is < 1 or > TrabajosPorTanda)
            return Result<TandaIaDto>.Fail(Error.Validation($"Envía de 1 a {TrabajosPorTanda} trabajos a la vez."));
        var peticiones = new List<(string, PeticionIa)>();
        var paginas = new Dictionary<string, int>();
        // La clave va en el sistema: es igual para todos los trabajos de la tanda.
        var sistema = SistemaCalificar + "\n\n" + DatosActividad(r.Asignatura, r.Grado, actividad, r.Puntos, r.Descripcion, r.Criterios);
        foreach (var t in trabajos)
        {
            var alumno = Texto(t.AlumnoId, 64);
            if (alumno is null || !IdValido().IsMatch(alumno) || paginas.ContainsKey(alumno))
                return Result<TandaIaDto>.Fail(Error.Validation("Cada trabajo debe ser de un alumno distinto."));
            var (fotos, error) = Fotos(t.Imagenes);
            if (error is not null) return Result<TandaIaDto>.Fail(error);
            peticiones.Add((alumno, new PeticionIa(sistema, "Califica este trabajo.", EsquemaCalificacion, 3000, Breve: false, Imagenes: fotos)));
            paginas[alumno] = fotos.Count;
        }

        if (!ia.Disponible) return Result<TandaIaDto>.Fail(Error.Forbidden("El asistente con IA no está disponible en este momento."));
        var (habilitada, institucion, saldo) = await HabilitadaAsync(ct);
        if (!habilitada) return Result<TandaIaDto>.Fail(Error.Forbidden("El asistente con IA es parte del plan Pro."));
        var medios = paginas.Values.Sum(n => CreditosIa.Trabajo(FuncionesIa.CalificarTanda, n));
        if (await NoAlcanzaAsync(medios, saldo, ct) is { } falta) return Result<TandaIaDto>.Fail(falta);

        string lote;
        try
        {
            lote = await ia.CrearLoteAsync(peticiones, ct);
        }
        catch (Exception e) when (e is not OperationCanceledException)
        {
            return Result<TandaIaDto>.Fail(Error.Validation("La IA no recibió la tanda. Intenta de nuevo en un momento."));
        }
        var tanda = new TandaIa
        {
            UsuarioId = currentUser.RequireUserId(), InstitucionId = institucion, Actividad = actividadId, Lote = lote,
            Trabajos = peticiones.Count, Puntos = r.Puntos, Medios = medios,
            Paginas = JsonSerializer.Serialize(paginas, ClienteIa.Json),
        };
        db.TandasIa.Add(tanda);
        await db.SaveChangesAsync(ct);
        return Dto(tanda);
    }

    public async Task<IReadOnlyList<TandaIaDto>> TandasAsync(string actividad, CancellationToken ct = default)
    {
        var yo = currentUser.RequireUserId();
        var desde = clock.Now.AddDays(-DiasTanda);
        var tandas = await db.TandasIa.AsNoTracking()
            .Where(t => t.UsuarioId == yo && t.Actividad == actividad && t.CreatedAt >= desde)
            .OrderBy(t => t.CreatedAt).ToListAsync(ct);
        return tandas.Select(Dto).ToList();
    }

    private static TandaIaDto Dto(TandaIa t) => new(t.Id, t.Estado, t.Trabajos, t.CreatedAt,
        t.Resultados is null ? [] : JsonSerializer.Deserialize<List<ResultadoTandaIaDto>>(t.Resultados, ClienteIa.Json)!);

    public static readonly Dictionary<string, JsonElement> EsquemaCalificacion = Esquema(new
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

    /// <summary>
    /// Pro por su cuenta personal (140 créditos) o por su centro (75), cada uno por su
    /// multiplicador; si tiene los dos, vale el mayor. El saldo va en medios créditos.
    /// </summary>
    private async Task<(bool Habilitada, Guid? Institucion, int Saldo)> HabilitadaAsync(CancellationToken ct)
    {
        var yo = currentUser.RequireUserId();
        var cuenta = await db.Users.AsNoTracking().Where(u => u.Id == yo)
            .Select(u => new { u.TenantId, u.InstitucionId }).FirstAsync(ct);
        var porCentro = cuenta.InstitucionId is { } i
            ? await db.Instituciones.Where(x => x.Id == i && x.Activa && x.ConIa).Select(x => (int?)x.IaMultiplicador).FirstOrDefaultAsync(ct)
            : null;
        var porCuenta = cuenta.TenantId is { } t
            ? await db.Tenants.IgnoreQueryFilters().Where(x => x.Id == t && x.IsActive && x.ConIa).Select(x => (int?)x.IaMultiplicador).FirstOrDefaultAsync(ct)
            : null;
        var saldo = Math.Max(
            porCuenta is { } c ? CreditosIa.SaldoDocente * Math.Max(1, c) : 0,
            porCentro is { } m ? CreditosIa.SaldoDocenteCentro * Math.Max(1, m) : 0);
        return (porCentro is not null || porCuenta is not null, cuenta.InstitucionId, saldo);
    }

    private DateTimeOffset InicioDelMes() => ClienteIa.InicioDelMes(clock.Today);

    /// <summary>Medios créditos usados este mes, más los apartados por tandas en proceso.</summary>
    private async Task<int> UsadosAsync(CancellationToken ct)
    {
        var yo = currentUser.RequireUserId();
        var desde = InicioDelMes();
        var usados = await db.UsosIa
            .Where(u => u.UsuarioId == yo && u.CreatedAt >= desde && CreditosIa.DelDocente.Contains(u.Funcion))
            .SumAsync(u => u.Medios, ct);
        var apartados = await db.TandasIa
            .Where(t => t.UsuarioId == yo && t.Estado == EstadosTanda.Procesando && t.CreatedAt >= desde)
            .SumAsync(t => t.Medios, ct);
        return usados + apartados;
    }

    private async Task<Error?> NoAlcanzaAsync(int medios, int saldo, CancellationToken ct)
    {
        var quedan = saldo - await UsadosAsync(ct);
        if (medios <= quedan) return null;
        return Error.Validation(quedan <= 0
            ? $"Ya usaste los {saldo / 2} créditos de IA de este mes.{Ampliar}"
            : $"No te alcanzan los créditos: esto usa {CreditosIa.Creditos(medios)} y te quedan {CreditosIa.Creditos(quedan)} de {saldo / 2}.{Ampliar}");
    }

    private async Task<Error?> PuedeAsync(int medios, CancellationToken ct)
    {
        if (!ia.Disponible) return Error.Forbidden("El asistente con IA no está disponible en este momento.");
        var (habilitada, _, saldo) = await HabilitadaAsync(ct);
        if (!habilitada) return Error.Forbidden("El asistente con IA es parte del plan Pro.");
        return await NoAlcanzaAsync(medios, saldo, ct);
    }

    /// <summary>El id del alumno va como id de la petición en el lote: letras, números, - y _.</summary>
    [System.Text.RegularExpressions.GeneratedRegex("^[A-Za-z0-9_-]{1,64}$")]
    private static partial System.Text.RegularExpressions.Regex IdValido();

    private async Task<Result<T>> LlamarAsync<T>(string funcion, PeticionIa peticion, CancellationToken ct, int? medios = null)
    {
        var (_, institucion, _) = await HabilitadaAsync(ct);
        return await ia.JsonAsync<T>(funcion, peticion, currentUser.RequireUserId(), institucion, ct, medios);
    }

    private async Task<Result<string>> LlamarAsync(string funcion, PeticionIa peticion, CancellationToken ct)
    {
        var (_, institucion, _) = await HabilitadaAsync(ct);
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
