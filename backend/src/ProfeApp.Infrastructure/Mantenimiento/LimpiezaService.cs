using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using ProfeApp.Application.Abstractions;
using ProfeApp.Infrastructure.Persistence;

namespace ProfeApp.Infrastructure.Mantenimiento;

/// <summary>
/// Limpieza diaria de lo que sólo crece: sesiones vencidas o rotadas, y lápidas (borrados
/// ya avisados) más viejas que <see cref="RetencionLapidas"/>. Un dispositivo que pase
/// más tiempo sin sincronizar puede conservar algo que otro borró; es el precio de no
/// guardar lápidas para siempre.
/// </summary>
public sealed class LimpiezaService(IServiceScopeFactory scopes, ILogger<LimpiezaService> logger) : BackgroundService
{
    public static readonly TimeSpan RetencionLapidas = TimeSpan.FromDays(120);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // Lejos del arranque: no compite con las migraciones ni con el primer tráfico.
        try { await Task.Delay(TimeSpan.FromMinutes(5), stoppingToken); }
        catch (OperationCanceledException) { return; }

        using var timer = new PeriodicTimer(TimeSpan.FromHours(24));
        do
        {
            try
            {
                await LimpiarAsync(stoppingToken);
            }
            catch (Exception error) when (error is not OperationCanceledException)
            {
                logger.LogError(error, "Falló la limpieza diaria; se reintenta mañana.");
            }
        } while (await timer.WaitForNextTickAsync(stoppingToken));
    }

    public async Task LimpiarAsync(CancellationToken ct)
    {
        using var scope = scopes.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var ahora = scope.ServiceProvider.GetRequiredService<IClock>().Now;
        var corte = ahora - RetencionLapidas;

        var sesiones = await db.RefreshTokens
            .Where(t => t.ExpiresAt < ahora || (t.RevokedAt != null && t.RevokedAt < ahora.AddDays(-7)))
            .ExecuteDeleteAsync(ct);
        var registros = await db.Registros.IgnoreQueryFilters()
            .Where(r => r.Eliminado && r.ModificadoEn < corte)
            .ExecuteDeleteAsync(ct);
        var celdas = await db.ClaseValores.IgnoreQueryFilters()
            .Where(v => v.Valor == null && v.ModificadoEn < corte)
            .ExecuteDeleteAsync(ct);
        // Columnas, alumnos y valores caen en cascada.
        // SQL directo: EF no admite ExecuteDelete en una tabla compartida (clase + archivo).
        var clases = await db.Database.ExecuteSqlAsync(
            $"DELETE FROM clases WHERE eliminada_en IS NOT NULL AND eliminada_en < {corte}", ct);

        logger.LogInformation(
            "Limpieza: {Sesiones} sesiones, {Registros} registros, {Celdas} celdas y {Clases} clases borradas.",
            sesiones, registros, celdas, clases);
    }
}
