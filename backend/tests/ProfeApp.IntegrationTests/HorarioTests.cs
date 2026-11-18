using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.DependencyInjection;
using ProfeApp.Domain.Common;
using ProfeApp.Infrastructure.Identity;
using ProfeApp.IntegrationTests.Infrastructure;

namespace ProfeApp.IntegrationTests;

public class HorarioTests(ApiFixture fixture) : ApiTestBase(fixture)
{
    private sealed record Escenario(
        HttpClient Centro, HttpClient Docente, Guid DocenteId, Guid A, Guid B, Guid C,
        Guid Espanol, Guid Mate, Guid Aula1, Guid B1, Guid B2, Guid Receso, Guid V1);

    private static async Task<Guid> IdAsync(HttpResponseMessage r) => (await ReadAsync(r)).GetProperty("id").GetGuid();

    private async Task<Escenario> EscenarioAsync()
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
            nombre = "Colegio Horario", plan = "pequeno", maxDocentes = 5,
            adminEmail = $"director-{Guid.NewGuid():N}@prueba.hn", adminNombre = "Director",
        }));
        var admin2 = creado.GetProperty("admin");
        var c = await EntrarConTemporalAsync(admin2.GetProperty("email").GetString()!, admin2.GetProperty("claveTemporal").GetString()!);

        // Año alrededor de hoy: la lista del día no admite fechas futuras ni fuera del año.
        var hoy = DateTime.Today;
        var anio = await IdAsync(await c.PostAsJsonAsync("/api/v1/centro/anios", new
        {
            anio = hoy.Year, inicio = hoy.AddDays(-60).ToString("yyyy-MM-dd"), fin = hoy.AddDays(60).ToString("yyyy-MM-dd"),
            cierres = (string?[]?)null, actual = true,
        }));
        var grado = await IdAsync(await c.PostAsJsonAsync("/api/v1/centro/grados", new { nivel = "basica", nombre = "7.º grado" }));
        await c.PostAsJsonAsync("/api/v1/centro/asignaturas", new { gradoIds = new[] { grado }, nombres = new[] { "Español", "Matemáticas" } });
        var asignaturas = (await ReadAsync(await c.GetAsync("/api/v1/centro/estructura"))).GetProperty("grados")[0].GetProperty("asignaturas");
        var espanol = asignaturas[0].GetProperty("id").GetGuid();
        var mate = asignaturas[1].GetProperty("id").GetGuid();
        var aula1 = await IdAsync(await c.PostAsJsonAsync("/api/v1/centro/aulas", new { nombre = "Aula 1", capacidad = 30 }));
        var aula2 = await IdAsync(await c.PostAsJsonAsync("/api/v1/centro/aulas", new { nombre = "Aula 2", capacidad = 30 }));

        var cuenta = await ReadAsync(await c.PostAsJsonAsync("/api/v1/centro/docentes",
            new { email = $"profe-{Guid.NewGuid():N}@prueba.hn", nombre = "Profe Español" }));
        var docenteId = cuenta.GetProperty("usuarioId").GetGuid();

        async Task<Guid> Seccion(string nombre, string jornada, Guid aula, Guid? guia) => await IdAsync(await c.PostAsJsonAsync("/api/v1/centro/secciones", new
        {
            anioLectivoId = anio, gradoId = grado, nombre, jornada, cupo = (int?)null, aulaId = aula, maestroGuiaId = guia,
        }));
        var a = await Seccion("A", "matutina", aula1, docenteId);
        var b = await Seccion("B", "matutina", aula2, null);
        var cc = await Seccion("C", "vespertina", aula1, null);
        foreach (var s in new[] { a, b })
            (await c.PutAsJsonAsync($"/api/v1/centro/secciones/{s}/carga",
                new { asignaciones = new[] { new { asignaturaId = espanol, docenteId } } })).IsSuccessStatusCode.Should().BeTrue();

        async Task<Guid> Bloque(string jornada, string inicio, string fin, bool receso = false) =>
            await IdAsync(await c.PostAsJsonAsync("/api/v1/centro/bloques", new { jornada, inicio = inicio + ":00", fin = fin + ":00", esReceso = receso }));
        var b2 = await Bloque("matutina", "07:45", "08:30");
        var b1 = await Bloque("matutina", "07:00", "07:45");
        var receso = await Bloque("matutina", "08:30", "08:50", receso: true);
        var v1 = await Bloque("vespertina", "13:00", "13:45");

        var docente = await EntrarConTemporalAsync(cuenta.GetProperty("email").GetString()!, cuenta.GetProperty("claveTemporal").GetString()!);
        return new Escenario(c, docente, docenteId, a, b, cc, espanol, mate, aula1, b1, b2, receso, v1);
    }

    private static object Horario(params (int Dia, Guid Bloque, Guid Asignatura, Guid? Aula)[] celdas) =>
        new { celdas = celdas.Select(x => new { dia = x.Dia, bloqueId = x.Bloque, asignaturaId = x.Asignatura, aulaId = x.Aula }) };

    [Fact]
    public async Task El_horario_no_deja_a_un_docente_ni_un_aula_en_dos_lugares_a_la_vez()
    {
        var e = await EscenarioAsync();
        var c = e.Centro;

        var bloques = (await ReadAsync(await c.GetAsync("/api/v1/centro/bloques"))).EnumerateArray()
            .Where(x => x.GetProperty("jornada").GetString() == "matutina").Select(x => x.GetProperty("orden").GetInt32());
        bloques.Should().Equal(1, 2, 3);
        (await c.PostAsJsonAsync("/api/v1/centro/bloques", new { jornada = "matutina", inicio = "07:30:00", fin = "08:00:00", esReceso = false }))
            .StatusCode.Should().Be(HttpStatusCode.Conflict, "se cruza con otro bloque");

        (await c.PutAsJsonAsync($"/api/v1/centro/secciones/{e.A}/horario", Horario((1, e.B1, e.Espanol, null), (1, e.B2, e.Mate, null))))
            .StatusCode.Should().Be(HttpStatusCode.OK);
        (await c.PutAsJsonAsync($"/api/v1/centro/secciones/{e.A}/horario", Horario((1, e.Receso, e.Mate, null))))
            .StatusCode.Should().Be(HttpStatusCode.BadRequest, "en receso no hay clase");

        var docenteDoble = await c.PutAsJsonAsync($"/api/v1/centro/secciones/{e.B}/horario", Horario((1, e.B1, e.Espanol, null)));
        docenteDoble.StatusCode.Should().Be(HttpStatusCode.Conflict);
        (await docenteDoble.Content.ReadAsStringAsync()).Should().Contain("Profe Español").And.Contain("a la vez");

        var aulaDoble = await c.PutAsJsonAsync($"/api/v1/centro/secciones/{e.B}/horario", Horario((1, e.B1, e.Mate, e.Aula1)));
        aulaDoble.StatusCode.Should().Be(HttpStatusCode.Conflict);
        (await aulaDoble.Content.ReadAsStringAsync()).Should().Contain("Aula 1");

        (await c.PutAsJsonAsync($"/api/v1/centro/secciones/{e.B}/horario", Horario((1, e.B2, e.Espanol, null))))
            .StatusCode.Should().Be(HttpStatusCode.OK);
        // Otra jornada, misma aula, otras horas: no choca.
        (await c.PutAsJsonAsync($"/api/v1/centro/secciones/{e.C}/horario", Horario((1, e.V1, e.Mate, null))))
            .StatusCode.Should().Be(HttpStatusCode.OK);

        var deA = await ReadAsync(await c.GetAsync($"/api/v1/centro/secciones/{e.A}/horario"));
        deA.GetProperty("celdas").EnumerateArray().Single(x => x.GetProperty("asignaturaId").GetGuid() == e.Espanol)
            .GetProperty("docenteId").GetGuid().Should().Be(e.DocenteId);

        // Si la carga cambia después, el choque se reporta (no se reescribe el horario).
        (await c.PutAsJsonAsync($"/api/v1/centro/secciones/{e.A}/carga",
            new { asignaciones = new[] { new { asignaturaId = e.Espanol, docenteId = e.DocenteId }, new { asignaturaId = e.Mate, docenteId = e.DocenteId } } }))
            .IsSuccessStatusCode.Should().BeTrue();
        (await ReadAsync(await c.GetAsync("/api/v1/centro/horario/choques"))).GetArrayLength().Should().Be(1);

        var delDocente = (await ReadAsync(await c.GetAsync($"/api/v1/centro/docentes/{e.DocenteId}/horario"))).EnumerateArray().ToList();
        delDocente.Select(x => x.GetProperty("inicio").GetString()).Should().Equal("07:00:00", "07:45:00", "07:45:00");

        var carga = await ReadAsync(await e.Docente.GetAsync("/api/v1/mi-centro/carga"));
        carga.GetProperty("horario").GetArrayLength().Should().Be(3);
        carga.GetProperty("horario")[0].GetProperty("aula").GetString().Should().Be("Aula 1");
    }

    [Fact]
    public async Task El_maestro_guia_pasa_la_lista_del_dia_y_la_ven_el_centro_y_la_familia()
    {
        var e = await EscenarioAsync();
        var c = e.Centro;
        var ana = (await ReadAsync(await c.PostAsJsonAsync($"/api/v1/centro/secciones/{e.A}/alumnos",
            new { identidad = "0801201400101", nombre = "Ana Lista", tipo = "nuevo_ingreso" }))).GetProperty("alumnoId").GetGuid();
        await c.PostAsJsonAsync($"/api/v1/centro/secciones/{e.A}/alumnos", new { identidad = "0801201400102", nombre = "Beto Lista", tipo = "nuevo_ingreso" });
        var hoy = DateTime.Today.ToString("yyyy-MM-dd");

        var vacia = await ReadAsync(await e.Docente.GetAsync($"/api/v1/mi-centro/secciones/{e.A}/asistencia?fecha={hoy}"));
        vacia.GetProperty("tomada").GetBoolean().Should().BeFalse();
        vacia.GetProperty("alumnos").GetArrayLength().Should().Be(2);

        var tomada = await ReadAsync(await e.Docente.PutAsJsonAsync($"/api/v1/mi-centro/secciones/{e.A}/asistencia",
            new { fecha = hoy, marcas = new[] { new { alumnoId = ana, estado = "A" } } }));
        tomada.GetProperty("tomada").GetBoolean().Should().BeTrue();
        tomada.GetProperty("alumnos").EnumerateArray().Single(x => x.GetProperty("alumnoId").GetGuid() == ana)
            .GetProperty("estado").GetString().Should().Be("A");

        (await e.Docente.PutAsJsonAsync($"/api/v1/mi-centro/secciones/{e.A}/asistencia",
            new { fecha = DateTime.Today.AddDays(1).ToString("yyyy-MM-dd"), marcas = Array.Empty<object>() }))
            .StatusCode.Should().Be(HttpStatusCode.BadRequest, "no se pasa lista del futuro");
        (await e.Docente.GetAsync($"/api/v1/mi-centro/secciones/{e.B}/asistencia"))
            .StatusCode.Should().Be(HttpStatusCode.NotFound, "no es guía de la B");

        var delDia = await ReadAsync(await c.GetAsync($"/api/v1/centro/asistencia-diaria?fecha={hoy}"));
        var seccionA = delDia.GetProperty("secciones").EnumerateArray().Single(s => s.GetProperty("seccionId").GetGuid() == e.A);
        seccionA.GetProperty("tomada").GetBoolean().Should().BeTrue();
        seccionA.GetProperty("guia").GetString().Should().Be("Profe Español");
        seccionA.GetProperty("faltas")[0].GetProperty("nombre").GetString().Should().Be("Ana Lista");

        await c.PutAsJsonAsync($"/api/v1/centro/secciones/{e.A}/horario", Horario((1, e.B1, e.Espanol, null)));
        var codigo = (await ReadAsync(await c.PostAsync($"/api/v1/centro/alumnos/{ana}/familia/codigo", null))).GetProperty("codigo").GetString();
        var padre = Fixture.CreateClient();
        Autorizar(padre, await ReadAsync(await padre.PostAsJsonAsync("/api/v1/auth/registro-padre", new
        {
            codigo, email = $"padre-{Guid.NewGuid():N}@prueba.hn", password = "Familia-1234", fullName = "Papá Lista",
        })));
        var resumen = await ReadAsync(await padre.GetAsync($"/api/v1/padres/hijos/{ana}"));
        var diaria = resumen.GetProperty("asistenciaDiaria");
        diaria.GetProperty("sesiones").GetInt32().Should().Be(1);
        diaria.GetProperty("ausencias").GetInt32().Should().Be(1);
        resumen.GetProperty("horario")[0].GetProperty("asignatura").GetString().Should().Be("Español");
    }

    [Fact]
    public async Task La_excusa_del_centro_la_ve_quien_pasa_lista_como_justificada()
    {
        var e = await EscenarioAsync();
        var c = e.Centro;
        var ana = (await ReadAsync(await c.PostAsJsonAsync($"/api/v1/centro/secciones/{e.A}/alumnos",
            new { identidad = "0801201400201", nombre = "Ana Excusa", tipo = "nuevo_ingreso" }))).GetProperty("alumnoId").GetGuid();
        await c.PostAsJsonAsync($"/api/v1/centro/secciones/{e.A}/alumnos", new { identidad = "0801201400202", nombre = "Beto Excusa", tipo = "nuevo_ingreso" });
        var hoy = DateTime.Today;

        (await c.PostAsJsonAsync("/api/v1/centro/excusas", new
        {
            alumnoId = ana, tipo = "excusa", desde = hoy.ToString("yyyy-MM-dd"), hasta = hoy.AddDays(-1).ToString("yyyy-MM-dd"), motivo = "Gripe",
        })).StatusCode.Should().Be(HttpStatusCode.BadRequest, "termina antes de empezar");
        var excusa = await ReadAsync(await c.PostAsJsonAsync("/api/v1/centro/excusas", new
        {
            alumnoId = ana, tipo = "excusa", desde = hoy.AddDays(-1).ToString("yyyy-MM-dd"), hasta = hoy.AddDays(1).ToString("yyyy-MM-dd"), motivo = "Gripe",
        }));
        excusa.GetProperty("seccion").GetString().Should().Be("7.º grado A");

        var delDocente = await ReadAsync(await e.Docente.GetAsync($"/api/v1/mi-centro/excusas?fecha={hoy:yyyy-MM-dd}"));
        delDocente.GetArrayLength().Should().Be(1);
        delDocente[0].GetProperty("identidad").GetString().Should().Be("0801201400201");
        (await ReadAsync(await e.Docente.GetAsync($"/api/v1/mi-centro/excusas?fecha={hoy.AddDays(5):yyyy-MM-dd}"))).GetArrayLength().Should().Be(0);

        var lista = await ReadAsync(await e.Docente.GetAsync($"/api/v1/mi-centro/secciones/{e.A}/asistencia?fecha={hoy:yyyy-MM-dd}"));
        var deAna = lista.GetProperty("alumnos").EnumerateArray().Single(x => x.GetProperty("alumnoId").GetGuid() == ana);
        deAna.GetProperty("estado").GetString().Should().Be("J");
        deAna.GetProperty("excusa").GetString().Should().Be("Excusa: Gripe");

        (await ReadAsync(await c.GetAsync("/api/v1/centro/excusas"))).GetArrayLength().Should().Be(1);
        (await c.DeleteAsync($"/api/v1/centro/excusas/{excusa.GetProperty("id").GetGuid()}")).StatusCode.Should().Be(HttpStatusCode.NoContent);
        (await ReadAsync(await e.Docente.GetAsync($"/api/v1/mi-centro/excusas?fecha={hoy:yyyy-MM-dd}"))).GetArrayLength().Should().Be(0);
    }

    [Fact]
    public async Task El_maestro_guia_pone_la_conducta_por_parcial_y_sale_en_el_consolidado()
    {
        var e = await EscenarioAsync();
        var ana = (await ReadAsync(await e.Centro.PostAsJsonAsync($"/api/v1/centro/secciones/{e.A}/alumnos",
            new { identidad = "0801201400201", nombre = "Ana Conducta", tipo = "nuevo_ingreso" }))).GetProperty("alumnoId").GetGuid();

        var vacia = await ReadAsync(await e.Docente.GetAsync($"/api/v1/mi-centro/secciones/{e.A}/conducta?parcial=2"));
        vacia.GetProperty("alumnos")[0].GetProperty("nota").ValueKind.Should().Be(JsonValueKind.Null);

        (await e.Docente.PutAsJsonAsync($"/api/v1/mi-centro/secciones/{e.A}/conducta",
            new { parcial = 2, notas = new[] { new { alumnoId = ana, nota = (string?)"F" } } }))
            .StatusCode.Should().Be(HttpStatusCode.BadRequest);
        (await e.Docente.PutAsJsonAsync($"/api/v1/mi-centro/secciones/{e.B}/conducta",
            new { parcial = 2, notas = new[] { new { alumnoId = ana, nota = (string?)"A" } } }))
            .StatusCode.Should().Be(HttpStatusCode.NotFound, "no es guía de la B");

        var puesta = await ReadAsync(await e.Docente.PutAsJsonAsync($"/api/v1/mi-centro/secciones/{e.A}/conducta",
            new { parcial = 2, notas = new[] { new { alumnoId = ana, nota = (string?)"B" } } }));
        puesta.GetProperty("alumnos")[0].GetProperty("nota").GetString().Should().Be("B");

        var consolidado = await ReadAsync(await e.Centro.GetAsync($"/api/v1/centro/secciones/{e.A}/consolidado"));
        consolidado.GetProperty("alumnos")[0].GetProperty("conducta").EnumerateArray()
            .Select(x => x.ValueKind == JsonValueKind.Null ? null : x.GetString()).Should().Equal(null, "B", null, null);

        // Nota null la borra.
        await e.Docente.PutAsJsonAsync($"/api/v1/mi-centro/secciones/{e.A}/conducta",
            new { parcial = 2, notas = new[] { new { alumnoId = ana, nota = (string?)null } } });
        (await ReadAsync(await e.Docente.GetAsync($"/api/v1/mi-centro/secciones/{e.A}/conducta?parcial=2")))
            .GetProperty("alumnos")[0].GetProperty("nota").ValueKind.Should().Be(JsonValueKind.Null);
    }

    [Fact]
    public async Task El_catedratico_registra_una_incidencia_el_centro_le_da_seguimiento_y_la_familia_la_ve()
    {
        var e = await EscenarioAsync();
        var c = e.Centro;
        var ana = (await ReadAsync(await c.PostAsJsonAsync($"/api/v1/centro/secciones/{e.A}/alumnos",
            new { identidad = "0801201400401", nombre = "Ana Incidencia", tipo = "nuevo_ingreso" }))).GetProperty("alumnoId").GetGuid();
        var codigo = (await ReadAsync(await c.PostAsync($"/api/v1/centro/alumnos/{ana}/familia/codigo", null))).GetProperty("codigo").GetString();
        var padre = Fixture.CreateClient();
        Autorizar(padre, await ReadAsync(await padre.PostAsJsonAsync("/api/v1/auth/registro-padre", new
        {
            codigo, email = $"padre-{Guid.NewGuid():N}@prueba.hn", password = "Familia-1234", fullName = "Papá Incidencia",
        })));
        var token = $"token-{Guid.NewGuid():N}";
        await padre.PostAsJsonAsync("/api/v1/dispositivos", new { token, plataforma = "android" });
        var hoy = DateTime.Today.ToString("yyyy-MM-dd");

        object Incidencia(Guid seccion, string identidad, string gravedad = "grave") =>
            new { seccionId = seccion, identidad, fecha = hoy, gravedad, descripcion = "Pelea en el recreo", medida = "Citación a la familia" };
        (await e.Docente.PostAsJsonAsync("/api/v1/mi-centro/incidencias", Incidencia(e.C, "0801201400401")))
            .StatusCode.Should().Be(HttpStatusCode.NotFound, "no da clase en la C");
        (await e.Docente.PostAsJsonAsync("/api/v1/mi-centro/incidencias", Incidencia(e.A, "0801201400401", "media")))
            .StatusCode.Should().Be(HttpStatusCode.BadRequest);
        var creada = await ReadAsync(await e.Docente.PostAsJsonAsync("/api/v1/mi-centro/incidencias", Incidencia(e.A, "0801-2014-00401")));
        creada.GetProperty("seccion").GetString().Should().Be("7.º grado A");
        creada.GetProperty("registradaPor").GetString().Should().Be("Profe Español");
        (await AvisosDeAsync(token, 1)).Should().ContainSingle().Which.Should().Be("Incidencia de Ana Incidencia: falta grave");

        var id = creada.GetProperty("id").GetGuid();
        (await c.PutAsJsonAsync($"/api/v1/centro/incidencias/{id}", new { medida = "Suspensión de un día", seguimiento = "Firmó acta", cerrada = true }))
            .StatusCode.Should().Be(HttpStatusCode.OK);
        (await ReadAsync(await c.GetAsync("/api/v1/centro/incidencias?abiertas=true"))).GetArrayLength().Should().Be(0);
        (await ReadAsync(await c.GetAsync($"/api/v1/centro/incidencias?alumnoId={ana}")))[0].GetProperty("cerrada").GetBoolean().Should().BeTrue();

        var delDocente = await ReadAsync(await e.Docente.GetAsync("/api/v1/mi-centro/incidencias"));
        delDocente[0].GetProperty("seguimiento").ValueKind.Should().Be(JsonValueKind.Null, "el seguimiento es del centro");

        var familia = (await ReadAsync(await padre.GetAsync($"/api/v1/padres/hijos/{ana}"))).GetProperty("incidencias");
        familia.GetArrayLength().Should().Be(1);
        familia[0].GetProperty("medida").GetString().Should().Be("Suspensión de un día");
        familia[0].TryGetProperty("seguimiento", out _).Should().BeFalse();

        (await c.DeleteAsync($"/api/v1/centro/incidencias/{id}")).StatusCode.Should().Be(HttpStatusCode.NoContent);
    }

    [Fact]
    public async Task El_carnet_lleva_la_foto_del_alumno_y_el_logo_y_color_del_centro()
    {
        var e = await EscenarioAsync();
        var c = e.Centro;
        var ana = (await ReadAsync(await c.PostAsJsonAsync($"/api/v1/centro/secciones/{e.A}/alumnos",
            new { identidad = "0801201400501", nombre = "Ana Carnet", tipo = "nuevo_ingreso" }))).GetProperty("alumnoId").GetGuid();
        await c.PostAsJsonAsync($"/api/v1/centro/secciones/{e.A}/alumnos", new { identidad = "0801201400502", nombre = "Beto Carnet", tipo = "nuevo_ingreso" });

        byte[] jpg = [0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4, 5, 6, 0xFF, 0xD9];
        byte[] png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 9, 9];
        (await c.PutAsJsonAsync($"/api/v1/centro/alumnos/{ana}/foto", new { base64 = Convert.ToBase64String(png) }))
            .StatusCode.Should().Be(HttpStatusCode.BadRequest, "la foto va en JPG");
        (await c.PutAsJsonAsync($"/api/v1/centro/alumnos/{ana}/foto", new { base64 = Convert.ToBase64String(jpg) }))
            .StatusCode.Should().Be(HttpStatusCode.NoContent);
        (await (await c.GetAsync($"/api/v1/centro/alumnos/{ana}/foto")).Content.ReadAsByteArrayAsync()).Should().Equal(jpg);

        (await c.PutAsJsonAsync("/api/v1/centro/marca", new { color = "rojo", lema = "Ciencia" })).StatusCode.Should().Be(HttpStatusCode.BadRequest);
        (await c.PutAsJsonAsync("/api/v1/centro/marca", new { color = "#aa0000", lema = "Ciencia y virtud" })).StatusCode.Should().Be(HttpStatusCode.OK);
        (await ReadAsync(await c.PutAsJsonAsync("/api/v1/centro/marca/logo", new { base64 = Convert.ToBase64String(png) })))
            .GetProperty("tieneLogo").GetBoolean().Should().BeTrue();

        var carnets = await ReadAsync(await c.GetAsync($"/api/v1/centro/secciones/{e.A}/carnets"));
        carnets.GetProperty("color").GetString().Should().Be("#AA0000");
        carnets.GetProperty("lema").GetString().Should().Be("Ciencia y virtud");
        carnets.GetProperty("logo").GetString().Should().Be(Convert.ToBase64String(png));
        var alumnos = carnets.GetProperty("alumnos");
        alumnos.GetArrayLength().Should().Be(2);
        alumnos[0].GetProperty("foto").GetString().Should().Be(Convert.ToBase64String(jpg));
        alumnos[1].GetProperty("foto").ValueKind.Should().Be(JsonValueKind.Null);
        alumnos[0].GetProperty("seccion").GetString().Should().Be("7.º grado A");

        var uno = await ReadAsync(await c.GetAsync($"/api/v1/centro/alumnos/{ana}/carnet"));
        uno.GetProperty("alumnos").GetArrayLength().Should().Be(1);
        (await e.Docente.GetAsync($"/api/v1/centro/alumnos/{ana}/foto")).StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    private static async Task<List<string>> AvisosDeAsync(string token, int esperados)
    {
        for (var i = 0; i < 50; i++)
        {
            var de = EnviadorDePrueba.Enviados.Where(e => e.Token == token).Select(e => e.Titulo).ToList();
            if (de.Count >= esperados) return de;
            await Task.Delay(100);
        }
        return EnviadorDePrueba.Enviados.Where(e => e.Token == token).Select(e => e.Titulo).ToList();
    }

    [Fact]
    public async Task La_familia_recibe_en_el_telefono_los_comunicados_y_las_faltas_del_dia()
    {
        var e = await EscenarioAsync();
        var ana = (await ReadAsync(await e.Centro.PostAsJsonAsync($"/api/v1/centro/secciones/{e.A}/alumnos",
            new { identidad = "0801201400301", nombre = "Ana Aviso", tipo = "nuevo_ingreso" }))).GetProperty("alumnoId").GetGuid();
        var codigo = (await ReadAsync(await e.Centro.PostAsync($"/api/v1/centro/alumnos/{ana}/familia/codigo", null))).GetProperty("codigo").GetString();
        var padre = Fixture.CreateClient();
        Autorizar(padre, await ReadAsync(await padre.PostAsJsonAsync("/api/v1/auth/registro-padre", new
        {
            codigo, email = $"padre-{Guid.NewGuid():N}@prueba.hn", password = "Familia-1234", fullName = "Papá Aviso",
        })));
        var token = $"token-{Guid.NewGuid():N}";
        var muerto = $"muerto-{Guid.NewGuid():N}";
        (await padre.PostAsJsonAsync("/api/v1/dispositivos", new { token, plataforma = "android" })).StatusCode.Should().Be(HttpStatusCode.NoContent);
        (await padre.PostAsJsonAsync("/api/v1/dispositivos", new { token = muerto, plataforma = "ios" })).StatusCode.Should().Be(HttpStatusCode.NoContent);

        await e.Centro.PostAsJsonAsync("/api/v1/centro/comunicados", new { titulo = "Reunión", cuerpo = "El viernes.", seccionIds = (Guid[]?)null });
        await e.Centro.PostAsJsonAsync("/api/v1/centro/comunicados", new { titulo = "Solo la B", cuerpo = "Gira.", seccionIds = new[] { e.B } });
        (await AvisosDeAsync(token, 1)).Should().ContainSingle().Which.Should().EndWith("Reunión");

        var hoy = DateTime.Today.ToString("yyyy-MM-dd");
        var lista = new { fecha = hoy, marcas = new[] { new { alumnoId = ana, estado = "A" } } };
        await e.Docente.PutAsJsonAsync($"/api/v1/mi-centro/secciones/{e.A}/asistencia", lista);
        await e.Docente.PutAsJsonAsync($"/api/v1/mi-centro/secciones/{e.A}/asistencia", lista);
        var avisos = await AvisosDeAsync(token, 2);
        await Task.Delay(500);
        avisos = EnviadorDePrueba.Enviados.Where(x => x.Token == token).Select(x => x.Titulo).ToList();
        avisos.Should().HaveCount(2, "corregir la lista no repite el aviso");
        avisos[1].Should().Be("Ana Aviso no llegó hoy a clases");

        // El token que Firebase rechazó se olvida: el siguiente aviso ya no va a él.
        var antes = EnviadorDePrueba.Enviados.Count(x => x.Token == muerto);
        await e.Centro.PostAsJsonAsync("/api/v1/centro/comunicados", new { titulo = "Otro", cuerpo = "Más.", seccionIds = (Guid[]?)null });
        await AvisosDeAsync(token, 3);
        EnviadorDePrueba.Enviados.Count(x => x.Token == muerto).Should().Be(antes);
    }
}
