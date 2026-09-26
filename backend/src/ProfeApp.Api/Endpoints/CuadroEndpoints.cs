using ProfeApp.Api.Common;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Contracts;
using ProfeApp.Domain.Common;

namespace ProfeApp.Api.Endpoints;

public static class CuadroEndpoints
{
    public static void MapCuadroEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/v1/cuadros").WithTags("Cuadros SACE")
            .RequireAuthorization(Policies.DocenteOnly);

        // JSON con el archivo en base64 y no multipart: el cuadro pesa unos 30 KB y así la
        // app lo manda con el mismo cliente que todo lo demás.
        group.MapPost("/exportar", (ExportarCuadroRequest request, ICuadroSaceWriter writer) =>
                writer.Rellenar(request).ToHttp(c => Results.File(c.Contenido, c.ContentType, c.NombreArchivo)))
            .WithSummary("Rellena el cuadro de SACE con lo capturado y lo devuelve listo para subir. No guarda nada.");
    }
}
