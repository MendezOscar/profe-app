using ProfeApp.Api.Common;
using ProfeApp.Application.Contracts;
using ProfeApp.Application.Services;
using ProfeApp.Domain.Common;

namespace ProfeApp.Api.Endpoints;

public static class SyncEndpoints
{
    public static void MapSyncEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/v1/sync").WithTags("Sync")
            .RequireAuthorization(Policies.DocenteOnly);

        group.MapPost("/push", async (SyncPushRequest request, SyncService sync, CancellationToken ct) =>
                (await sync.PushAsync(request, ct)).ToHttp())
            .WithSummary("Sube clases cambiadas en el teléfono. Idempotente: gana la captura más nueva por celda.");

        group.MapGet("/pull", async (DateTimeOffset? desde, SyncService sync, CancellationToken ct) =>
                (await sync.PullAsync(desde, ct)).ToHttp())
            .WithSummary("Clases cambiadas desde el cursor. El archivo sólo viaja si la plantilla cambió.");
    }
}
