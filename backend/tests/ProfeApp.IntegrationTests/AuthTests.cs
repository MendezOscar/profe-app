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
    public async Task No_se_puede_registrar_dos_veces_el_mismo_correo()
    {
        var email = $"repetido-{Guid.NewGuid():N}@prueba.hn";
        await RegisterAsync(email);

        var response = await Fixture.CreateClient().PostAsJsonAsync("/api/v1/auth/register",
            new { email, password = "Prueba1234!", fullName = "Otro" });

        response.StatusCode.Should().Be(HttpStatusCode.Conflict);
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
}
