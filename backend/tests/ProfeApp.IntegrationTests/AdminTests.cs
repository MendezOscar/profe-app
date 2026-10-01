using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.DependencyInjection;
using ProfeApp.Domain.Common;
using ProfeApp.Infrastructure.Identity;
using ProfeApp.IntegrationTests.Infrastructure;

namespace ProfeApp.IntegrationTests;

public class AdminTests(ApiFixture fixture) : ApiTestBase(fixture)
{
    private async Task<HttpClient> PlataformaAsync()
    {
        var email = $"plataforma-{Guid.NewGuid():N}@prueba.hn";
        using (var scope = Fixture.Services.CreateScope())
        {
            var users = scope.ServiceProvider.GetRequiredService<UserManager<AppUser>>();
            var admin = new AppUser { Id = Guid.NewGuid(), UserName = email, Email = email, FullName = "Plataforma", CreatedAt = DateTimeOffset.UtcNow };
            (await users.CreateAsync(admin, "Prueba1234!")).Succeeded.Should().BeTrue();
            await users.AddToRoleAsync(admin, Roles.PlatformAdmin);
        }
        return await LoginAsync(email, "Prueba1234!");
    }

    /// <summary>Crea un centro y devuelve el cliente de su administrador ya logueado.</summary>
    private async Task<HttpClient> CentroAsync(int cupo = 2)
    {
        var plataforma = await PlataformaAsync();
        var creado = await ReadAsync(await plataforma.PostAsJsonAsync("/api/v1/plataforma/instituciones", new
        {
            nombre = "Instituto de Prueba",
            plan = "pequeno",
            maxDocentes = cupo,
            adminEmail = $"director-{Guid.NewGuid():N}@prueba.hn",
            adminNombre = "Directora",
        }));
        var admin = creado.GetProperty("admin");
        return await LoginAsync(admin.GetProperty("email").GetString()!, admin.GetProperty("claveTemporal").GetString()!);
    }

    [Fact]
    public async Task Las_cuentas_de_administracion_se_eliminan_sin_tocar_los_datos_de_los_docentes()
    {
        var docente = await RegisterAsync();
        (await docente.PostAsJsonAsync("/api/v1/sync/push", new
        {
            clases = Array.Empty<object>(),
            registros = new[] { new { tipo = "plantilla", claseClave = "", clave = "mia", datos = "{\"nombre\":\"Mía\",\"rubros\":[]}", eliminado = false, actualizadoEn = DateTimeOffset.UtcNow } },
        })).IsSuccessStatusCode.Should().BeTrue();

        var plataforma = await PlataformaAsync();
        var creado = await ReadAsync(await plataforma.PostAsJsonAsync("/api/v1/plataforma/instituciones", new
        {
            nombre = "Instituto a Borrar",
            plan = "pequeno",
            maxDocentes = 2,
            adminEmail = $"director-{Guid.NewGuid():N}@prueba.hn",
            adminNombre = "Director",
        }));
        var admin = creado.GetProperty("admin");
        var clave = admin.GetProperty("claveTemporal").GetString()!;
        var centro = await LoginAsync(admin.GetProperty("email").GetString()!, clave);

        (await plataforma.PostAsJsonAsync("/api/v1/auth/delete-account", new { password = "Prueba1234!" }))
            .StatusCode.Should().Be(HttpStatusCode.Forbidden, "la cuenta de plataforma ve los datos de todos");
        (await centro.PostAsJsonAsync("/api/v1/auth/delete-account", new { password = clave }))
            .StatusCode.Should().Be(HttpStatusCode.NoContent);

        var pull = await ReadAsync(await docente.GetAsync("/api/v1/sync/pull"));
        pull.GetProperty("registros").EnumerateArray().Select(r => r.GetProperty("clave").GetString()).Should().Contain("mia");
    }

    [Fact]
    public async Task El_centro_da_de_alta_docentes_que_entran_con_clave_temporal_y_deben_cambiarla()
    {
        var centro = await CentroAsync();

        var docente = await ReadAsync(await centro.PostAsJsonAsync("/api/v1/centro/docentes",
            new { email = $"profe-{Guid.NewGuid():N}@prueba.hn", nombre = "Profe Uno" }));
        var login = await ReadAsync(await Fixture.CreateClient().PostAsJsonAsync("/api/v1/auth/login", new
        {
            email = docente.GetProperty("email").GetString(),
            password = docente.GetProperty("claveTemporal").GetString(),
        }));
        var panel = await ReadAsync(await centro.GetAsync("/api/v1/centro"));

        login.GetProperty("user").GetProperty("mustChangePassword").GetBoolean().Should().BeTrue();
        login.GetProperty("user").GetProperty("role").GetString().Should().Be("Docente");
        panel.GetProperty("institucion").GetProperty("docentes").GetInt32().Should().Be(1);
        panel.GetProperty("docentes")[0].GetProperty("nombre").GetString().Should().Be("Profe Uno");
    }

    [Fact]
    public async Task El_cupo_de_la_licencia_no_se_puede_pasar()
    {
        var centro = await CentroAsync(cupo: 1);
        await ReadAsync(await centro.PostAsJsonAsync("/api/v1/centro/docentes", new { email = $"a-{Guid.NewGuid():N}@prueba.hn", nombre = "A" }));

        var segundo = await centro.PostAsJsonAsync("/api/v1/centro/docentes", new { email = $"b-{Guid.NewGuid():N}@prueba.hn", nombre = "B" });

        segundo.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task Un_docente_desactivado_ya_no_entra_y_se_puede_reactivar()
    {
        var centro = await CentroAsync();
        var docente = await ReadAsync(await centro.PostAsJsonAsync("/api/v1/centro/docentes", new { email = $"c-{Guid.NewGuid():N}@prueba.hn", nombre = "C" }));
        var id = docente.GetProperty("usuarioId").GetGuid();
        var credenciales = new { email = docente.GetProperty("email").GetString(), password = docente.GetProperty("claveTemporal").GetString() };

        (await centro.PostAsync($"/api/v1/centro/docentes/{id}/desactivar", null)).StatusCode.Should().Be(HttpStatusCode.NoContent);
        var bloqueado = await Fixture.CreateClient().PostAsJsonAsync("/api/v1/auth/login", credenciales);
        (await centro.PostAsync($"/api/v1/centro/docentes/{id}/activar", null)).StatusCode.Should().Be(HttpStatusCode.NoContent);
        var entra = await Fixture.CreateClient().PostAsJsonAsync("/api/v1/auth/login", credenciales);

        bloqueado.IsSuccessStatusCode.Should().BeFalse();
        entra.IsSuccessStatusCode.Should().BeTrue();
    }

    [Fact]
    public async Task Con_la_licencia_vencida_los_docentes_del_centro_no_entran()
    {
        var plataforma = await PlataformaAsync();
        var nombre = $"Centro {Guid.NewGuid():N}";
        var creado = await ReadAsync(await plataforma.PostAsJsonAsync("/api/v1/plataforma/instituciones", new
        {
            nombre, plan = "pequeno", maxDocentes = 2, adminEmail = $"dir-{Guid.NewGuid():N}@prueba.hn", adminNombre = "Director",
        }));
        var admin = creado.GetProperty("admin");
        var centro = await LoginAsync(admin.GetProperty("email").GetString()!, admin.GetProperty("claveTemporal").GetString()!);
        var docente = await ReadAsync(await centro.PostAsJsonAsync("/api/v1/centro/docentes", new { email = $"d-{Guid.NewGuid():N}@prueba.hn", nombre = "D" }));

        await ReadAsync(await plataforma.PutAsJsonAsync($"/api/v1/plataforma/instituciones/{creado.GetProperty("institucion").GetProperty("id").GetGuid()}",
            new { plan = "pequeno", maxDocentes = 2, venceEn = DateTimeOffset.UtcNow.AddDays(-1), activa = true }));
        var login = await Fixture.CreateClient().PostAsJsonAsync("/api/v1/auth/login",
            new { email = docente.GetProperty("email").GetString(), password = docente.GetProperty("claveTemporal").GetString() });

        login.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task Un_docente_no_puede_usar_el_panel_del_centro_ni_el_de_plataforma()
    {
        var docente = await RegisterAsync();

        (await docente.GetAsync("/api/v1/centro")).StatusCode.Should().Be(HttpStatusCode.Forbidden);
        (await docente.GetAsync("/api/v1/plataforma/instituciones")).StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task La_plataforma_crea_cuentas_del_plan_personal()
    {
        var plataforma = await PlataformaAsync();

        var cuenta = await ReadAsync(await plataforma.PostAsJsonAsync("/api/v1/plataforma/docentes",
            new { email = $"personal-{Guid.NewGuid():N}@prueba.hn", nombre = "Profe Personal" }));
        var login = await Fixture.CreateClient().PostAsJsonAsync("/api/v1/auth/login",
            new { email = cuenta.GetProperty("email").GetString(), password = cuenta.GetProperty("claveTemporal").GetString() });

        login.StatusCode.Should().Be(HttpStatusCode.OK);
    }
}
