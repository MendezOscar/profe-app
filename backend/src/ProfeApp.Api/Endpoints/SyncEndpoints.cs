using ProfeApp.Api.Common;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;
using ProfeApp.Application.Services;
using ProfeApp.Domain.Common;

namespace ProfeApp.Api.Endpoints;

public static class SyncEndpoints
{
    public static void MapSyncEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/v1/sync").WithTags("Sync")
            .RequireAuthorization(Policies.DocenteOnly)
            .RequireRateLimiting(Limites.Usuario);

        // Con el plan vencido (pasada la gracia) o una asignatura nueva por encima del tope,
        // no se respalda nada: lo del teléfono queda pendiente y sube al ponerse al día.
        group.MapPost("/push", async (SyncPushRequest request, SyncService sync, ICobroService cobro, CancellationToken ct) =>
                await cobro.BloqueoDeSyncAsync(request, ct) is { } bloqueo
                    ? Result.Fail(bloqueo).ToHttp()
                    : (await sync.PushAsync(request, ct)).ToHttp())
            .WithSummary("Sube clases cambiadas en el teléfono. Idempotente: gana la captura más nueva por celda.");

        group.MapGet("/pull", async (DateTimeOffset? desde, DateTimeOffset? hasta, int? pagina, string? despues, SyncService sync, CancellationToken ct) =>
                (await sync.PullAsync(desde, hasta, pagina ?? 0, despues, ct)).ToHttp())
            .WithSummary("Lo cambiado desde el cursor, por páginas. Sin archivos: esos van por /archivo.");

        group.MapGet("/archivo", async (string clave, SyncService sync, CancellationToken ct) =>
                (await sync.ArchivoAsync(clave, ct)).ToHttp())
            .WithSummary("El cuadro original de una clase, para un dispositivo que no lo tiene.");
    }
}
