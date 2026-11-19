using Microsoft.EntityFrameworkCore;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Contracts;
using ProfeApp.Infrastructure.Persistence;

namespace ProfeApp.Infrastructure.Ia;

/// <summary>
/// Costo estimado de la IA a partir de los tokens de <c>usos_ia</c>. Lo de un docente de un
/// centro se le suma al centro. Si cambia el precio del modelo o el tipo de cambio, se cambian aquí.
/// </summary>
public sealed class CostosIaService(AppDbContext db, IClock clock) : ICostosIaService
{
    /// <summary>Claude Opus 5.5, dólares por millón de tokens.</summary>
    public const decimal PrecioEntrada = 4m;
    public const decimal PrecioSalida = 20m;

    /// <summary>Lempiras por dólar (aproximado).</summary>
    public const decimal TasaLempira = 26m;

    public async Task<CostosIaDto> CostosAsync(int? anio, int? mes, CancellationToken ct = default)
    {
        var hoy = clock.Today;
        var primero = new DateOnly(anio ?? hoy.Year, mes is >= 1 and <= 12 ? mes.Value : hoy.Month, 1);
        var desde = ClienteIa.InicioDelMes(primero);
        var hasta = ClienteIa.InicioDelMes(primero.AddMonths(1));

        var filas = await db.UsosIa.AsNoTracking()
            .Where(u => u.CreatedAt >= desde && u.CreatedAt < hasta)
            .GroupBy(u => new { u.InstitucionId, u.UsuarioId, u.Funcion })
            .Select(g => new
            {
                g.Key.InstitucionId, g.Key.UsuarioId, g.Key.Funcion, Usos = g.Count(),
                Entrada = g.Sum(u => (long)u.TokensEntrada), Salida = g.Sum(u => (long)u.TokensSalida),
            })
            .ToListAsync(ct);

        var centros = filas.Where(f => f.InstitucionId is not null).Select(f => f.InstitucionId!.Value).Distinct().ToList();
        var docentes = filas.Where(f => f.InstitucionId is null).Select(f => f.UsuarioId).Distinct().ToList();
        var nombresCentro = await db.Instituciones.AsNoTracking().Where(i => centros.Contains(i.Id))
            .ToDictionaryAsync(i => i.Id, i => i.Nombre, ct);
        var nombresDocente = await db.Users.AsNoTracking().Where(u => docentes.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => u.FullName, ct);

        var porFuncion = filas.GroupBy(f => f.Funcion)
            .Select(g =>
            {
                var total = Lempiras(g.Sum(f => f.Entrada), g.Sum(f => f.Salida));
                var usos = g.Sum(f => f.Usos);
                return new CostoFuncionIaDto(g.Key, usos, g.Sum(f => f.Entrada), g.Sum(f => f.Salida), total, Math.Round(total / usos, 2));
            })
            .OrderByDescending(f => f.Total).ToList();

        var porCuenta = filas
            .GroupBy(f => f.InstitucionId is { } i ? ("centro", i) : ("docente", f.UsuarioId))
            .Select(g => new CostoCuentaIaDto(g.Key.Item1,
                g.Key.Item1 == "centro" ? nombresCentro.GetValueOrDefault(g.Key.Item2, "Centro") : nombresDocente.GetValueOrDefault(g.Key.Item2, "Docente"),
                g.Sum(f => f.Usos), Lempiras(g.Sum(f => f.Entrada), g.Sum(f => f.Salida))))
            .OrderByDescending(c => c.Total).ToList();

        return new CostosIaDto(primero.Year, primero.Month, TasaLempira, PrecioEntrada, PrecioSalida,
            filas.Sum(f => f.Usos), porFuncion.Sum(f => f.Total), porFuncion, porCuenta);
    }

    private static decimal Lempiras(long entrada, long salida) =>
        Math.Round((entrada * PrecioEntrada + salida * PrecioSalida) / 1_000_000m * TasaLempira, 2);
}
