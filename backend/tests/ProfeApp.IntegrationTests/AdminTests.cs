using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
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

    /// <summary>Un centro con su administrador y un docente; devuelve ids y credenciales.</summary>
    private async Task<(HttpClient Plataforma, Guid CentroId, string Email, string Clave)> CentroConDocenteAsync()
    {
        var plataforma = await PlataformaAsync();
        var creado = await ReadAsync(await plataforma.PostAsJsonAsync("/api/v1/plataforma/instituciones", new
        {
            nombre = $"Centro {Guid.NewGuid():N}", plan = "pequeno", maxDocentes = 2,
            adminEmail = $"dir-{Guid.NewGuid():N}@prueba.hn", adminNombre = "Director",
        }));
        var admin = creado.GetProperty("admin");
        var centro = await LoginAsync(admin.GetProperty("email").GetString()!, admin.GetProperty("claveTemporal").GetString()!);
        var docente = await ReadAsync(await centro.PostAsJsonAsync("/api/v1/centro/docentes", new { email = $"d-{Guid.NewGuid():N}@prueba.hn", nombre = "D" }));
        return (plataforma, creado.GetProperty("institucion").GetProperty("id").GetGuid(),
            docente.GetProperty("email").GetString()!, docente.GetProperty("claveTemporal").GetString()!);
    }

    private static object Plan(DateOnly? pagadoHasta, int diasGracia = 0, string? nivel = null) =>
        new { planNombre = "Mensual", monto = 99m, pagadoHasta, diasGracia, comoPagar = "BAC 123", nivel };

    private static DateOnly Hoy => DateOnly.FromDateTime(DateTime.UtcNow.AddHours(-6));

    [Fact]
    public async Task Con_la_licencia_vencida_los_docentes_del_centro_entran_pero_no_respaldan()
    {
        var (plataforma, centroId, email, clave) = await CentroConDocenteAsync();
        (await plataforma.PutAsJsonAsync($"/api/v1/plataforma/instituciones/{centroId}/plan", Plan(Hoy.AddDays(-10), diasGracia: 5)))
            .IsSuccessStatusCode.Should().BeTrue();

        var login = await ReadAsync(await Fixture.CreateClient().PostAsJsonAsync("/api/v1/auth/login", new { email, password = clave }));
        var docente = Fixture.CreateClient();
        docente.DefaultRequestHeaders.Authorization = new("Bearer", login.GetProperty("tokens").GetProperty("accessToken").GetString());
        var push = await docente.PostAsJsonAsync("/api/v1/sync/push", new { clases = new[] { SyncTests.Clase("bloqueada") } });

        login.GetProperty("user").GetProperty("cobro").GetProperty("estado").GetString().Should().Be("soloLectura");
        push.StatusCode.Should().Be(HttpStatusCode.Conflict);
        (await ReadErrorCodeAsync(push)).Should().Be("solo_lectura");
        (await docente.GetAsync("/api/v1/sync/pull")).IsSuccessStatusCode.Should().BeTrue();
    }

    [Fact]
    public async Task Con_el_centro_suspendido_sus_docentes_no_entran()
    {
        var (plataforma, centroId, email, clave) = await CentroConDocenteAsync();
        (await plataforma.PostAsync($"/api/v1/plataforma/instituciones/{centroId}/suspender", null)).IsSuccessStatusCode.Should().BeTrue();

        var login = await Fixture.CreateClient().PostAsJsonAsync("/api/v1/auth/login", new { email, password = clave });

        login.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task Registrar_un_pago_corre_el_vencimiento_desde_el_que_tenia_y_vuelve_a_respaldar()
    {
        var plataforma = await PlataformaAsync();
        var correo = $"personal-{Guid.NewGuid():N}@prueba.hn";
        var cuenta = await ReadAsync(await plataforma.PostAsJsonAsync("/api/v1/plataforma/docentes", new { email = correo, nombre = "Profe Moroso" }));
        var id = cuenta.GetProperty("usuarioId").GetGuid();
        var vencio = new DateOnly(Hoy.Year - 1, 1, 31);
        (await plataforma.PutAsJsonAsync($"/api/v1/plataforma/docentes/{id}/plan", Plan(vencio))).IsSuccessStatusCode.Should().BeTrue();
        var docente = await LoginAsync(correo, cuenta.GetProperty("claveTemporal").GetString()!);
        var bloqueado = await docente.PostAsJsonAsync("/api/v1/sync/push", new { clases = new[] { SyncTests.Clase("al-dia") } });

        var unMes = await ReadAsync(await plataforma.PostAsJsonAsync($"/api/v1/plataforma/docentes/{id}/pagos", new { monto = 99m, periodos = 1 }));
        var alDia = await ReadAsync(await plataforma.PostAsJsonAsync($"/api/v1/plataforma/docentes/{id}/pagos",
            new { monto = 690m, periodos = 12, pagadoHasta = Hoy.AddMonths(12), referencia = "BAC 555" }));
        var pagos = await ReadAsync(await plataforma.GetAsync($"/api/v1/plataforma/docentes/{id}/pagos"));
        var lista = await ReadAsync(await plataforma.GetAsync($"/api/v1/plataforma/docentes?buscar={Uri.EscapeDataString(correo)}"));

        bloqueado.StatusCode.Should().Be(HttpStatusCode.Conflict);
        // El 31 de enero más un mes cae al último día de febrero, no a marzo.
        unMes.GetProperty("pagadoHasta").GetString().Should().Be(vencio.AddMonths(1).ToString("yyyy-MM-dd"));
        alDia.GetProperty("estado").GetString().Should().Be("alDia");
        pagos.GetArrayLength().Should().Be(2);
        pagos[0].GetProperty("referencia").GetString().Should().Be("BAC 555");
        lista.GetProperty("total").GetInt32().Should().Be(1);
        lista.GetProperty("docentes")[0].GetProperty("ultimoPago").GetString().Should().Be(Hoy.ToString("yyyy-MM-dd"));
        // Lo que se quedó en el teléfono sube apenas se pone al día (la copia en memoria se olvidó).
        (await docente.PostAsJsonAsync("/api/v1/sync/push", new { clases = new[] { SyncTests.Clase("al-dia") } }))
            .StatusCode.Should().Be(HttpStatusCode.NoContent);
    }

    [Fact]
    public async Task El_plan_basico_no_deja_respaldar_una_cuarta_asignatura()
    {
        var plataforma = await PlataformaAsync();
        var correo = $"basico-{Guid.NewGuid():N}@prueba.hn";
        var cuenta = await ReadAsync(await plataforma.PostAsJsonAsync("/api/v1/plataforma/docentes", new { email = correo, nombre = "Profe Básico" }));
        (await plataforma.PutAsJsonAsync($"/api/v1/plataforma/docentes/{cuenta.GetProperty("usuarioId").GetGuid()}/plan",
            Plan(Hoy.AddMonths(1), nivel: "basico"))).IsSuccessStatusCode.Should().BeTrue();
        var docente = await LoginAsync(correo, cuenta.GetProperty("claveTemporal").GetString()!);

        var tres = await docente.PostAsJsonAsync("/api/v1/sync/push",
            new { clases = new[] { SyncTests.Clase("a"), SyncTests.Clase("b"), SyncTests.Clase("c") } });
        var cuarta = await docente.PostAsJsonAsync("/api/v1/sync/push", new { clases = new[] { SyncTests.Clase("d") } });
        var otraVez = await docente.PostAsJsonAsync("/api/v1/sync/push", new { clases = new[] { SyncTests.Clase("a", conArchivo: false) } });
        var me = await ReadAsync(await docente.GetAsync("/api/v1/auth/me"));

        tres.StatusCode.Should().Be(HttpStatusCode.NoContent);
        cuarta.StatusCode.Should().Be(HttpStatusCode.Conflict);
        (await ReadErrorCodeAsync(cuarta)).Should().Be("tope_asignaturas");
        otraVez.StatusCode.Should().Be(HttpStatusCode.NoContent);
        me.GetProperty("cobro").GetProperty("topeAsignaturas").GetInt32().Should().Be(3);
    }

    [Fact]
    public async Task La_plataforma_lista_a_los_docentes_del_plan_personal_y_no_a_los_de_un_centro()
    {
        var (plataforma, _, delCentro, _) = await CentroConDocenteAsync();
        var correo = $"lista-{Guid.NewGuid():N}@prueba.hn";
        await ReadAsync(await plataforma.PostAsJsonAsync("/api/v1/plataforma/docentes", new { email = correo, nombre = "Profe Lista" }));

        var personal = await ReadAsync(await plataforma.GetAsync($"/api/v1/plataforma/docentes?buscar={Uri.EscapeDataString(correo)}"));
        var centro = await ReadAsync(await plataforma.GetAsync($"/api/v1/plataforma/docentes?buscar={Uri.EscapeDataString(delCentro)}"));

        personal.GetProperty("total").GetInt32().Should().Be(1);
        personal.GetProperty("docentes")[0].GetProperty("ultimoPago").ValueKind.Should().Be(JsonValueKind.Null);
        centro.GetProperty("total").GetInt32().Should().Be(0);
    }

    private static async Task<string?> ReadErrorCodeAsync(HttpResponseMessage response) =>
        JsonSerializer.Deserialize<JsonElement>(await response.Content.ReadAsStringAsync()).GetProperty("code").GetString();

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
