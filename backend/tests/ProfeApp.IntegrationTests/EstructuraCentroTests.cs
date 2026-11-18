using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.DependencyInjection;
using ProfeApp.Domain.Common;
using ProfeApp.Infrastructure.Identity;
using ProfeApp.IntegrationTests.Infrastructure;

namespace ProfeApp.IntegrationTests;

public class EstructuraCentroTests(ApiFixture fixture) : ApiTestBase(fixture)
{
    private async Task<HttpClient> CentroAsync()
    {
        var email = $"plataforma-{Guid.NewGuid():N}@prueba.hn";
        using (var scope = Fixture.Services.CreateScope())
        {
            var users = scope.ServiceProvider.GetRequiredService<UserManager<AppUser>>();
            var admin = new AppUser { Id = Guid.NewGuid(), UserName = email, Email = email, FullName = "Plataforma", CreatedAt = DateTimeOffset.UtcNow };
            (await users.CreateAsync(admin, "Prueba1234!")).Succeeded.Should().BeTrue();
            await users.AddToRoleAsync(admin, Roles.PlatformAdmin);
        }
        var plataforma = await LoginAsync(email, "Prueba1234!");
        var creado = await ReadAsync(await plataforma.PostAsJsonAsync("/api/v1/plataforma/instituciones", new
        {
            nombre = "Instituto de Prueba",
            plan = "pequeno",
            maxDocentes = 5,
            adminEmail = $"director-{Guid.NewGuid():N}@prueba.hn",
            adminNombre = "Directora",
        }));
        var admin2 = creado.GetProperty("admin");
        return await EntrarConTemporalAsync(admin2.GetProperty("email").GetString()!, admin2.GetProperty("claveTemporal").GetString()!);
    }

    private static async Task<Guid> IdAsync(HttpResponseMessage r) => (await ReadAsync(r)).GetProperty("id").GetGuid();

    private static async Task<JsonElement> EstructuraAsync(HttpClient c) => await ReadAsync(await c.GetAsync("/api/v1/centro/estructura"));

    [Fact]
    public async Task El_centro_arma_su_ano_grados_asignaturas_aulas_secciones_y_carga()
    {
        var centro = await CentroAsync();
        var docente = (await ReadAsync(await centro.PostAsJsonAsync("/api/v1/centro/docentes",
            new { email = $"profe-{Guid.NewGuid():N}@prueba.hn", nombre = "Profe Uno" }))).GetProperty("usuarioId").GetGuid();

        var anio = await IdAsync(await centro.PostAsJsonAsync("/api/v1/centro/anios", new
        {
            anio = 2027, inicio = "2027-02-01", fin = "2027-11-30",
            cierres = new[] { "2027-04-15", "2027-06-30", null, null }, actual = false,
        }));

        var plantilla = await ReadAsync(await centro.PostAsJsonAsync("/api/v1/centro/grados/plantilla", new { niveles = new[] { "basica" } }));
        plantilla.GetProperty("creados").GetInt32().Should().Be(9);
        // Repetirla no duplica.
        (await ReadAsync(await centro.PostAsJsonAsync("/api/v1/centro/grados/plantilla", new { niveles = new[] { "basica" } })))
            .GetProperty("creados").GetInt32().Should().Be(0);

        var estructura = await EstructuraAsync(centro);
        var grados = estructura.GetProperty("grados").EnumerateArray().ToList();
        grados.Select(g => g.GetProperty("nombre").GetString()).Should().StartWith(["1.º grado", "2.º grado"]);
        var septimo = grados.Single(g => g.GetProperty("nombre").GetString() == "7.º grado").GetProperty("id").GetGuid();
        var octavo = grados.Single(g => g.GetProperty("nombre").GetString() == "8.º grado").GetProperty("id").GetGuid();

        (await ReadAsync(await centro.PostAsJsonAsync("/api/v1/centro/asignaturas", new
        {
            gradoIds = new[] { septimo, octavo },
            nombres = new[] { "Español", "Matemáticas", "español" },
        }))).GetProperty("creadas").GetInt32().Should().Be(4, "dos por grado, sin repetir mayúsculas");

        var aula = await IdAsync(await centro.PostAsJsonAsync("/api/v1/centro/aulas", new { nombre = "Aula 1", capacidad = 35 }));
        var seccion = await IdAsync(await centro.PostAsJsonAsync("/api/v1/centro/secciones", new
        {
            anioLectivoId = anio, gradoId = septimo, nombre = "a", jornada = "matutina", cupo = 35, aulaId = aula, maestroGuiaId = docente,
        }));
        (await centro.PostAsJsonAsync("/api/v1/centro/secciones", new
        {
            anioLectivoId = anio, gradoId = septimo, nombre = "A", jornada = "matutina", cupo = 30, aulaId = (Guid?)null, maestroGuiaId = (Guid?)null,
        })).StatusCode.Should().Be(HttpStatusCode.Conflict);

        estructura = await EstructuraAsync(centro);
        var asignaturas7 = estructura.GetProperty("grados").EnumerateArray()
            .Single(g => g.GetProperty("id").GetGuid() == septimo).GetProperty("asignaturas").EnumerateArray()
            .Select(a => a.GetProperty("id").GetGuid()).ToList();
        var asignatura8 = estructura.GetProperty("grados").EnumerateArray()
            .Single(g => g.GetProperty("id").GetGuid() == octavo).GetProperty("asignaturas")[0].GetProperty("id").GetGuid();

        (await centro.PutAsJsonAsync($"/api/v1/centro/secciones/{seccion}/carga", new
        {
            asignaciones = new[] { new { asignaturaId = asignatura8, docenteId = docente } },
        })).StatusCode.Should().Be(HttpStatusCode.BadRequest, "la asignatura es de otro grado");

        var conCarga = await ReadAsync(await centro.PutAsJsonAsync($"/api/v1/centro/secciones/{seccion}/carga", new
        {
            asignaciones = asignaturas7.Select(a => new { asignaturaId = a, docenteId = docente }),
        }));
        conCarga.GetProperty("carga").GetArrayLength().Should().Be(2);
        conCarga.GetProperty("nombre").GetString().Should().Be("A");

        estructura = await EstructuraAsync(centro);
        estructura.GetProperty("anioId").GetGuid().Should().Be(anio, "el primer año queda como actual");
        estructura.GetProperty("puedeEditar").GetBoolean().Should().BeTrue();
        var sec = estructura.GetProperty("secciones")[0];
        sec.GetProperty("maestroGuiaId").GetGuid().Should().Be(docente);
        sec.GetProperty("carga").GetArrayLength().Should().Be(2);

        (await centro.DeleteAsync($"/api/v1/centro/grados/{septimo}")).StatusCode.Should().Be(HttpStatusCode.Conflict);
        (await centro.DeleteAsync($"/api/v1/centro/aulas/{aula}")).StatusCode.Should().Be(HttpStatusCode.NoContent);
        (await EstructuraAsync(centro)).GetProperty("secciones")[0].GetProperty("aulaId").ValueKind.Should().Be(JsonValueKind.Null);

        // Un año nuevo marcado como actual desplaza al anterior.
        var otro = await IdAsync(await centro.PostAsJsonAsync("/api/v1/centro/anios", new
        {
            anio = 2028, inicio = "2028-02-01", fin = "2028-11-30", cierres = (string?[]?)null, actual = true,
        }));
        estructura = await EstructuraAsync(centro);
        estructura.GetProperty("anioId").GetGuid().Should().Be(otro);
        estructura.GetProperty("secciones").GetArrayLength().Should().Be(0, "las secciones son de cada año");
        estructura.GetProperty("anios").EnumerateArray().Count(a => a.GetProperty("actual").GetBoolean()).Should().Be(1);
    }

    [Fact]
    public async Task Un_centro_no_toca_la_estructura_de_otro()
    {
        var uno = await CentroAsync();
        var otro = await CentroAsync();
        var aula = await IdAsync(await uno.PostAsJsonAsync("/api/v1/centro/aulas", new { nombre = "Lab", capacidad = (int?)null }));

        (await otro.DeleteAsync($"/api/v1/centro/aulas/{aula}")).StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await otro.PutAsJsonAsync($"/api/v1/centro/aulas/{aula}", new { nombre = "Mía", capacidad = 10 }))
            .StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await EstructuraAsync(otro)).GetProperty("aulas").GetArrayLength().Should().Be(0);
    }

    [Fact]
    public async Task Orientacion_consulta_sin_editar_y_siempre_queda_quien_administre()
    {
        var centro = await CentroAsync();
        var cuenta = await ReadAsync(await centro.PostAsJsonAsync("/api/v1/centro/personal", new
        {
            email = $"orienta-{Guid.NewGuid():N}@prueba.hn", nombre = "Orientadora", cargo = "orientador",
        }));
        var orientadora = await EntrarConTemporalAsync(cuenta.GetProperty("email").GetString()!, cuenta.GetProperty("claveTemporal").GetString()!);

        (await EstructuraAsync(orientadora)).GetProperty("puedeEditar").GetBoolean().Should().BeFalse();
        (await ReadAsync(await orientadora.GetAsync("/api/v1/centro"))).GetProperty("puedeEditar").GetBoolean().Should().BeFalse();
        (await orientadora.PostAsJsonAsync("/api/v1/centro/aulas", new { nombre = "X", capacidad = 10 }))
            .StatusCode.Should().Be(HttpStatusCode.Forbidden);
        (await orientadora.PostAsJsonAsync("/api/v1/centro/docentes", new { email = $"p-{Guid.NewGuid():N}@prueba.hn", nombre = "P" }))
            .StatusCode.Should().Be(HttpStatusCode.Forbidden);

        var personal = (await ReadAsync(await centro.GetAsync("/api/v1/centro/personal"))).EnumerateArray().ToList();
        personal.Should().HaveCount(2);
        var yo = personal.Single(p => p.GetProperty("esYo").GetBoolean()).GetProperty("id").GetGuid();

        (await centro.PutAsJsonAsync($"/api/v1/centro/personal/{yo}/cargo", new { cargo = "orientador" }))
            .StatusCode.Should().Be(HttpStatusCode.Conflict, "nadie más administra");
        (await centro.PostAsync($"/api/v1/centro/personal/{yo}/desactivar", null))
            .StatusCode.Should().Be(HttpStatusCode.Conflict);

        // El personal no ocupa cupo de docentes.
        (await ReadAsync(await centro.GetAsync("/api/v1/centro"))).GetProperty("institucion").GetProperty("docentes").GetInt32().Should().Be(0);
    }
}
