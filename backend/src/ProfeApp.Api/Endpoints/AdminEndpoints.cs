using ProfeApp.Api.Common;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Contracts;
using ProfeApp.Domain.Common;

namespace ProfeApp.Api.Endpoints;

public static class AdminEndpoints
{
    public static void MapAdminEndpoints(this IEndpointRouteBuilder app)
    {
        var centro = app.MapGroup("/api/v1/centro").WithTags("Centro").RequireAuthorization(Policies.CentroOnly)
            .RequireRateLimiting(Limites.Usuario);

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

        // Organización académica: años lectivos, grados y asignaturas, aulas, secciones y carga.
        centro.MapGet("/estructura", async (Guid? anioId, IEstructuraCentroService s, CancellationToken ct) =>
                (await s.ObtenerAsync(anioId, ct)).ToHttp())
            .WithSummary("Años lectivos, grados con asignaturas, aulas, secciones del año (por defecto el actual) y docentes.");
        centro.MapPost("/anios", async (AnioLectivoRequest r, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.GuardarAnioAsync(null, r, ct)).ToHttp());
        centro.MapPut("/anios/{id:guid}", async (Guid id, AnioLectivoRequest r, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.GuardarAnioAsync(id, r, ct)).ToHttp());
        centro.MapPost("/grados", async (GradoRequest r, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.GuardarGradoAsync(null, r, ct)).ToHttp());
        centro.MapPost("/grados/plantilla", async (PlantillaGradosRequest r, IEstructuraCentroService s, CancellationToken ct) =>
                (await s.PlantillaGradosAsync(r, ct)).ToHttp(n => Results.Ok(new { creados = n })))
            .WithSummary("Crea los grados de Honduras que falten en los niveles pedidos.");
        centro.MapPut("/grados/{id:guid}", async (Guid id, GradoRequest r, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.GuardarGradoAsync(id, r, ct)).ToHttp());
        centro.MapDelete("/grados/{id:guid}", async (Guid id, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.EliminarGradoAsync(id, ct)).ToHttp());
        centro.MapPost("/asignaturas", async (AgregarAsignaturasRequest r, IEstructuraCentroService s, CancellationToken ct) =>
                (await s.AgregarAsignaturasAsync(r, ct)).ToHttp(n => Results.Ok(new { creadas = n })))
            .WithSummary("Agrega las mismas asignaturas a varios grados.");
        centro.MapPut("/asignaturas/{id:guid}", async (Guid id, NombreRequest r, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.RenombrarAsignaturaAsync(id, r, ct)).ToHttp());
        centro.MapDelete("/asignaturas/{id:guid}", async (Guid id, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.EliminarAsignaturaAsync(id, ct)).ToHttp());
        centro.MapPost("/aulas", async (AulaRequest r, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.GuardarAulaAsync(null, r, ct)).ToHttp());
        centro.MapPut("/aulas/{id:guid}", async (Guid id, AulaRequest r, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.GuardarAulaAsync(id, r, ct)).ToHttp());
        centro.MapDelete("/aulas/{id:guid}", async (Guid id, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.EliminarAulaAsync(id, ct)).ToHttp());
        centro.MapPost("/secciones", async (SeccionRequest r, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.GuardarSeccionAsync(null, r, ct)).ToHttp());
        centro.MapPut("/secciones/{id:guid}", async (Guid id, SeccionRequest r, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.GuardarSeccionAsync(id, r, ct)).ToHttp());
        centro.MapDelete("/secciones/{id:guid}", async (Guid id, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.EliminarSeccionAsync(id, ct)).ToHttp());
        centro.MapPut("/secciones/{id:guid}/carga", async (Guid id, CargaRequest r, IEstructuraCentroService s, CancellationToken ct) =>
                (await s.GuardarCargaAsync(id, r, ct)).ToHttp())
            .WithSummary("Reemplaza qué docente da cada asignatura en la sección.");

        // Personal: dirección, subdirección, secretaría y orientación.
        centro.MapGet("/personal", async (IEstructuraCentroService s, CancellationToken ct) => (await s.PersonalAsync(ct)).ToHttp());
        centro.MapPost("/personal", async (CrearPersonalRequest r, IEstructuraCentroService s, CancellationToken ct) =>
                (await s.CrearPersonalAsync(r, ct)).ToHttp())
            .WithSummary("Cuenta de personal con contraseña temporal; no cuenta en el cupo de docentes.");
        centro.MapPut("/personal/{id:guid}/cargo", async (Guid id, CargoRequest r, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.CambiarCargoAsync(id, r, ct)).ToHttp());
        centro.MapPost("/personal/{id:guid}/activar", async (Guid id, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.CambiarEstadoPersonalAsync(id, true, ct)).ToHttp());
        centro.MapPost("/personal/{id:guid}/desactivar", async (Guid id, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.CambiarEstadoPersonalAsync(id, false, ct)).ToHttp());
        centro.MapPost("/personal/{id:guid}/restablecer-clave", async (Guid id, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.RestablecerClavePersonalAsync(id, ct)).ToHttp());

        var plataforma = app.MapGroup("/api/v1/plataforma").WithTags("Plataforma").RequireAuthorization(Policies.PlatformOnly)
            .RequireRateLimiting(Limites.Usuario);

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
        plataforma.MapGet("/docentes", async (string? buscar, int? pagina, IPlataformaService s, CancellationToken ct) =>
                (await s.DocentesAsync(buscar, pagina ?? 0, ct)).ToHttp())
            .WithSummary("Docentes del plan personal, por páginas, con su cobro.");

        // Cobro: lo mismo para un docente (por su usuario) que para un centro.
        foreach (var (ruta, tipo) in new[] { ("docentes", TipoCuenta.Docente), ("instituciones", TipoCuenta.Centro) })
        {
            plataforma.MapPut($"/{ruta}/{{id:guid}}/plan", async (Guid id, PlanCobroRequest r, IPlataformaService s, CancellationToken ct) =>
                (await s.FijarPlanAsync(tipo, id, r, ct)).ToHttp());
            plataforma.MapPost($"/{ruta}/{{id:guid}}/pagos", async (Guid id, RegistrarPagoRequest r, IPlataformaService s, CancellationToken ct) =>
                    (await s.RegistrarPagoAsync(tipo, id, r, ct)).ToHttp())
                .WithSummary("Anota un pago y corre el vencimiento.");
            plataforma.MapGet($"/{ruta}/{{id:guid}}/pagos", async (Guid id, IPlataformaService s, CancellationToken ct) =>
                (await s.PagosAsync(tipo, id, ct)).ToHttp());
            plataforma.MapPost($"/{ruta}/{{id:guid}}/suspender", async (Guid id, IPlataformaService s, CancellationToken ct) =>
                (await s.CambiarEstadoAsync(tipo, id, false, ct)).ToHttp());
            plataforma.MapPost($"/{ruta}/{{id:guid}}/reactivar", async (Guid id, IPlataformaService s, CancellationToken ct) =>
                (await s.CambiarEstadoAsync(tipo, id, true, ct)).ToHttp());
            plataforma.MapPost($"/{ruta}/{{id:guid}}/reponer-clave", async (Guid id, IPlataformaService s, CancellationToken ct) =>
                (await s.ReponerClaveAsync(tipo, id, ct)).ToHttp());
        }
    }
}
