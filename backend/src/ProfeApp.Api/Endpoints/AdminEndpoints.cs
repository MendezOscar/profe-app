using ProfeApp.Api.Common;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Contracts;
using ProfeApp.Domain.Common;

namespace ProfeApp.Api.Endpoints;

public static class AdminEndpoints
{
    public static void MapAdminEndpoints(this IEndpointRouteBuilder app)
    {
        var centro = app.MapGroup("/api/v1/centro").WithTags("Centro").RequireAuthorization(Policies.CentroOnly);

        centro.MapGet("/", async (ICentroService s, CancellationToken ct) => (await s.ObtenerAsync(ct)).ToHttp())
            .WithSummary("El centro, su licencia y el avance de cada docente.");
        centro.MapPost("/docentes", async (CrearDocenteRequest r, ICentroService s, CancellationToken ct) =>
                (await s.CrearDocenteAsync(r, ct)).ToHttp())
            .WithSummary("Da de alta un docente con contraseña temporal.");
        centro.MapPost("/docentes/{id:guid}/activar", async (Guid id, ICentroService s, CancellationToken ct) =>
            (await s.CambiarEstadoDocenteAsync(id, true, ct)).ToHttp());
        centro.MapPost("/docentes/{id:guid}/desactivar", async (Guid id, ICentroService s, CancellationToken ct) =>
            (await s.CambiarEstadoDocenteAsync(id, false, ct)).ToHttp());
        centro.MapPost("/docentes/{id:guid}/restablecer-clave", async (Guid id, ICentroService s, CancellationToken ct) =>
            (await s.RestablecerClaveAsync(id, ct)).ToHttp());

        var plataforma = app.MapGroup("/api/v1/plataforma").WithTags("Plataforma").RequireAuthorization(Policies.PlatformOnly);

        plataforma.MapGet("/instituciones", async (IPlataformaService s, CancellationToken ct) =>
            (await s.InstitucionesAsync(ct)).ToHttp());
        plataforma.MapPost("/instituciones", async (CrearInstitucionRequest r, IPlataformaService s, CancellationToken ct) =>
                (await s.CrearInstitucionAsync(r, ct)).ToHttp())
            .WithSummary("Crea un centro con licencia y su administrador.");
        plataforma.MapPut("/instituciones/{id:guid}", async (Guid id, ActualizarInstitucionRequest r, IPlataformaService s, CancellationToken ct) =>
            (await s.ActualizarInstitucionAsync(id, r, ct)).ToHttp());
        plataforma.MapPost("/docentes", async (CrearDocenteRequest r, IPlataformaService s, CancellationToken ct) =>
                (await s.CrearDocentePersonalAsync(r, ct)).ToHttp())
            .WithSummary("Cuenta de docente del plan personal, con contraseña temporal.");
    }
}
