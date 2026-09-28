using ProfeApp.Api.Common;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Contracts;

namespace ProfeApp.Api.Endpoints;

public static class AuthEndpoints
{
    public static void MapAuthEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/v1/auth").WithTags("Auth");

        // Sin registro público: las cuentas no se crean desde la app. El alta de docentes
        // está por definir; por ahora sólo existe el docente demo (App:SeedDemoData).

        group.MapPost("/login", async (LoginRequest request, IAuthService auth, HttpContext http, CancellationToken ct) =>
                (await auth.LoginAsync(request, http.Connection.RemoteIpAddress?.ToString(), ct)).ToHttp())
            .AllowAnonymous()
            .RequireRateLimiting(Limites.Login)
            .WithSummary("Inicia sesión y devuelve el par access/refresh token.");

        group.MapPost("/refresh", async (RefreshRequest request, IAuthService auth, HttpContext http, CancellationToken ct) =>
                (await auth.RefreshAsync(request, http.Connection.RemoteIpAddress?.ToString(), ct)).ToHttp())
            .AllowAnonymous();

        group.MapPost("/logout", async (RefreshRequest request, IAuthService auth, CancellationToken ct) =>
                (await auth.LogoutAsync(request.RefreshToken, ct)).ToHttp())
            .AllowAnonymous();

        group.MapGet("/me", async (IAuthService auth, CancellationToken ct) =>
            (await auth.GetCurrentAsync(ct)).ToHttp())
            .RequireAuthorization();

        group.MapPost("/delete-account", async (DeleteAccountRequest request, IAuthService auth, CancellationToken ct) =>
                (await auth.DeleteAccountAsync(request, ct)).ToHttp())
            .RequireAuthorization()
            .WithSummary("Elimina la cuenta del docente y todos sus datos en el servidor.");

        group.MapPost("/change-password", async (ChangePasswordRequest request, IAuthService auth, CancellationToken ct) =>
                (await auth.ChangePasswordAsync(request, ct)).ToHttp())
            .RequireAuthorization();
    }
}
