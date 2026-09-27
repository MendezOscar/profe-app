using System.Net;
using System.Net.Http.Json;
using ProfeApp.IntegrationTests.Infrastructure;

namespace ProfeApp.IntegrationTests;

public class AuthTests(ApiFixture fixture) : ApiTestBase(fixture)
{
    [Fact]
    public async Task El_docente_demo_entra_y_ve_su_perfil()
    {
        var client = await LoginAsync();

        var me = await ReadAsync(await client.GetAsync("/api/v1/auth/me"));

        me.GetProperty("email").GetString().Should().Be("docente@demo.hn");
        me.GetProperty("role").GetString().Should().Be("Docente");
    }

    [Fact]
    public async Task Cada_docente_registrado_tiene_su_propio_espacio()
    {
        var first = await ReadAsync(await (await RegisterAsync()).GetAsync("/api/v1/auth/me"));
        var second = await ReadAsync(await (await RegisterAsync()).GetAsync("/api/v1/auth/me"));

        first.GetProperty("tenantId").GetGuid().Should().NotBeEmpty();
        first.GetProperty("tenantId").GetGuid().Should().NotBe(second.GetProperty("tenantId").GetGuid());
    }

    [Fact]
    public async Task No_hay_registro_publico()
    {
        var response = await Fixture.CreateClient().PostAsJsonAsync("/api/v1/auth/register",
            new { email = "nuevo@prueba.hn", password = "Prueba1234!", fullName = "Nuevo" });

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task El_refresh_token_rota_y_el_usado_ya_no_sirve()
    {
        var login = await ReadAsync(await Fixture.CreateClient().PostAsJsonAsync("/api/v1/auth/login",
            new { email = "docente@demo.hn", password = "Demo1234!" }));
        var refreshToken = login.GetProperty("tokens").GetProperty("refreshToken").GetString();

        var first = await Fixture.CreateClient().PostAsJsonAsync("/api/v1/auth/refresh", new { refreshToken });
        var reused = await Fixture.CreateClient().PostAsJsonAsync("/api/v1/auth/refresh", new { refreshToken });

        first.StatusCode.Should().Be(HttpStatusCode.OK);
        reused.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task Eliminar_la_cuenta_borra_sus_datos_y_ya_no_se_puede_entrar()
    {
        var email = $"borrar-{Guid.NewGuid():N}@prueba.hn";
        var client = await RegisterAsync(email);
        (await client.PostAsJsonAsync("/api/v1/sync/push", new
        {
            registros = new[] { new { tipo = "plantilla", claseClave = "", clave = "p1", datos = "{}", eliminado = false, actualizadoEn = DateTimeOffset.UtcNow } },
        })).StatusCode.Should().Be(HttpStatusCode.NoContent);

        var malaClave = await client.PostAsJsonAsync("/api/v1/auth/delete-account", new { password = "otra" });
        var borrada = await client.PostAsJsonAsync("/api/v1/auth/delete-account", new { password = "Prueba1234!" });
        var login = await Fixture.CreateClient().PostAsJsonAsync("/api/v1/auth/login", new { email, password = "Prueba1234!" });

        malaClave.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        borrada.StatusCode.Should().Be(HttpStatusCode.NoContent);
        login.IsSuccessStatusCode.Should().BeFalse();
    }
}
