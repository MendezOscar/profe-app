using Microsoft.Extensions.DependencyInjection;
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

    private static object Valor(int? valor, DateTimeOffset cuando, string columna = "PARCIAL I|NOTA TOTAL") =>
        new { alumnoClave = "0501200900001", columnaClave = columna, valor, actualizadoEn = cuando };

    private static async Task PushAsync(HttpClient client, params object[] clases)
    {
        var response = await client.PostAsJsonAsync("/api/v1/sync/push", new { clases });
        response.StatusCode.Should().Be(HttpStatusCode.NoContent, await response.Content.ReadAsStringAsync());
    }

    private static async Task<JsonElement> PullAsync(HttpClient client, string? desde = null, string? hasta = null, int pagina = 0, string? despues = null)
    {
        var query = new List<string> { $"pagina={pagina}" };
        if (despues is not null) query.Add($"despues={Uri.EscapeDataString(despues)}");
        if (desde is not null) query.Add($"desde={Uri.EscapeDataString(desde)}");
        if (hasta is not null) query.Add($"hasta={Uri.EscapeDataString(hasta)}");
        return await ReadAsync(await client.GetAsync("/api/v1/sync/pull?" + string.Join("&", query)));
    }

    private static JsonElement ClaseDe(JsonElement pull, string clave) =>
        pull.GetProperty("clases").EnumerateArray().Single(c => c.GetProperty("clave").GetString() == clave);

    [Fact]
    public async Task Lo_que_sube_un_telefono_lo_baja_otro_con_su_archivo()
    {
        var telefonoA = await RegisterAsync();
        await PushAsync(telefonoA, Clase("quimica", valores: [Valor(81, Importada.AddHours(1))]));

        var clase = ClaseDe(await PullAsync(telefonoA), "quimica");
        // El archivo no viaja en el pull: se pide aparte, sólo si hace falta.
        var archivo = await ReadAsync(await telefonoA.GetAsync("/api/v1/sync/archivo?clave=quimica"));

        clase.GetProperty("archivoBase64").ValueKind.Should().Be(JsonValueKind.Null);
        clase.GetProperty("conPlantilla").GetBoolean().Should().BeTrue();
        archivo.GetProperty("archivoBase64").GetString().Should().Be(Convert.ToBase64String([0xD0, 0xCF, 0x11, 0xE0]));
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
    public async Task El_pull_incremental_trae_solo_las_celdas_cambiadas_y_sin_plantilla_si_no_cambio()
    {
        var client = await RegisterAsync();
        await PushAsync(client, Clase("historia"), Clase("civica", valores: [Valor(70, Importada.AddHours(1), "PARCIAL I|INASISTENCIAS")]));
        var cursor = (await PullAsync(client)).GetProperty("hasta").GetString();

        await PushAsync(client, Clase("civica", conArchivo: false, valores: [Valor(88, Importada.AddHours(3))]));
        var incremental = await PullAsync(client, cursor);

        incremental.GetProperty("clases").GetArrayLength().Should().Be(1);
        var civica = ClaseDe(incremental, "civica");
        civica.GetProperty("conPlantilla").GetBoolean().Should().BeFalse();
        civica.GetProperty("alumnos").GetArrayLength().Should().Be(0);
        civica.GetProperty("valores").GetArrayLength().Should().Be(1, "la celda de inasistencias no cambió");
        civica.GetProperty("valores")[0].GetProperty("valor").GetInt32().Should().Be(88);
    }

    [Fact]
    public async Task El_pull_de_registros_va_por_paginas_sin_perder_ninguno()
    {
        var client = await RegisterAsync();
        var registros = Enumerable.Range(0, 1_500)
            .Select(i => Registro("calificacion", $"act|{i}", new { valor = i % 10 }, Importada.AddMinutes(i)))
            .ToArray();
        await PushRegistrosAsync(client, registros);

        var primera = await PullAsync(client);
        var hasta = primera.GetProperty("hasta").GetString();
        var segunda = await PullAsync(client, hasta: hasta, pagina: 1);
        // El primer pull (sin desde) usa MinValue; la segunda página repite el mismo "hasta".

        primera.GetProperty("mas").GetBoolean().Should().BeTrue();
        primera.GetProperty("registros").GetArrayLength().Should().Be(1_000);
        segunda.GetProperty("mas").GetBoolean().Should().BeFalse();
        segunda.GetProperty("registros").GetArrayLength().Should().Be(500);
        primera.GetProperty("registros").EnumerateArray().Concat(segunda.GetProperty("registros").EnumerateArray())
            .Select(r => r.GetProperty("clave").GetString()).Distinct().Count().Should().Be(1_500);
        segunda.GetProperty("clases").GetArrayLength().Should().Be(0, "las clases van sólo en la primera página");
    }

    [Fact]
    public async Task El_pull_sigue_por_cursor_aunque_muchos_registros_tengan_la_misma_hora()
    {
        var client = await RegisterAsync();
        // Un solo push: todos quedan con el mismo modificado_en y el desempate es el id.
        await PushRegistrosAsync(client, Enumerable.Range(0, 2_000)
            .Select(i => Registro("calificacion", $"act|{i}", new { valor = 1 }, Importada)).ToArray());
        await PushRegistrosAsync(client, Enumerable.Range(2_000, 500)
            .Select(i => Registro("calificacion", $"act|{i}", new { valor = 1 }, Importada)).ToArray());

        var claves = new List<string?>();
        var pull = await PullAsync(client);
        var hasta = pull.GetProperty("hasta").GetString();
        claves.AddRange(pull.GetProperty("registros").EnumerateArray().Select(r => r.GetProperty("clave").GetString()));
        while (pull.GetProperty("mas").GetBoolean())
        {
            pull = await PullAsync(client, hasta: hasta, despues: pull.GetProperty("siguiente").GetString());
            pull.GetProperty("clases").GetArrayLength().Should().Be(0);
            claves.AddRange(pull.GetProperty("registros").EnumerateArray().Select(r => r.GetProperty("clave").GetString()));
        }

        claves.Should().HaveCount(2_500).And.OnlyHaveUniqueItems();
        pull.GetProperty("siguiente").ValueKind.Should().Be(JsonValueKind.Null);
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

    [Fact]
    public async Task La_limpieza_diaria_corre_sin_errores_y_no_toca_lo_vigente()
    {
        var client = await RegisterAsync();
        await PushAsync(client, Clase("vigente", valores: [Valor(90, Importada.AddHours(1))]));

        using (var scope = Fixture.Services.CreateScope())
            await scope.ServiceProvider.GetRequiredService<ProfeApp.Infrastructure.Mantenimiento.LimpiezaService>()
                .LimpiarAsync(CancellationToken.None);

        ClaseDe(await PullAsync(client), "vigente").GetProperty("valores")[0].GetProperty("valor").GetInt32().Should().Be(90);
    }
}
