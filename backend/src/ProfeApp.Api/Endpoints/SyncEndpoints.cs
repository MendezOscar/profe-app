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
            .RequireAuthorization(Policies.DocenteOnly)
            .RequireRateLimiting(Limites.Usuario);

        group.MapPost("/push", async (SyncPushRequest request, SyncService sync, CancellationToken ct) =>
                (await sync.PushAsync(request, ct)).ToHttp())
            .WithSummary("Sube clases cambiadas en el teléfono. Idempotente: gana la captura más nueva por celda.");

        group.MapGet("/pull", async (DateTimeOffset? desde, DateTimeOffset? hasta, int? pagina, SyncService sync, CancellationToken ct) =>
                (await sync.PullAsync(desde, hasta, pagina ?? 0, ct)).ToHttp())
            .WithSummary("Lo cambiado desde el cursor, por páginas. Sin archivos: esos van por /archivo.");

        group.MapGet("/archivo", async (string clave, SyncService sync, CancellationToken ct) =>
                (await sync.ArchivoAsync(clave, ct)).ToHttp())
            .WithSummary("El cuadro original de una clase, para un dispositivo que no lo tiene.");
    }
}
