using ProfeApp.Api.Common;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Contracts;

namespace ProfeApp.Api.Endpoints;

public static class AuthEndpoints
{
    public static void MapAuthEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/v1/auth").WithTags("Auth");

        group.MapPost("/register", async (RegisterRequest request, IAuthService auth, HttpContext http, CancellationToken ct) =>
                (await auth.RegisterAsync(request, http.Connection.RemoteIpAddress?.ToString(), ct)).ToHttp())
            .AllowAnonymous()
            .WithSummary("Crea la cuenta del docente y devuelve la sesión iniciada.");

        group.MapPost("/login", async (LoginRequest request, IAuthService auth, HttpContext http, CancellationToken ct) =>
                (await auth.LoginAsync(request, http.Connection.RemoteIpAddress?.ToString(), ct)).ToHttp())
            .AllowAnonymous()
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

        group.MapPost("/change-password", async (ChangePasswordRequest request, IAuthService auth, CancellationToken ct) =>
                (await auth.ChangePasswordAsync(request, ct)).ToHttp())
            .RequireAuthorization();
    }
}
