using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;
using ProfeApp.Domain.Cobros;
using ProfeApp.Domain.Common;
using ProfeApp.Infrastructure.Persistence;

namespace ProfeApp.Infrastructure.Cobros;

/// <summary>
/// El plan de cada cuenta casi no cambia y se consulta en cada sincronización y cada
/// renovación de sesión: vive cinco minutos en memoria. Dos niveles, para que registrar el
/// pago de un centro libere a todos sus docentes de una vez: usuario → cuenta, cuenta → plan.
/// </summary>
public sealed class CobroService(AppDbContext db, ICurrentUser currentUser, IMemoryCache cache, IClock clock) : ICobroService
{
    private static readonly TimeSpan Vive = TimeSpan.FromMinutes(5);

    /// <summary>A quién le cobra un usuario. <c>CuentaId</c> null = no se le cobra (la plataforma).</summary>
    internal sealed record CuentaDeUsuario(Guid? CuentaId, bool EsCentro);

    /// <summary>Lo que hace falta del plan, sin el resto de la fila.</summary>
    internal sealed record Plan(
        bool Activa, string? Nivel, string? PlanNombre, decimal Monto, DateOnly? PagadoHasta, int DiasGracia, string? ComoPagar)
    {
        public SituacionCobro En(DateOnly hoy) => SituacionCobro.Para(PlanNombre, Monto, PagadoHasta, DiasGracia, ComoPagar, hoy);
    }

    public async Task<CobroDto> MioAsync(CancellationToken ct = default)
    {
        var (cuenta, plan) = await DeUsuarioAsync(currentUser.RequireUserId(), ct);
        return Describir(cuenta, plan);
    }

    public async Task<Error?> BloqueoDeSyncAsync(SyncPushRequest request, CancellationToken ct = default)
    {
        var (cuenta, plan) = await DeUsuarioAsync(currentUser.RequireUserId(), ct);
        if (plan is null) return null;

        var situacion = plan.En(clock.Today);
        if (situacion.SoloLectura) return Error.Conflict(Mensaje(situacion, cuenta.EsCentro), "solo_lectura");

        // Sólo frena secciones nuevas (cada clase es una asignatura en una sección): quien ya tiene más de las que cubre su plan (porque
        // se lo bajaron) sigue respaldando las que tiene.
        if (cuenta.EsCentro || NivelesDocente.Tope(plan.Nivel) is not { } tope) return null;
        var entrantes = (request.Clases ?? []).Where(c => !c.Eliminada).Select(c => c.Clave).Distinct().ToList();
        if (entrantes.Count == 0) return null;

        var activas = await db.Clases.Where(c => c.EliminadaEn == null).Select(c => c.Clave).ToListAsync(ct);
        var nuevas = entrantes.Except(activas).Count();
        var borradas = (request.Clases ?? []).Where(c => c.Eliminada).Select(c => c.Clave).Intersect(activas).Count();
        if (nuevas == 0 || activas.Count - borradas + nuevas <= tope) return null;

        return Error.Conflict(
            $"Tu plan cubre {tope} secciones (asignatura por sección) y ya las tienes todas. Para agregar otra hay que pasar a un plan mayor.",
            "tope_asignaturas");
    }

    public void Olvidar(Guid cuentaId) => cache.Remove(ClavePlan(cuentaId));

    /// <summary>Para el login: suspendida, la cuenta no entra.</summary>
    internal async Task<(CuentaDeUsuario Cuenta, Plan? Plan)> DeUsuarioAsync(Guid userId, CancellationToken ct)
    {
        var cuenta = await cache.GetOrCreateAsync($"cobro:usuario:{userId}", async e =>
        {
            e.AbsoluteExpirationRelativeToNow = Vive;
            var u = await db.Users.AsNoTracking().Where(x => x.Id == userId)
                .Select(x => new { x.TenantId, x.InstitucionId }).FirstOrDefaultAsync(ct);
            return u?.InstitucionId is { } centro ? new CuentaDeUsuario(centro, true)
                : new CuentaDeUsuario(u?.TenantId, false);
        }) ?? new CuentaDeUsuario(null, false);

        if (cuenta.CuentaId is not { } id) return (cuenta, null);
        var plan = await cache.GetOrCreateAsync(ClavePlan(id), async e =>
        {
            e.AbsoluteExpirationRelativeToNow = Vive;
            return cuenta.EsCentro
                ? await db.Instituciones.AsNoTracking().Where(i => i.Id == id)
                    .Select(i => new Plan(i.Activa, null, i.PlanNombre, i.Monto, i.PagadoHasta, i.DiasGracia, i.ComoPagar))
                    .FirstOrDefaultAsync(ct)
                : await db.Tenants.AsNoTracking().Where(t => t.Id == id)
                    .Select(t => new Plan(t.IsActive, t.Nivel, t.PlanNombre, t.Monto, t.PagadoHasta, t.DiasGracia, t.ComoPagar))
                    .FirstOrDefaultAsync(ct);
        });
        return (cuenta, plan);
    }

    internal CobroDto Describir(CuentaDeUsuario cuenta, Plan? plan) => plan is null
        ? Describir(SituacionCobro.SinCobro, cuenta.EsCentro, null)
        : Describir(plan.En(clock.Today), cuenta.EsCentro, cuenta.EsCentro ? null : plan.Nivel);

    internal static CobroDto Describir(SituacionCobro s, bool esCentro, string? nivel) => new(
        s.Estado switch
        {
            EstadoCobro.PorVencer => "porVencer",
            EstadoCobro.Gracia => "gracia",
            EstadoCobro.SoloLectura => "soloLectura",
            _ => "alDia",
        },
        s.PlanNombre, s.Monto, s.PagadoHasta, s.DiasGracia, s.BloqueaEn, s.DiasRestantes, s.SoloLectura,
        Mensaje(s, esCentro), s.ComoPagar, nivel, NivelesDocente.Tope(nivel));

    /// <summary>Informa sin llamar a comprar: el mismo texto sale en la app de las tiendas.</summary>
    private static string Mensaje(SituacionCobro s, bool esCentro)
    {
        var de = esCentro ? "La licencia de tu centro" : "Tu plan";
        if (s.PagadoHasta is not { } hasta) return $"{de} no tiene fecha de vencimiento.";
        var dia = hasta.ToString("dd-MM-yyyy");
        return s.Estado switch
        {
            EstadoCobro.AlDia => $"{de} está al día hasta el {dia}.",
            EstadoCobro.PorVencer when s.DiasRestantes == 0 => $"{de} vence hoy.",
            EstadoCobro.PorVencer => $"{de} vence el {dia}: faltan {s.DiasRestantes} día(s).",
            EstadoCobro.Gracia =>
                $"{de} venció el {dia}. Hasta el {s.BloqueaEn:dd-MM-yyyy} todo sigue igual; después ProfeApp queda de solo lectura.",
            _ => $"ProfeApp quedó de solo lectura: {de.ToLowerInvariant()} venció el {dia}. Puedes ver y exportar tus cuadros, "
                 + "pero lo que cambies no se respalda hasta que se renueve.",
        };
    }

    private static string ClavePlan(Guid cuentaId) => $"cobro:cuenta:{cuentaId}";
}
