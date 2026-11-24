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
        return await EntrarConTemporalAsync(admin.GetProperty("email").GetString()!, admin.GetProperty("claveTemporal").GetString()!);
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

        var conTemporal = Fixture.CreateClient();
        conTemporal.DefaultRequestHeaders.Authorization = new("Bearer", login.GetProperty("tokens").GetProperty("accessToken").GetString());
        var antes = await conTemporal.GetAsync("/api/v1/sync/pull");
        (await conTemporal.PostAsJsonAsync("/api/v1/auth/change-password",
            new { currentPassword = docente.GetProperty("claveTemporal").GetString(), newPassword = ClaveNueva })).IsSuccessStatusCode.Should().BeTrue();
        var despues = await conTemporal.GetAsync("/api/v1/sync/pull");

        // El servidor, no sólo la app, exige cambiar la temporal; con el mismo token ya sirve.
        antes.StatusCode.Should().Be(HttpStatusCode.Forbidden);
        (await antes.Content.ReadAsStringAsync()).Should().Contain("debe_cambiar_clave");
        despues.IsSuccessStatusCode.Should().BeTrue();
        login.GetProperty("user").GetProperty("mustChangePassword").GetBoolean().Should().BeTrue();
        login.GetProperty("user").GetProperty("role").GetString().Should().Be("Docente");
        panel.GetProperty("institucion").GetProperty("docentes").GetInt32().Should().Be(1);
        panel.GetProperty("docentes")[0].GetProperty("nombre").GetString().Should().Be("Profe Uno");
    }

    [Fact]
    public async Task El_centro_ve_cuando_trabajo_cada_docente_y_los_equipos_y_observaciones_se_respaldan()
    {
        var centro = await CentroAsync();
        async Task<JsonElement> Alta(string nombre) =>
            await ReadAsync(await centro.PostAsJsonAsync("/api/v1/centro/docentes", new { email = $"p-{Guid.NewGuid():N}@prueba.hn", nombre }));
        var activo = await Alta("Activa");
        await Alta("Sin trabajo");
        var cliente = await EntrarConTemporalAsync(activo.GetProperty("email").GetString()!, activo.GetProperty("claveTemporal").GetString()!);

        var push = await cliente.PostAsJsonAsync("/api/v1/sync/push", new
        {
            clases = Array.Empty<object>(),
            registros = new[]
            {
                new { tipo = "equipo", claseClave = "c1", clave = "e1", datos = "{\"nombre\":\"Equipo 1\",\"miembros\":[\"a1\"]}", eliminado = false, actualizadoEn = DateTimeOffset.UtcNow },
                new { tipo = "observacion", claseClave = "c1", clave = "o1", datos = "{\"alumnoClave\":\"a1\",\"texto\":\"Participa\"}", eliminado = false, actualizadoEn = DateTimeOffset.UtcNow },
            },
        });
        var pull = await ReadAsync(await cliente.GetAsync("/api/v1/sync/pull"));
        var panel = await ReadAsync(await centro.GetAsync("/api/v1/centro"));

        push.IsSuccessStatusCode.Should().BeTrue();
        pull.GetProperty("registros").EnumerateArray().Select(r => r.GetProperty("tipo").GetString())
            .Should().Contain(["equipo", "observacion"]);
        var docentes = panel.GetProperty("docentes").EnumerateArray().ToDictionary(d => d.GetProperty("nombre").GetString()!);
        docentes["Activa"].GetProperty("ultimoTrabajo").ValueKind.Should().Be(JsonValueKind.String);
        docentes["Sin trabajo"].GetProperty("ultimoTrabajo").ValueKind.Should().Be(JsonValueKind.Null);
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
        var centro = await EntrarConTemporalAsync(admin.GetProperty("email").GetString()!, admin.GetProperty("claveTemporal").GetString()!);
        var docente = await ReadAsync(await centro.PostAsJsonAsync("/api/v1/centro/docentes", new { email = $"d-{Guid.NewGuid():N}@prueba.hn", nombre = "D" }));
        var email = docente.GetProperty("email").GetString()!;
        // El docente ya cambió su temporal: las pruebas entran con la nueva.
        await EntrarConTemporalAsync(email, docente.GetProperty("claveTemporal").GetString()!);
        return (plataforma, creado.GetProperty("institucion").GetProperty("id").GetGuid(), email, ClaveNueva);
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
    public async Task Desactivar_o_suspender_corta_al_instante_la_sesion_ya_abierta()
    {
        var (plataforma, centroId, email, clave) = await CentroConDocenteAsync();
        var docente = await LoginAsync(email, clave);
        var otro = await CentroConDocenteAsync();
        var docenteOtro = await LoginAsync(otro.Email, otro.Clave);
        (await docente.GetAsync("/api/v1/auth/me")).IsSuccessStatusCode.Should().BeTrue();
        (await docenteOtro.GetAsync("/api/v1/auth/me")).IsSuccessStatusCode.Should().BeTrue();

        // El mismo access token, que aún no vence: tras suspender el centro ya no sirve.
        (await plataforma.PostAsync($"/api/v1/plataforma/instituciones/{centroId}/suspender", null)).IsSuccessStatusCode.Should().BeTrue();
        var centroAdmin = await CentroAsync();
        var nuevo = await ReadAsync(await centroAdmin.PostAsJsonAsync("/api/v1/centro/docentes", new { email = $"x-{Guid.NewGuid():N}@prueba.hn", nombre = "X" }));
        var desactivado = await LoginAsync(nuevo.GetProperty("email").GetString()!, nuevo.GetProperty("claveTemporal").GetString()!);
        (await centroAdmin.PostAsync($"/api/v1/centro/docentes/{nuevo.GetProperty("usuarioId").GetGuid()}/desactivar", null))
            .StatusCode.Should().Be(HttpStatusCode.NoContent);

        (await docente.GetAsync("/api/v1/auth/me")).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        (await desactivado.GetAsync("/api/v1/auth/me")).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        (await docenteOtro.GetAsync("/api/v1/auth/me")).IsSuccessStatusCode.Should().BeTrue();
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
        var docente = await EntrarConTemporalAsync(correo, cuenta.GetProperty("claveTemporal").GetString()!);
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
        var docente = await EntrarConTemporalAsync(correo, cuenta.GetProperty("claveTemporal").GetString()!);

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

    [Fact]
    public async Task El_asistente_con_IA_es_del_plan_Pro_no_recibe_nombres_y_tiene_tope()
    {
        var plataforma = await PlataformaAsync();
        var correo = $"profe-ia-{Guid.NewGuid():N}@prueba.hn";
        var cuenta = await ReadAsync(await plataforma.PostAsJsonAsync("/api/v1/plataforma/docentes", new { email = correo, nombre = "Profe IA" }));
        var id = cuenta.GetProperty("usuarioId").GetGuid();
        (await plataforma.PutAsJsonAsync($"/api/v1/plataforma/docentes/{id}/plan", Plan(Hoy.AddMonths(1)))).IsSuccessStatusCode.Should().BeTrue();
        var docente = await EntrarConTemporalAsync(correo, cuenta.GetProperty("claveTemporal").GetString()!);

        var plan = new
        {
            asignatura = "Matemáticas", grado = "7.º grado", parcial = "Parcial I", temas = "Fracciones", semanas = 4, total = 100m,
            rubros = new[] { new { nombre = "tareas", puntos = 30m }, new { nombre = "Examen", puntos = 70m } },
        };
        (await ReadAsync(await docente.GetAsync("/api/v1/ia/estado"))).GetProperty("habilitada").GetBoolean().Should().BeFalse();
        (await docente.PostAsJsonAsync("/api/v1/ia/plan", plan)).StatusCode.Should().Be(HttpStatusCode.Forbidden, "no tiene el plan Pro");

        var pro = new { planNombre = "Docente Pro", monto = 100m, pagadoHasta = Hoy.AddMonths(1), diasGracia = 0, comoPagar = (string?)null, conIa = true };
        (await ReadAsync(await plataforma.PutAsJsonAsync($"/api/v1/plataforma/docentes/{id}/plan", pro))).GetProperty("conIa").GetBoolean().Should().BeTrue();

        // Respeta los rubros del docente (nombre y puntos) y descarta los que la IA inventó.
        var sugerido = await ReadAsync(await docente.PostAsJsonAsync("/api/v1/ia/plan", plan));
        var rubros = sugerido.GetProperty("rubros");
        rubros.EnumerateArray().Select(r => r.GetProperty("nombre").GetString()).Should().Equal("tareas", "Examen");
        rubros[0].GetProperty("actividades")[0].GetProperty("semana").GetInt32().Should().Be(4, "la semana no pasa de la duración");

        var examen = await ReadAsync(await docente.PostAsJsonAsync("/api/v1/ia/examen", new
        {
            asignatura = "Matemáticas", grado = "7.º grado", temas = "Fracciones", preguntas = 10, puntos = 10m,
            tipos = new[] { "opcion_multiple", "verdadero_falso" },
        }));
        examen.GetProperty("preguntas")[1].GetProperty("opciones").GetArrayLength().Should().Be(0, "verdadero o falso no lleva opciones");

        var comentario = await ReadAsync(await docente.PostAsJsonAsync("/api/v1/ia/comentario", new
        {
            asignatura = "Matemáticas", grado = "7.º grado", parcial = "Parcial I", nota = 64m, ausencias = 2, tardes = 1,
            rubros = new[] { new { nombre = "Examen", obtenido = 40m, posible = 70m } }, enfoque = (string?)null,
        }));
        comentario.GetProperty("texto").GetString().Should().StartWith("El estudiante");
        GeneradorDePrueba.Peticiones.Last().Usuario.Should().Contain("64").And.NotContain("Profe IA");

        byte[] jpg = [0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 0xFF, 0xD9];
        var calificada = await ReadAsync(await docente.PostAsJsonAsync("/api/v1/ia/calificar", new
        {
            asignatura = "Matemáticas", grado = "7.º grado", actividad = "Tarea 1", descripcion = "Fracciones", puntos = 10m,
            criterios = "1/2 + 1/4 = 3/4", imagenes = new[] { Convert.ToBase64String(jpg) },
        }));
        calificada.GetProperty("nota").GetDecimal().Should().Be(7.5m, "se redondea a medios puntos");
        GeneradorDePrueba.Peticiones.Last().Imagenes.Should().ContainSingle();
        (await docente.PostAsJsonAsync("/api/v1/ia/calificar", new { actividad = "Tarea 1", puntos = 10m, imagenes = new[] { "AAAA" } }))
            .StatusCode.Should().Be(HttpStatusCode.BadRequest, "no es una foto JPG");

        var estado = await ReadAsync(await docente.GetAsync("/api/v1/ia/estado"));
        estado.GetProperty("creditos").GetDecimal().Should().Be(9.5m, "plan 3 + examen 4 + comentario ½ + foto de una página 2");
        (await docente.PostAsJsonAsync("/api/v1/ia/examen", new { asignatura = "Mate", temas = "x", preguntas = 2, puntos = 10m, tipos = new[] { "desarrollo" } }))
            .StatusCode.Should().Be(HttpStatusCode.BadRequest, "mínimo 3 preguntas");

        estado.GetProperty("limiteCreditos").GetInt32().Should().Be(140);
        (await plataforma.PutAsJsonAsync($"/api/v1/plataforma/docentes/{id}/plan", new
            {
                pro.planNombre, pro.monto, pro.pagadoHasta, pro.diasGracia, pro.comoPagar, pro.conIa, iaMultiplicador = 9,
            }))
            .StatusCode.Should().Be(HttpStatusCode.BadRequest, "de x1 a x5");
        (await ReadAsync(await plataforma.PutAsJsonAsync($"/api/v1/plataforma/docentes/{id}/plan", new
            {
                pro.planNombre, pro.monto, pro.pagadoHasta, pro.diasGracia, pro.comoPagar, pro.conIa, iaMultiplicador = 2,
            }))).GetProperty("iaMultiplicador").GetInt32().Should().Be(2);
        var doble = await ReadAsync(await docente.GetAsync("/api/v1/ia/estado"));
        doble.GetProperty("limiteCreditos").GetInt32().Should().Be(280);

        var costos = await ReadAsync(await plataforma.GetAsync("/api/v1/plataforma/ia/costos"));
        costos.GetProperty("usos").GetInt32().Should().BeGreaterThanOrEqualTo(4);
        costos.GetProperty("porFuncion").EnumerateArray().Select(f => f.GetProperty("funcion").GetString()).Should().Contain("calificar");
        costos.GetProperty("porCuenta").GetArrayLength().Should().BeGreaterThan(0);
        (await docente.GetAsync("/api/v1/plataforma/ia/costos")).StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task El_portafolio_con_IA_redacta_la_presentacion_y_la_nivelacion_sin_nombres()
    {
        var plataforma = await PlataformaAsync();
        var correo = $"profe-portafolio-{Guid.NewGuid():N}@prueba.hn";
        var cuenta = await ReadAsync(await plataforma.PostAsJsonAsync("/api/v1/plataforma/docentes", new { email = correo, nombre = "Profe Portafolio" }));
        var id = cuenta.GetProperty("usuarioId").GetGuid();
        (await plataforma.PutAsJsonAsync($"/api/v1/plataforma/docentes/{id}/plan", new
        {
            planNombre = "Docente Pro", monto = 100m, pagadoHasta = Hoy.AddMonths(1), diasGracia = 0, comoPagar = (string?)null, conIa = true,
        })).IsSuccessStatusCode.Should().BeTrue();
        var docente = await EntrarConTemporalAsync(correo, cuenta.GetProperty("claveTemporal").GetString()!);

        var presentacion = await ReadAsync(await docente.PostAsJsonAsync("/api/v1/ia/portafolio/presentacion",
            new { nivel = "Educación Media", asignaturas = new[] { "Matemática, décimo grado" }, indicaciones = (string?)null }));
        presentacion.GetProperty("introduccion").GetString().Should().NotBeEmpty();
        presentacion.GetProperty("objetivos").GetArrayLength().Should().Be(2);

        var nivelacion = await ReadAsync(await docente.PostAsJsonAsync("/api/v1/ia/portafolio/nivelacion", new
        {
            asignatura = "Matemática", grado = "Décimo grado",
            alumnos = new[] { new { codigo = "A1", parciales = new[] { "PARCIAL I: 62" }, rubros = new[] { new { nombre = "Examen", obtenido = 20m, posible = 50m } }, ausencias = 3 } },
        }));
        nivelacion.GetProperty("acciones").GetArrayLength().Should().Be(1, "solo los códigos que se mandaron");
        GeneradorDePrueba.Peticiones.Last().Usuario.Should().Contain("A1").And.Contain("Examen 20 de 50");

        var estado = await ReadAsync(await docente.GetAsync("/api/v1/ia/estado"));
        estado.GetProperty("creditos").GetDecimal().Should().Be(2.5m, "presentación 1 + nivelación 1½");
    }

    [Fact]
    public async Task Calificar_en_tanda_cuesta_un_credito_por_trabajo_y_deja_las_sugerencias()
    {
        var plataforma = await PlataformaAsync();
        var correo = $"profe-tanda-{Guid.NewGuid():N}@prueba.hn";
        var cuenta = await ReadAsync(await plataforma.PostAsJsonAsync("/api/v1/plataforma/docentes", new { email = correo, nombre = "Profe Tanda" }));
        var id = cuenta.GetProperty("usuarioId").GetGuid();
        (await plataforma.PutAsJsonAsync($"/api/v1/plataforma/docentes/{id}/plan", new
        {
            planNombre = "Docente Pro", monto = 100m, pagadoHasta = Hoy.AddMonths(1), diasGracia = 0, comoPagar = (string?)null, conIa = true,
        })).IsSuccessStatusCode.Should().BeTrue();
        var docente = await EntrarConTemporalAsync(correo, cuenta.GetProperty("claveTemporal").GetString()!);

        var foto = Convert.ToBase64String(new byte[] { 0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 0xFF, 0xD9 });
        var actividad = Guid.NewGuid().ToString();
        object Tanda(params string[] alumnos) => new
        {
            actividadId = actividad, asignatura = "Matemáticas", grado = "7.º grado", actividad = "Tarea 1", puntos = 10m,
            criterios = "1/2 + 1/4 = 3/4", trabajos = alumnos.Select(a => new { alumnoId = a, imagenes = new[] { foto } }).ToArray(),
        };

        (await docente.PostAsJsonAsync("/api/v1/ia/calificar/tanda", Tanda("a", "a"))).StatusCode
            .Should().Be(HttpStatusCode.BadRequest, "un alumno dos veces");
        (await docente.PostAsJsonAsync("/api/v1/ia/calificar/tanda", Tanda(Enumerable.Range(0, 11).Select(i => $"x{i}").ToArray()))).StatusCode
            .Should().Be(HttpStatusCode.BadRequest, "hasta 10 por envío");

        var tanda = await ReadAsync(await docente.PostAsJsonAsync("/api/v1/ia/calificar/tanda", Tanda("alumno-1", "alumno-2", "falla-3")));
        tanda.GetProperty("estado").GetString().Should().Be("procesando");
        GeneradorDePrueba.Lotes.Values.SelectMany(l => l).Should().Contain(p => p.Peticion.Sistema.Contains("3/4"), "la clave va en el sistema, igual para todos");
        (await ReadAsync(await docente.GetAsync("/api/v1/ia/estado"))).GetProperty("creditos").GetDecimal()
            .Should().Be(3m, "los 3 trabajos en camino apartan un crédito cada uno");

        await new ProfeApp.Infrastructure.Ia.ServicioTandas(Fixture.Services.GetRequiredService<IServiceScopeFactory>(),
            Microsoft.Extensions.Logging.Abstractions.NullLogger<ProfeApp.Infrastructure.Ia.ServicioTandas>.Instance).RevisarAsync(default);

        var tandas = await ReadAsync(await docente.GetAsync($"/api/v1/ia/calificar/tandas?actividad={actividad}"));
        tandas.GetArrayLength().Should().Be(1);
        tandas[0].GetProperty("estado").GetString().Should().Be("lista");
        var resultados = tandas[0].GetProperty("resultados").EnumerateArray().ToDictionary(r => r.GetProperty("alumnoId").GetString()!);
        resultados["alumno-1"].GetProperty("nota").GetDecimal().Should().Be(7.5m);
        resultados["falla-3"].GetProperty("nota").ValueKind.Should().Be(JsonValueKind.Null);
        (await ReadAsync(await docente.GetAsync("/api/v1/ia/estado"))).GetProperty("creditos").GetDecimal()
            .Should().Be(2m, "solo se cobran los 2 que la IA calificó");

        var costos = await ReadAsync(await plataforma.GetAsync("/api/v1/plataforma/ia/costos"));
        costos.GetProperty("porFuncion").EnumerateArray().Select(f => f.GetProperty("funcion").GetString()).Should().Contain("calificar_tanda");
    }
}
