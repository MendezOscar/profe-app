using Microsoft.EntityFrameworkCore;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Common;
using ProfeApp.Domain.Common;
using ProfeApp.Infrastructure.Persistence;

namespace ProfeApp.Infrastructure.Push;

public sealed class DispositivosService(AppDbContext db, ICurrentUser currentUser, IClock clock) : IDispositivosService
{
    public async Task<Result> RegistrarAsync(DispositivoRequest r, CancellationToken ct = default)
    {
        var token = (r.Token ?? "").Trim();
        if (token.Length is < 20 or > 512) return Result.Fail(Error.Validation("Token no válido."));
        if (r.Plataforma is not ("android" or "ios")) return Result.Fail(Error.Validation("Plataforma desconocida."));
        // Un token es de un teléfono: si otro usuario entra en él, el aviso pasa a ser suyo.
        var dispositivo = await db.DispositivosPush.FirstOrDefaultAsync(d => d.Token == token, ct)
                          ?? db.DispositivosPush.Add(new DispositivoPush { Token = token }).Entity;
        dispositivo.UsuarioId = currentUser.RequireUserId();
        dispositivo.Plataforma = r.Plataforma;
        dispositivo.ActualizadoEn = clock.Now;
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }
}
