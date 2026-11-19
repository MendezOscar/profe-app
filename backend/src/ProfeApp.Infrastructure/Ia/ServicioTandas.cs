using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Contracts;
using ProfeApp.Domain.Common;
using ProfeApp.Infrastructure.Persistence;

namespace ProfeApp.Infrastructure.Ia;

/// <summary>
/// Cada 30 segundos revisa los lotes de las tandas en proceso; al terminar guarda la sugerencia de
/// cada alumno y anota el uso de los trabajos que Anthropic cobró. Una tanda de más de un día se
/// da por fallida (el lote vence a las 24 horas) y libera su parte del tope.
/// </summary>
public sealed class ServicioTandas(IServiceScopeFactory scopes, ILogger<ServicioTandas> log) : BackgroundService
{
    public static readonly TimeSpan Intervalo = TimeSpan.FromSeconds(30);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(Intervalo);
        do
        {
            try
            {
                await RevisarAsync(stoppingToken);
            }
            catch (Exception e) when (e is not OperationCanceledException)
            {
                log.LogError(e, "Falló la revisión de las tandas de calificación");
            }
        } while (await timer.WaitForNextTickAsync(stoppingToken));
    }

    public async Task RevisarAsync(CancellationToken ct)
    {
        await using var scope = scopes.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var generador = scope.ServiceProvider.GetRequiredService<IGeneradorIa>();
        var clock = scope.ServiceProvider.GetRequiredService<IClock>();
        if (!generador.Disponible) return;

        var tandas = await db.TandasIa.Where(t => t.Estado == EstadosTanda.Procesando)
            .OrderBy(t => t.CreatedAt).Take(20).ToListAsync(ct);
        foreach (var tanda in tandas)
        {
            IReadOnlyList<(string Id, RespuestaIa? Respuesta)>? resultados;
            try
            {
                resultados = await generador.ResultadosLoteAsync(tanda.Lote, ct);
            }
            catch (Exception e) when (e is not OperationCanceledException)
            {
                log.LogWarning(e, "No se pudo revisar el lote {Lote}", tanda.Lote);
                resultados = null;
            }
            if (resultados is null)
            {
                if (clock.Now - tanda.CreatedAt > TimeSpan.FromHours(25)) tanda.Estado = EstadosTanda.Fallida;
                continue;
            }

            var paginas = JsonSerializer.Deserialize<Dictionary<string, int>>(tanda.Paginas) ?? [];
            var sugerencias = new List<ResultadoTandaIaDto>();
            foreach (var (alumno, r) in resultados)
            {
                if (r is not null)
                    db.UsosIa.Add(ClienteIa.Uso(FuncionesIa.CalificarTanda, r, tanda.UsuarioId, tanda.InstitucionId,
                        CreditosIa.Trabajo(FuncionesIa.CalificarTanda, paginas.GetValueOrDefault(alumno, 1))));
                sugerencias.Add(Sugerencia(alumno, r, tanda.Puntos));
            }
            tanda.Resultados = JsonSerializer.Serialize(sugerencias, ClienteIa.Json);
            tanda.Estado = EstadosTanda.Lista;
        }
        await db.SaveChangesAsync(ct);
    }

    private static ResultadoTandaIaDto Sugerencia(string alumno, RespuestaIa? r, decimal puntos)
    {
        if (r is null || r.Rechazada) return new(alumno, null, "La IA no pudo calificar este trabajo. Califícalo a mano o mándalo otra vez.");
        try
        {
            var leida = JsonSerializer.Deserialize<AsistenteIaService.CalificacionLeida>(r.Texto, ClienteIa.Json)!;
            return leida.Legible
                ? new(alumno, AsistenteIaService.Redondear(leida.Nota, puntos), leida.Justificacion.Trim())
                : new(alumno, null, "No se pudo leer el trabajo en las fotos. Toma otra con buena luz y de frente.");
        }
        catch (JsonException)
        {
            return new(alumno, null, "La IA respondió algo que no se pudo leer. Califícalo a mano o mándalo otra vez.");
        }
    }
}
