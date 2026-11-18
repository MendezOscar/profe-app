using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.DependencyInjection;
using ProfeApp.Domain.Common;
using ProfeApp.Infrastructure.Identity;
using ProfeApp.IntegrationTests.Infrastructure;

namespace ProfeApp.IntegrationTests;

public class PadresTests(ApiFixture fixture) : ApiTestBase(fixture)
{
    private const string Identidad = "0501200900001"; // La de SyncTests.Clase.

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
            nombre = "Colegio Familias", plan = "pequeno", maxDocentes = 5,
            adminEmail = $"director-{Guid.NewGuid():N}@prueba.hn", adminNombre = "Director",
        }));
        var admin2 = creado.GetProperty("admin");
        return await EntrarConTemporalAsync(admin2.GetProperty("email").GetString()!, admin2.GetProperty("claveTemporal").GetString()!);
    }

    /// <summary>Centro con 7.º A y 7.º B, el alumno en la A, y su docente con notas y asistencia respaldadas.</summary>
    private async Task<(HttpClient Centro, Guid Alumno, Guid SeccionA, Guid SeccionB)> EscenarioAsync()
    {
        var centro = await CentroAsync();
        var anio = (await ReadAsync(await centro.PostAsJsonAsync("/api/v1/centro/anios",
            new { anio = 2027, inicio = "2027-02-01", fin = "2027-11-30", cierres = (string?[]?)null, actual = true }))).GetProperty("id").GetGuid();
        var grado = (await ReadAsync(await centro.PostAsJsonAsync("/api/v1/centro/grados", new { nivel = "basica", nombre = "7.º grado" })))
            .GetProperty("id").GetGuid();
        async Task<Guid> Seccion(string nombre) => (await ReadAsync(await centro.PostAsJsonAsync("/api/v1/centro/secciones", new
        {
            anioLectivoId = anio, gradoId = grado, nombre, jornada = "matutina", cupo = (int?)null, aulaId = (Guid?)null, maestroGuiaId = (Guid?)null,
        }))).GetProperty("id").GetGuid();
        var a = await Seccion("A");
        var b = await Seccion("B");
        var alumno = (await ReadAsync(await centro.PostAsJsonAsync($"/api/v1/centro/secciones/{a}/alumnos",
            new { identidad = "0501-2009-00001", nombre = "Ana Pérez", tipo = "nuevo_ingreso" }))).GetProperty("alumnoId").GetGuid();

        var cuenta = await ReadAsync(await centro.PostAsJsonAsync("/api/v1/centro/docentes",
            new { email = $"profe-{Guid.NewGuid():N}@prueba.hn", nombre = "Profe Química" }));
        var docente = await EntrarConTemporalAsync(cuenta.GetProperty("email").GetString()!, cuenta.GetProperty("claveTemporal").GetString()!);
        (await docente.PostAsJsonAsync("/api/v1/sync/push", new { clases = new[] { SyncTests.Clase("quimica") } }))
            .StatusCode.Should().Be(HttpStatusCode.NoContent);
        var ahora = DateTimeOffset.UtcNow;
        var pronto = DateTime.Today.AddDays(3).ToString("yyyy-MM-dd");
        object R(string tipo, string clave, object datos) =>
            new { tipo, claseClave = "quimica", clave, datos = JsonSerializer.Serialize(datos), eliminado = false, actualizadoEn = ahora };
        (await docente.PostAsJsonAsync("/api/v1/sync/push", new
        {
            clases = Array.Empty<object>(),
            registros = new[]
            {
                R("actividad", "t1", new { parcial = "PARCIAL I", titulo = "Tarea 1", fecha = "2027-03-01", puntos = 10 }),
                R("actividad", "ex", new { parcial = "PARCIAL I", titulo = "Examen", fecha = pronto, puntos = 20 }),
                R("calificacion", $"t1|{Identidad}", new { valor = 8.5 }),
                R("calificacion", "t1|OTRO-ALUMNO", new { valor = 2 }),
                R("sesion", "s1", new { parcial = "PARCIAL I", fecha = "2027-03-02" }),
                R("sesion", "s2", new { parcial = "PARCIAL I", fecha = "2027-03-03" }),
                R("asistencia", $"s1|{Identidad}", new { estado = "A" }),
            },
        })).StatusCode.Should().Be(HttpStatusCode.NoContent);
        return (centro, alumno, a, b);
    }

    private async Task<(HttpClient Cliente, JsonElement Respuesta)> RegistrarPadreAsync(string codigo, string? email = null)
    {
        var cliente = Fixture.CreateClient();
        var respuesta = await cliente.PostAsJsonAsync("/api/v1/auth/registro-padre", new
        {
            codigo, email = email ?? $"padre-{Guid.NewGuid():N}@prueba.hn", password = "Familia-1234", fullName = "Marta Pérez",
        });
        var cuerpo = await respuesta.Content.ReadFromJsonAsync<JsonElement>();
        if (respuesta.IsSuccessStatusCode) Autorizar(cliente, cuerpo);
        return (cliente, cuerpo);
    }

    [Fact]
    public async Task El_padre_entra_con_el_codigo_y_ve_notas_asistencia_y_entregas_de_su_hijo()
    {
        var (centro, alumno, _, _) = await EscenarioAsync();
        var codigo = (await ReadAsync(await centro.PostAsync($"/api/v1/centro/alumnos/{alumno}/familia/codigo", null)))
            .GetProperty("codigo").GetString()!;
        codigo.Should().MatchRegex("^[A-Z2-9]{4}-[A-Z2-9]{4}$");

        var (padre, registro) = await RegistrarPadreAsync(codigo.ToLowerInvariant().Replace("-", " "));
        registro.GetProperty("user").GetProperty("role").GetString().Should().Be("Padre");

        var hijos = (await ReadAsync(await padre.GetAsync("/api/v1/padres/hijos"))).EnumerateArray().ToList();
        hijos.Should().ContainSingle();
        hijos[0].GetProperty("seccion").GetString().Should().Be("7.º grado A");

        var resumen = await ReadAsync(await padre.GetAsync($"/api/v1/padres/hijos/{alumno}"));
        var quimica = resumen.GetProperty("asignaturas")[0];
        quimica.GetProperty("asignatura").GetString().Should().Be("QUÍMICA");
        quimica.GetProperty("docente").GetString().Should().Be("Profe Química");
        var parcial = quimica.GetProperty("parciales")[0];
        parcial.GetProperty("obtenidos").GetDecimal().Should().Be(8.5m);
        parcial.GetProperty("calificados").GetDecimal().Should().Be(10m, "sólo cuenta lo ya calificado");
        parcial.GetProperty("actividades").GetArrayLength().Should().Be(2);
        var asistencia = resumen.GetProperty("asistencia");
        asistencia.GetProperty("sesiones").GetInt32().Should().Be(2);
        asistencia.GetProperty("ausencias").GetInt32().Should().Be(1);
        asistencia.GetProperty("recientes")[0].GetProperty("fecha").GetString().Should().Be("2027-03-02");
        resumen.GetProperty("proximas")[0].GetProperty("titulo").GetString().Should().Be("Examen");

        // El centro ve quién entró y le puede quitar el acceso.
        var familia = await ReadAsync(await centro.GetAsync($"/api/v1/centro/alumnos/{alumno}/familia"));
        var vinculo = familia.GetProperty("vinculos")[0].GetProperty("usuarioId").GetGuid();
        (await centro.DeleteAsync($"/api/v1/centro/alumnos/{alumno}/familia/{vinculo}")).StatusCode.Should().Be(HttpStatusCode.NoContent);
        (await padre.GetAsync($"/api/v1/padres/hijos/{alumno}")).StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Un_codigo_invalido_o_reemplazado_no_sirve_y_nadie_ve_hijos_ajenos()
    {
        var (centro, alumno, _, _) = await EscenarioAsync();
        var viejo = (await ReadAsync(await centro.PostAsync($"/api/v1/centro/alumnos/{alumno}/familia/codigo", null))).GetProperty("codigo").GetString()!;
        var nuevo = (await ReadAsync(await centro.PostAsync($"/api/v1/centro/alumnos/{alumno}/familia/codigo", null))).GetProperty("codigo").GetString()!;
        nuevo.Should().NotBe(viejo);

        var (_, fallo) = await RegistrarPadreAsync(viejo);
        fallo.GetProperty("code").GetString().Should().Be("codigo_invalido");

        // Otro padre, de otro centro, no ve a este alumno.
        var (otroCentro, otroAlumno, _, _) = await EscenarioAsync();
        var otroCodigo = (await ReadAsync(await otroCentro.PostAsync($"/api/v1/centro/alumnos/{otroAlumno}/familia/codigo", null)))
            .GetProperty("codigo").GetString()!;
        var (ajeno, _) = await RegistrarPadreAsync(otroCodigo);
        (await ajeno.GetAsync($"/api/v1/padres/hijos/{alumno}")).StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await ajeno.GetAsync("/api/v1/centro/estructura")).StatusCode.Should().Be(HttpStatusCode.Forbidden);
        (await ajeno.GetAsync("/api/v1/sync/pull")).StatusCode.Should().Be(HttpStatusCode.Forbidden);

        // Con cuenta ya creada, el segundo hijo se agrega con su código.
        (await ReadAsync(await ajeno.PostAsJsonAsync("/api/v1/padres/vincular", new { codigo = nuevo })))
            .GetProperty("alumnoId").GetGuid().Should().Be(alumno);
        (await ReadAsync(await ajeno.GetAsync("/api/v1/padres/hijos"))).GetArrayLength().Should().Be(2);
    }

    [Fact]
    public async Task Los_comunicados_llegan_a_las_familias_de_su_seccion_y_el_centro_ve_quien_leyo()
    {
        var (centro, alumno, a, b) = await EscenarioAsync();
        var codigo = (await ReadAsync(await centro.PostAsync($"/api/v1/centro/alumnos/{alumno}/familia/codigo", null))).GetProperty("codigo").GetString()!;
        var (padre, _) = await RegistrarPadreAsync(codigo);

        var todos = (await ReadAsync(await centro.PostAsJsonAsync("/api/v1/centro/comunicados",
            new { titulo = "Reunión de padres", cuerpo = "El viernes a las 3:00 p. m.", seccionIds = (Guid[]?)null }))).GetProperty("id").GetGuid();
        await centro.PostAsJsonAsync("/api/v1/centro/comunicados", new { titulo = "Gira de 7.º B", cuerpo = "Solo la B.", seccionIds = new[] { b } });
        await centro.PostAsJsonAsync("/api/v1/centro/comunicados", new { titulo = "Examen de la A", cuerpo = "Solo la A.", seccionIds = new[] { a } });

        var recibidos = (await ReadAsync(await padre.GetAsync("/api/v1/padres/comunicados"))).EnumerateArray().ToList();
        recibidos.Select(c => c.GetProperty("titulo").GetString()).Should().BeEquivalentTo(["Reunión de padres", "Examen de la A"]);
        recibidos.Should().OnlyContain(c => !c.GetProperty("leido").GetBoolean());

        (await padre.PostAsync($"/api/v1/padres/comunicados/{todos}/leido", null)).StatusCode.Should().Be(HttpStatusCode.NoContent);
        var enCentro = (await ReadAsync(await centro.GetAsync("/api/v1/centro/comunicados"))).EnumerateArray()
            .Single(c => c.GetProperty("id").GetGuid() == todos);
        enCentro.GetProperty("leidos").GetInt32().Should().Be(1);
        enCentro.GetProperty("destinatarios").GetInt32().Should().Be(1);
        (await centro.GetAsync("/api/v1/centro/comunicados")).IsSuccessStatusCode.Should().BeTrue();
        (await ReadAsync(await centro.GetAsync("/api/v1/centro/comunicados"))).EnumerateArray()
            .Single(c => c.GetProperty("titulo").GetString() == "Gira de 7.º B").GetProperty("destinatarios").GetInt32().Should().Be(0);
    }
}
