using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.DependencyInjection;
using ProfeApp.Domain.Common;
using ProfeApp.Infrastructure.Identity;
using ProfeApp.IntegrationTests.Infrastructure;

namespace ProfeApp.IntegrationTests;

public class MatriculaTests(ApiFixture fixture) : ApiTestBase(fixture)
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
            nombre = "Instituto Matrícula", plan = "pequeno", maxDocentes = 5,
            adminEmail = $"director-{Guid.NewGuid():N}@prueba.hn", adminNombre = "Director",
        }));
        var admin2 = creado.GetProperty("admin");
        return await EntrarConTemporalAsync(admin2.GetProperty("email").GetString()!, admin2.GetProperty("claveTemporal").GetString()!);
    }

    /// <summary>Año 2027 con 7.º A y 7.º B (cupo 2 en la A).</summary>
    private static async Task<(Guid A, Guid B)> SeccionesAsync(HttpClient c)
    {
        var anio = (await ReadAsync(await c.PostAsJsonAsync("/api/v1/centro/anios",
            new { anio = 2027, inicio = "2027-02-01", fin = "2027-11-30", cierres = (string?[]?)null, actual = true }))).GetProperty("id").GetGuid();
        var grado = (await ReadAsync(await c.PostAsJsonAsync("/api/v1/centro/grados", new { nivel = "basica", nombre = "7.º grado" })))
            .GetProperty("id").GetGuid();
        async Task<Guid> Seccion(string nombre, int? cupo) => (await ReadAsync(await c.PostAsJsonAsync("/api/v1/centro/secciones", new
        {
            anioLectivoId = anio, gradoId = grado, nombre, jornada = "matutina", cupo, aulaId = (Guid?)null, maestroGuiaId = (Guid?)null,
        }))).GetProperty("id").GetGuid();
        return (await Seccion("A", 2), await Seccion("B", null));
    }

    private static object Lista(params (string Id, string Nombre)[] alumnos) =>
        new { alumnos = alumnos.Select(a => new { identidad = a.Id, nombre = a.Nombre }) };

    [Fact]
    public async Task La_lista_de_SACE_matricula_sin_duplicar_y_avisa_quien_esta_en_otra_seccion()
    {
        var centro = await CentroAsync();
        var (a, b) = await SeccionesAsync(centro);

        var primera = await ReadAsync(await centro.PostAsJsonAsync($"/api/v1/centro/secciones/{a}/importar",
            Lista(("0801-2014-00001", "Ana López"), ("0801201400002", "Beto Cruz"), ("0801 2014 00003", "Carla Díaz"))));
        primera.GetProperty("nuevos").GetInt32().Should().Be(3);
        primera.GetProperty("activos").GetInt32().Should().Be(3);
        primera.GetProperty("cupo").GetInt32().Should().Be(2, "se avisa que pasa el cupo, no se bloquea: SACE manda");

        // Repetir el mismo archivo no duplica; la identidad con guiones es la misma.
        var segunda = await ReadAsync(await centro.PostAsJsonAsync($"/api/v1/centro/secciones/{a}/importar",
            Lista(("080120140000 1", "Ana López Mejía"))));
        segunda.GetProperty("yaEstaban").GetInt32().Should().Be(1);

        var enB = await ReadAsync(await centro.PostAsJsonAsync($"/api/v1/centro/secciones/{b}/importar",
            Lista(("0801201400002", "Beto Cruz"), ("0801201400004", "Dani Paz"))));
        enB.GetProperty("nuevos").GetInt32().Should().Be(1);
        var conflicto = enB.GetProperty("enOtraSeccion")[0];
        conflicto.GetProperty("identidad").GetString().Should().Be("0801201400002");
        conflicto.GetProperty("seccion").GetString().Should().Be("7.º grado A (matutina)");

        var movido = await ReadAsync(await centro.PostAsJsonAsync($"/api/v1/centro/secciones/{b}/importar", new
        {
            alumnos = new[] { new { identidad = "0801201400002", nombre = "Beto Cruz" } }, moverDeSeccion = true,
        }));
        movido.GetProperty("movidos").GetInt32().Should().Be(1);

        var listaA = (await ReadAsync(await centro.GetAsync($"/api/v1/centro/secciones/{a}/alumnos"))).EnumerateArray().ToList();
        listaA.Select(x => x.GetProperty("nombre").GetString()).Should().Equal("Ana López Mejía", "Carla Díaz");

        var estructura = await ReadAsync(await centro.GetAsync("/api/v1/centro/estructura"));
        estructura.GetProperty("secciones").EnumerateArray().Select(s => s.GetProperty("matriculados").GetInt32()).Should().Equal(2, 2);

        (await centro.DeleteAsync($"/api/v1/centro/secciones/{a}")).StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task La_ficha_guarda_encargados_y_la_baja_queda_con_fecha_y_motivo()
    {
        var centro = await CentroAsync();
        var (a, b) = await SeccionesAsync(centro);
        var matriculado = await ReadAsync(await centro.PostAsJsonAsync($"/api/v1/centro/secciones/{a}/alumnos",
            new { identidad = "0801201400010", nombre = "Eva Ruiz", tipo = "traslado_entrante" }));
        var alumno = matriculado.GetProperty("alumnoId").GetGuid();
        var matricula = matriculado.GetProperty("matriculaId").GetGuid();

        (await centro.PostAsJsonAsync($"/api/v1/centro/secciones/{b}/alumnos",
            new { identidad = "0801201400010", nombre = "Eva Ruiz", tipo = "nuevo_ingreso" }))
            .StatusCode.Should().Be(HttpStatusCode.Conflict, "una matrícula por año");

        var ficha = await ReadAsync(await centro.PutAsJsonAsync($"/api/v1/centro/alumnos/{alumno}", new
        {
            identidad = "0801201400010", nombre = "Eva Ruiz", fechaNacimiento = "2014-03-02", sexo = "F",
            direccion = "Col. Kennedy", salud = "Alergia a la penicilina", notas = (string?)null,
            encargados = new[]
            {
                new { nombre = "Marta Ruiz", parentesco = "Madre", telefono = "9999-0000", correo = "MARTA@correo.hn", principal = false },
                new { nombre = "Juan Ruiz", parentesco = "Padre", telefono = "8888-0000", correo = (string?)null, principal = true },
            },
        }));
        ficha.GetProperty("encargados")[0].GetProperty("nombre").GetString().Should().Be("Juan Ruiz", "el principal va primero");
        ficha.GetProperty("encargados")[1].GetProperty("correo").GetString().Should().Be("marta@correo.hn");
        ficha.GetProperty("salud").GetString().Should().Be("Alergia a la penicilina");

        (await centro.PutAsJsonAsync($"/api/v1/centro/matriculas/{matricula}/seccion", new { seccionId = b }))
            .StatusCode.Should().Be(HttpStatusCode.NoContent);
        (await centro.PostAsJsonAsync($"/api/v1/centro/matriculas/{matricula}/baja",
            new { estado = "trasladada", fecha = "2027-03-15", motivo = "Se mudó a San Pedro Sula" }))
            .StatusCode.Should().Be(HttpStatusCode.NoContent);

        var historial = (await ReadAsync(await centro.GetAsync($"/api/v1/centro/alumnos/{alumno}"))).GetProperty("matriculas")[0];
        historial.GetProperty("estado").GetString().Should().Be("trasladada");
        historial.GetProperty("seccion").GetString().Should().Be("7.º grado B (matutina)");
        historial.GetProperty("motivoBaja").GetString().Should().Be("Se mudó a San Pedro Sula");

        var buscado = await ReadAsync(await centro.GetAsync("/api/v1/centro/alumnos?buscar=eva"));
        buscado.GetProperty("total").GetInt32().Should().Be(1);
        buscado.GetProperty("alumnos")[0].GetProperty("estado").GetString().Should().Be("trasladada");
    }

    [Fact]
    public async Task Otro_centro_no_ve_las_fichas()
    {
        var uno = await CentroAsync();
        var (a, _) = await SeccionesAsync(uno);
        var alumno = (await ReadAsync(await uno.PostAsJsonAsync($"/api/v1/centro/secciones/{a}/alumnos",
            new { identidad = "0801201400020", nombre = "Fito Gómez", tipo = "nuevo_ingreso" }))).GetProperty("alumnoId").GetGuid();

        var otro = await CentroAsync();
        (await otro.GetAsync($"/api/v1/centro/alumnos/{alumno}")).StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await otro.GetAsync($"/api/v1/centro/secciones/{a}/alumnos")).StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await ReadAsync(await otro.GetAsync("/api/v1/centro/alumnos?buscar=fito"))).GetProperty("total").GetInt32().Should().Be(0);
        // Un docente no entra a las fichas del centro.
        var docente = await RegisterAsync();
        (await docente.GetAsync($"/api/v1/centro/alumnos/{alumno}")).StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task El_docente_ve_su_carga_y_la_lista_de_matricula_sin_la_ficha()
    {
        var centro = await CentroAsync();
        var (a, b) = await SeccionesAsync(centro);
        var cuenta = await ReadAsync(await centro.PostAsJsonAsync("/api/v1/centro/docentes",
            new { email = $"profe-{Guid.NewGuid():N}@prueba.hn", nombre = "Profe Carga" }));
        var docenteId = cuenta.GetProperty("usuarioId").GetGuid();

        var estructura = await ReadAsync(await centro.GetAsync("/api/v1/centro/estructura"));
        var grado = estructura.GetProperty("grados")[0].GetProperty("id").GetGuid();
        await centro.PostAsJsonAsync("/api/v1/centro/asignaturas", new { gradoIds = new[] { grado }, nombres = new[] { "Español", "Matemáticas" } });
        estructura = await ReadAsync(await centro.GetAsync("/api/v1/centro/estructura"));
        var espanol = estructura.GetProperty("grados")[0].GetProperty("asignaturas")[0].GetProperty("id").GetGuid();
        (await centro.PutAsJsonAsync($"/api/v1/centro/secciones/{a}/carga",
            new { asignaciones = new[] { new { asignaturaId = espanol, docenteId } } })).IsSuccessStatusCode.Should().BeTrue();
        // Guía de la B sin dar clase en ella.
        var anio = estructura.GetProperty("anioId").GetGuid();
        (await centro.PutAsJsonAsync($"/api/v1/centro/secciones/{b}", new
        {
            anioLectivoId = anio, gradoId = grado, nombre = "B", jornada = "matutina", cupo = (int?)null, aulaId = (Guid?)null, maestroGuiaId = docenteId,
        })).IsSuccessStatusCode.Should().BeTrue();

        await centro.PostAsJsonAsync($"/api/v1/centro/secciones/{a}/importar",
            Lista(("0801201400031", "Gina Mora"), ("0801201400032", "Hugo Vega")));
        var lista = (await ReadAsync(await centro.GetAsync($"/api/v1/centro/secciones/{a}/alumnos"))).EnumerateArray().ToList();
        var hugo = lista.Single(x => x.GetProperty("nombre").GetString() == "Hugo Vega").GetProperty("matriculaId").GetGuid();
        await centro.PostAsJsonAsync($"/api/v1/centro/matriculas/{hugo}/baja", new { estado = "retirada", fecha = "2027-03-01", motivo = "Salud" });

        var docente = await EntrarConTemporalAsync(cuenta.GetProperty("email").GetString()!, cuenta.GetProperty("claveTemporal").GetString()!);
        var carga = await ReadAsync(await docente.GetAsync("/api/v1/mi-centro/carga"));
        carga.GetProperty("centro").GetString().Should().Be("Instituto Matrícula");
        carga.GetProperty("anio").GetInt32().Should().Be(2027);
        var secciones = carga.GetProperty("secciones").EnumerateArray().ToList();
        secciones.Should().HaveCount(2);
        var seccionA = secciones.Single(s => s.GetProperty("nombre").GetString() == "A");
        seccionA.GetProperty("asignaturas").EnumerateArray().Select(x => x.GetString()).Should().Equal("Español");
        seccionA.GetProperty("esGuia").GetBoolean().Should().BeFalse();
        seccionA.GetProperty("alumnos").EnumerateArray().Select(x => x.GetProperty("estado").GetString()).Should().Equal("activa", "retirada");
        seccionA.GetProperty("alumnos")[0].TryGetProperty("salud", out _).Should().BeFalse();
        secciones.Single(s => s.GetProperty("nombre").GetString() == "B").GetProperty("esGuia").GetBoolean().Should().BeTrue();

        // Un docente del plan personal no tiene centro.
        var personal = await RegisterAsync();
        var vacia = await ReadAsync(await personal.GetAsync("/api/v1/mi-centro/carga"));
        vacia.GetProperty("secciones").GetArrayLength().Should().Be(0);
        (await centro.GetAsync("/api/v1/mi-centro/carga")).StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }
}
