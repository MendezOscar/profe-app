using System.Collections.Concurrent;
using System.Threading.Channels;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Contracts;
using ProfeApp.Domain.Centros;
using ProfeApp.Domain.Common;
using ProfeApp.Infrastructure.Centros;
using ProfeApp.Infrastructure.Persistence;

namespace ProfeApp.Infrastructure.Ia;

/// <summary>Redactar los comentarios de boleta de una sección en un parcial.</summary>
public sealed record TrabajoBoletas(Guid InstitucionId, string Centro, Guid SeccionId, int Parcial, bool Todos, Guid UsuarioId);

/// <summary>Cola en memoria; una sección y parcial no se encola dos veces mientras se procesa.</summary>
public sealed class ColaBoletas
{
    private readonly Channel<TrabajoBoletas> _canal = Channel.CreateUnbounded<TrabajoBoletas>();
    private readonly ConcurrentDictionary<(Guid, int), byte> _enProceso = new();

    public ChannelReader<TrabajoBoletas> Lector => _canal.Reader;

    public bool EnProceso(Guid seccion, int parcial) => _enProceso.ContainsKey((seccion, parcial));

    public bool Encolar(TrabajoBoletas t) =>
        _enProceso.TryAdd((t.SeccionId, t.Parcial), 0) && _canal.Writer.TryWrite(t);

    public void Terminar(TrabajoBoletas t) => _enProceso.TryRemove((t.SeccionId, t.Parcial), out _);
}

/// <summary>
/// Saca trabajos de la cola y redacta un comentario por alumno, de a cuatro a la vez. Al
/// modelo van las notas, la conducta, las faltas y el conteo de incidencias, sin nombres.
/// </summary>
public sealed class ServicioBoletas(ColaBoletas cola, IServiceScopeFactory scopes, ILogger<ServicioBoletas> log) : BackgroundService
{
    private const int AlaVez = 4;
    private static readonly string[] Romanos = ["I", "II", "III", "IV"];

    private const string Sistema = ClienteIa.Contexto +
        "\n\nRedacta el comentario de la boleta de un estudiante para su familia: de 2 a 3 oraciones, en tercera persona, " +
        "llamándolo «el estudiante». Empieza por un logro concreto, señala con respeto la asignatura o el aspecto que más " +
        "debe mejorar y cierra con una recomendación para la casa. Sin cifras salvo que ayuden. Sin saludos ni firma. " +
        "Responde solo con el comentario.";

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await foreach (var trabajo in cola.Lector.ReadAllAsync(stoppingToken))
        {
            try
            {
                await ProcesarAsync(trabajo, stoppingToken);
            }
            catch (Exception e) when (e is not OperationCanceledException)
            {
                log.LogError(e, "Falló la redacción de comentarios de boleta de la sección {Seccion}", trabajo.SeccionId);
            }
            finally
            {
                cola.Terminar(trabajo);
            }
        }
    }

    private async Task ProcesarAsync(TrabajoBoletas t, CancellationToken ct)
    {
        await using var scope = scopes.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var generador = scope.ServiceProvider.GetRequiredService<IGeneradorIa>();
        var consolidado = await scope.ServiceProvider.GetRequiredService<ConsolidadoService>()
            .DeSeccionAsync(t.InstitucionId, t.Centro, t.SeccionId, ct);
        if (consolidado is null) return;

        var existentes = await db.ComentariosBoleta.Where(c => c.SeccionId == t.SeccionId && c.Parcial == t.Parcial)
            .ToDictionaryAsync(c => c.AlumnoId, ct);
        var inicio = await (from s in db.Secciones join a in db.AniosLectivos on s.AnioLectivoId equals a.Id
                            where s.Id == t.SeccionId select a.Inicio).FirstAsync(ct);
        var incidencias = (await db.Incidencias.AsNoTracking()
                .Where(i => i.InstitucionId == t.InstitucionId && i.Fecha >= inicio)
                .Select(i => new { i.AlumnoId, i.Gravedad }).ToListAsync(ct))
            .ToLookup(i => i.AlumnoId, i => i.Gravedad);

        var pendientes = consolidado.Alumnos
            .Where(a => a.EstadoMatricula == EstadosMatricula.Activa)
            .Where(a => !existentes.TryGetValue(a.AlumnoId, out var c) || (t.Todos && c.DeIa))
            .ToList();

        using var turno = new SemaphoreSlim(AlaVez);
        var resultados = await Task.WhenAll(pendientes.Select(async a =>
        {
            await turno.WaitAsync(ct);
            try
            {
                var r = await generador.GenerarAsync(new PeticionIa(Sistema, Datos(consolidado, a, t.Parcial, incidencias[a.AlumnoId]), null, 600, Breve: true), ct);
                return (a.AlumnoId, Respuesta: (RespuestaIa?)r);
            }
            catch (Exception e) when (e is not OperationCanceledException)
            {
                log.LogWarning(e, "Sin comentario de boleta para un alumno de la sección {Seccion}", t.SeccionId);
                return (a.AlumnoId, Respuesta: (RespuestaIa?)null);
            }
            finally
            {
                turno.Release();
            }
        }));

        foreach (var (alumno, r) in resultados)
        {
            if (r is null) continue;
            db.UsosIa.Add(ClienteIa.Uso(FuncionesIa.Boleta, r, t.UsuarioId, t.InstitucionId));
            var texto = r.Texto.Trim();
            if (r.Rechazada || texto.Length == 0) continue;
            if (texto.Length > 1000) texto = texto[..1000];
            var fila = existentes.GetValueOrDefault(alumno)
                       ?? db.ComentariosBoleta.Add(new ComentarioBoleta
                       {
                           InstitucionId = t.InstitucionId, SeccionId = t.SeccionId, AlumnoId = alumno, Parcial = t.Parcial,
                       }).Entity;
            fila.Texto = texto;
            fila.DeIa = true;
        }
        await db.SaveChangesAsync(ct);
    }

    /// <summary>Lo de un alumno hasta el parcial pedido, sin nombre ni identidad.</summary>
    private static string Datos(ConsolidadoDto c, AlumnoConsolidadoDto a, int parcial, IEnumerable<string> incidencias)
    {
        var lineas = new List<string>
        {
            $"Grado y sección: {c.Seccion}",
            $"Comentario para la boleta del parcial {Romanos[parcial - 1]} (nota mínima para aprobar: {c.NotaMinima})",
            "Notas por asignatura (parciales cerrados hasta ahora):",
        };
        for (var i = 0; i < c.Asignaturas.Count; i++)
        {
            if (a.Notas[i] is not { } n) continue;
            var parciales = n.Parciales.Take(parcial).Select((p, j) => $"{Romanos[j]}: {(p is { } v ? v.ToString() : "sin cerrar")}");
            lineas.Add($"- {c.Asignaturas[i].Nombre}: {string.Join(", ", parciales)}");
        }
        if (a.Conducta is { } conducta && conducta.Take(parcial).Any(x => x is not null))
            lineas.Add("Conducta (A es la mejor, E la más baja): " +
                string.Join(", ", conducta.Take(parcial).Select((x, j) => $"{Romanos[j]}: {x ?? "sin nota"}")));
        var faltas = a.Notas.Where(n => n is not null).Sum(n => n!.Inasistencias);
        lineas.Add($"Inasistencias registradas por los docentes: {faltas}");
        var porGravedad = incidencias.GroupBy(g => g).Select(g => $"{g.Count()} {GravedadesIncidencia.Nombre(g.Key)}").ToList();
        if (porGravedad.Count > 0) lineas.Add($"Faltas disciplinarias en el año: {string.Join(", ", porGravedad)}");
        return string.Join("\n", lineas);
    }
}
