using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using ProfeApp.IntegrationTests.Infrastructure;

namespace ProfeApp.IntegrationTests;

public class SyncTests(ApiFixture fixture) : ApiTestBase(fixture)
{
    private static readonly DateTimeOffset Importada = new(2026, 7, 1, 12, 0, 0, TimeSpan.Zero);

    private static object Clase(
        string clave, bool conArchivo = true, bool eliminada = false, DateTimeOffset? plantilla = null,
        object[]? valores = null) => new
    {
        clave,
        codigoCentro = "050100235M02",
        centro = "INSTITUTO DE PRUEBA",
        modalidad = "BTP",
        gradoSeccion = "DÉCIMO GRADO SECCIÓN 2",
        jornada = "JORNADA MATUTINA",
        asignatura = "QUÍMICA",
        hoja = "12345678~1~1123",
        archivoNombre = "QUIMICA.xls",
        archivoBase64 = conArchivo ? Convert.ToBase64String([0xD0, 0xCF, 0x11, 0xE0]) : null,
        plantillaActualizadaEn = plantilla ?? Importada,
        eliminada,
        columnas = new[] { new { clave = "PARCIAL I|NOTA TOTAL", grupo = "PARCIAL I", nombre = "NOTA TOTAL", tipo = "nota", col = 4, orden = 0 } },
        alumnos = new[] { new { clave = "0501200900001", identidad = "0501200900001", documento = "HND", nombre = "ANA", fila = 7, orden = 0, activo = true } },
        valores = valores ?? [],
    };

    private static object Valor(int? valor, DateTimeOffset cuando) =>
        new { alumnoClave = "0501200900001", columnaClave = "PARCIAL I|NOTA TOTAL", valor, actualizadoEn = cuando };

    private static async Task PushAsync(HttpClient client, params object[] clases)
    {
        var response = await client.PostAsJsonAsync("/api/v1/sync/push", new { clases });
        response.StatusCode.Should().Be(HttpStatusCode.NoContent, await response.Content.ReadAsStringAsync());
    }

    private static async Task<JsonElement> PullAsync(HttpClient client, string? desde = null) =>
        await ReadAsync(await client.GetAsync("/api/v1/sync/pull" + (desde is null ? "" : $"?desde={Uri.EscapeDataString(desde)}")));

    private static JsonElement ClaseDe(JsonElement pull, string clave) =>
        pull.GetProperty("clases").EnumerateArray().Single(c => c.GetProperty("clave").GetString() == clave);

    [Fact]
    public async Task Lo_que_sube_un_telefono_lo_baja_otro_con_su_archivo()
    {
        var telefonoA = await RegisterAsync();
        await PushAsync(telefonoA, Clase("quimica", valores: [Valor(81, Importada.AddHours(1))]));

        var clase = ClaseDe(await PullAsync(telefonoA), "quimica");

        clase.GetProperty("archivoBase64").GetString().Should().NotBeNullOrEmpty();
        clase.GetProperty("hoja").GetString().Should().Be("12345678~1~1123");
        clase.GetProperty("alumnos")[0].GetProperty("nombre").GetString().Should().Be("ANA");
        clase.GetProperty("valores")[0].GetProperty("valor").GetInt32().Should().Be(81);
    }

    [Fact]
    public async Task Por_celda_gana_la_captura_mas_nueva_aunque_llegue_despues_la_vieja()
    {
        var client = await RegisterAsync();
        await PushAsync(client, Clase("fisica", valores: [Valor(90, Importada.AddHours(2))]));
        // Otro teléfono que estuvo sin señal manda una captura anterior.
        await PushAsync(client, Clase("fisica", conArchivo: false, valores: [Valor(40, Importada.AddHours(1))]));

        var valor = ClaseDe(await PullAsync(client), "fisica").GetProperty("valores")[0];
        valor.GetProperty("valor").GetInt32().Should().Be(90);
    }

    [Fact]
    public async Task Un_borrado_de_nota_tambien_se_propaga()
    {
        var client = await RegisterAsync();
        await PushAsync(client, Clase("biologia", valores: [Valor(75, Importada.AddHours(1))]));
        await PushAsync(client, Clase("biologia", conArchivo: false, valores: [Valor(null, Importada.AddHours(2))]));

        var valor = ClaseDe(await PullAsync(client), "biologia").GetProperty("valores")[0];
        valor.GetProperty("valor").ValueKind.Should().Be(JsonValueKind.Null);
    }

    [Fact]
    public async Task El_pull_incremental_trae_solo_lo_cambiado_y_sin_archivo_si_la_plantilla_no_cambio()
    {
        var client = await RegisterAsync();
        await PushAsync(client, Clase("historia"), Clase("civica"));
        var cursor = (await PullAsync(client)).GetProperty("hasta").GetString();

        await PushAsync(client, Clase("civica", conArchivo: false, valores: [Valor(88, Importada.AddHours(3))]));
        var incremental = await PullAsync(client, cursor);

        incremental.GetProperty("clases").GetArrayLength().Should().Be(1);
        var civica = ClaseDe(incremental, "civica");
        civica.GetProperty("archivoBase64").ValueKind.Should().Be(JsonValueKind.Null);
        civica.GetProperty("valores")[0].GetProperty("valor").GetInt32().Should().Be(88);
    }

    [Fact]
    public async Task Una_clase_nueva_sin_archivo_se_rechaza()
    {
        var client = await RegisterAsync();

        var response = await client.PostAsJsonAsync("/api/v1/sync/push", new { clases = new[] { Clase("sin-archivo", conArchivo: false) } });

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Borrar_la_clase_deja_una_lapida_para_los_otros_dispositivos()
    {
        var client = await RegisterAsync();
        await PushAsync(client, Clase("arte", valores: [Valor(70, Importada.AddHours(1))]));
        await PushAsync(client, Clase("arte", conArchivo: false, eliminada: true));

        var clase = ClaseDe(await PullAsync(client), "arte");

        clase.GetProperty("eliminada").GetBoolean().Should().BeTrue();
        clase.GetProperty("valores").GetArrayLength().Should().Be(0);
        clase.GetProperty("archivoBase64").ValueKind.Should().Be(JsonValueKind.Null);
    }

    [Fact]
    public async Task Un_docente_no_ve_las_clases_de_otro()
    {
        var uno = await RegisterAsync();
        var otro = await RegisterAsync();
        await PushAsync(uno, Clase("privada"));

        var pull = await PullAsync(otro);

        pull.GetProperty("clases").GetArrayLength().Should().Be(0);
    }

    private static object Registro(string tipo, string clave, object? datos, DateTimeOffset cuando, bool eliminado = false, string claseClave = "quimica") =>
        new { tipo, claseClave, clave, datos = datos is null ? null : JsonSerializer.Serialize(datos), eliminado, actualizadoEn = cuando };

    private static async Task PushRegistrosAsync(HttpClient client, params object[] registros)
    {
        var response = await client.PostAsJsonAsync("/api/v1/sync/push", new { clases = Array.Empty<object>(), registros });
        response.StatusCode.Should().Be(HttpStatusCode.NoContent, await response.Content.ReadAsStringAsync());
    }

    private static JsonElement RegistroDe(JsonElement pull, string tipo, string clave) =>
        pull.GetProperty("registros").EnumerateArray()
            .Single(r => r.GetProperty("tipo").GetString() == tipo && r.GetProperty("clave").GetString() == clave);

    [Fact]
    public async Task Por_nota_de_actividad_gana_la_mas_nueva()
    {
        var client = await RegisterAsync();
        await PushRegistrosAsync(client, Registro("calificacion", "act1|0501", new { valor = 9.5 }, Importada.AddHours(2)));
        await PushRegistrosAsync(client, Registro("calificacion", "act1|0501", new { valor = 4 }, Importada.AddHours(1)));

        var nota = RegistroDe(await PullAsync(client), "calificacion", "act1|0501");

        JsonDocument.Parse(nota.GetProperty("datos").GetString()!).RootElement.GetProperty("valor").GetDouble().Should().Be(9.5);
    }

    [Fact]
    public async Task Borrar_una_actividad_deja_la_lapida_y_el_pull_incremental_la_trae()
    {
        var client = await RegisterAsync();
        await PushRegistrosAsync(client, Registro("actividad", "act2", new { titulo = "Tarea 1", puntos = 10 }, Importada.AddHours(1)));
        var cursor = (await PullAsync(client)).GetProperty("hasta").GetString();

        await PushRegistrosAsync(client, Registro("actividad", "act2", new { titulo = "Tarea 1", puntos = 10 }, Importada.AddHours(2), eliminado: true));
        var pull = await PullAsync(client, cursor);

        pull.GetProperty("registros").GetArrayLength().Should().Be(1);
        RegistroDe(pull, "actividad", "act2").GetProperty("eliminado").GetBoolean().Should().BeTrue();
    }

    [Fact]
    public async Task Las_plantillas_son_del_docente_y_no_se_mezclan_entre_docentes()
    {
        var uno = await RegisterAsync();
        var otro = await RegisterAsync();
        await PushRegistrosAsync(uno, Registro("plantilla", "p1", new { nombre = "Mi plan" }, Importada, claseClave: ""));

        (await PullAsync(uno)).GetProperty("registros").GetArrayLength().Should().Be(1);
        (await PullAsync(otro)).GetProperty("registros").GetArrayLength().Should().Be(0);
    }

    [Fact]
    public async Task Un_registro_de_tipo_desconocido_o_datos_que_no_son_json_se_rechaza()
    {
        var client = await RegisterAsync();

        var tipo = await client.PostAsJsonAsync("/api/v1/sync/push",
            new { registros = new[] { Registro("otra-cosa", "x", new { }, Importada) } });
        var datos = await client.PostAsJsonAsync("/api/v1/sync/push",
            new { registros = new[] { new { tipo = "rubro", claseClave = "c", clave = "r", datos = "{no es json", eliminado = false, actualizadoEn = Importada } } });

        tipo.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        datos.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }
}
