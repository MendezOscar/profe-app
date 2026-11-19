using Microsoft.EntityFrameworkCore;
using ProfeApp.Infrastructure.Persistence;
using System.IO.Compression;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.DependencyInjection;
using NPOI.HSSF.UserModel;
using ProfeApp.Domain.Common;
using ProfeApp.Infrastructure.Identity;
using ProfeApp.IntegrationTests.Infrastructure;

namespace ProfeApp.IntegrationTests;

public class ConsolidadoTests(ApiFixture fixture) : ApiTestBase(fixture)
{
    private static readonly DateTimeOffset Ahora = new(2027, 6, 1, 12, 0, 0, TimeSpan.Zero);

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
            nombre = "Colegio Consolidado", plan = "pequeno", maxDocentes = 5,
            adminEmail = $"director-{Guid.NewGuid():N}@prueba.hn", adminNombre = "Director",
        }));
        var admin2 = creado.GetProperty("admin");
        return await EntrarConTemporalAsync(admin2.GetProperty("email").GetString()!, admin2.GetProperty("claveTemporal").GetString()!);
    }

    /// <summary>Cuadro de dos parciales (el II con nivelación) y recuperación, con tres alumnos.</summary>
    private static object Clase(string clave, string asignatura, params (string Id, int Fila)[] alumnos) => new
    {
        clave,
        codigoCentro = "050100235M02", centro = "INSTITUTO", modalidad = "BTP", gradoSeccion = "SÉPTIMO GRADO SECCIÓN A",
        jornada = "JORNADA MATUTINA", asignatura, hoja = "12345678~1~1123", archivoNombre = $"{asignatura}.xls",
        archivoBase64 = Convert.ToBase64String(ExportarCuadroTests.CuadroDePrueba()),
        plantillaActualizadaEn = Ahora, eliminada = false,
        columnas = new[]
        {
            new { clave = "PARCIAL I|INASISTENCIAS", grupo = "PARCIAL I", nombre = "INASISTENCIAS", tipo = "inasistencias", col = 3, orden = 0 },
            new { clave = "PARCIAL I|NOTA TOTAL", grupo = "PARCIAL I", nombre = "NOTA TOTAL", tipo = "nota", col = 4, orden = 1 },
            new { clave = "PARCIAL II|NOTA TOTAL", grupo = "PARCIAL II", nombre = "NOTA TOTAL", tipo = "nota", col = 5, orden = 2 },
            new { clave = "PARCIAL II|NIVELACION", grupo = "PARCIAL II", nombre = "NIVELACIÓN", tipo = "nivelacion", col = 6, orden = 3 },
            new { clave = "RECUPERACION|RECUPERACION", grupo = "RECUPERACIÓN", nombre = "RECUPERACIÓN", tipo = "nota", col = 7, orden = 4 },
        },
        alumnos = alumnos.Select((a, i) => new { clave = a.Id, identidad = a.Id, documento = "HND", nombre = a.Id, fila = a.Fila, orden = i, activo = true }),
        valores = Array.Empty<object>(),
    };

    private static object V(string alumno, string columna, int valor) =>
        new { alumnoClave = alumno, columnaClave = columna, valor, actualizadoEn = Ahora };

    [Fact]
    public async Task El_consolidado_junta_las_asignaturas_de_la_seccion_con_final_recuperacion_y_resultado()
    {
        var c = await CentroAsync();
        var anio = (await ReadAsync(await c.PostAsJsonAsync("/api/v1/centro/anios",
            new { anio = 2027, inicio = "2027-02-01", fin = "2027-11-30", cierres = (string?[]?)null, actual = true }))).GetProperty("id").GetGuid();
        var grado = (await ReadAsync(await c.PostAsJsonAsync("/api/v1/centro/grados", new { nivel = "basica", nombre = "7.º grado" }))).GetProperty("id").GetGuid();
        var a = (await ReadAsync(await c.PostAsJsonAsync("/api/v1/centro/secciones", new
        {
            anioLectivoId = anio, gradoId = grado, nombre = "A", jornada = "matutina", cupo = (int?)null, aulaId = (Guid?)null, maestroGuiaId = (Guid?)null,
        }))).GetProperty("id").GetGuid();
        await c.PostAsJsonAsync($"/api/v1/centro/secciones/{a}/importar", new
        {
            alumnos = new[] { new { identidad = "0801201400001", nombre = "Ana" }, new { identidad = "0801201400002", nombre = "Beto" }, new { identidad = "0801201400003", nombre = "Carla" } },
        });

        var cuenta = await ReadAsync(await c.PostAsJsonAsync("/api/v1/centro/docentes", new { email = $"profe-{Guid.NewGuid():N}@prueba.hn", nombre = "Profe Mate" }));
        var docente = await EntrarConTemporalAsync(cuenta.GetProperty("email").GetString()!, cuenta.GetProperty("claveTemporal").GetString()!);
        var mate = Clase("mate", "MATEMÁTICAS", ("0801201400001", 7), ("0801201400002", 8), ("0801201400003", 9));
        // Otra clase del docente, de otra sección: no entra al consolidado.
        var otra = Clase("otra", "FÍSICA", ("0801209999991", 7), ("0801209999992", 8));
        (await docente.PostAsJsonAsync("/api/v1/sync/push", new { clases = new[] { mate, otra } })).StatusCode.Should().Be(HttpStatusCode.NoContent);
        (await docente.PostAsJsonAsync("/api/v1/sync/push", new
        {
            clases = new[]
            {
                new
                {
                    clave = "mate", codigoCentro = "050100235M02", centro = "INSTITUTO", modalidad = "BTP", gradoSeccion = "SÉPTIMO GRADO SECCIÓN A",
                    jornada = "JORNADA MATUTINA", asignatura = "MATEMÁTICAS", hoja = "12345678~1~1123", archivoNombre = "MATEMÁTICAS.xls",
                    archivoBase64 = (string?)null, plantillaActualizadaEn = Ahora, eliminada = false,
                    columnas = (object[]?)null, alumnos = (object[]?)null,
                    valores = new[]
                    {
                        // Ana: 80 y 70 → 75, aprobada.
                        V("0801201400001", "PARCIAL I|NOTA TOTAL", 80), V("0801201400001", "PARCIAL II|NOTA TOTAL", 70),
                        V("0801201400001", "PARCIAL I|INASISTENCIAS", 2),
                        // Beto: 60 y (55 + 15) → 65, a recuperación.
                        V("0801201400002", "PARCIAL I|NOTA TOTAL", 60), V("0801201400002", "PARCIAL II|NOTA TOTAL", 55),
                        V("0801201400002", "PARCIAL II|NIVELACION", 15),
                        // Carla: 50 y 40 → 45, recuperación 60: reprobada.
                        V("0801201400003", "PARCIAL I|NOTA TOTAL", 50), V("0801201400003", "PARCIAL II|NOTA TOTAL", 40),
                        V("0801201400003", "RECUPERACION|RECUPERACION", 60),
                    },
                },
            },
        })).StatusCode.Should().Be(HttpStatusCode.NoContent);

        var consolidado = await ReadAsync(await c.GetAsync($"/api/v1/centro/secciones/{a}/consolidado"));
        consolidado.GetProperty("notaMinima").GetInt32().Should().Be(70);
        var asignaturas = consolidado.GetProperty("asignaturas").EnumerateArray().ToList();
        asignaturas.Should().ContainSingle().Which.GetProperty("nombre").GetString().Should().Be("MATEMÁTICAS");
        asignaturas[0].GetProperty("parciales").EnumerateArray().Select(p => p.GetString()).Should().Equal("PARCIAL I", "PARCIAL II");

        JsonElement Fila(string nombre) => consolidado.GetProperty("alumnos").EnumerateArray().Single(x => x.GetProperty("nombre").GetString() == nombre);
        var ana = Fila("Ana");
        ana.GetProperty("notas")[0].GetProperty("final").GetInt32().Should().Be(75);
        ana.GetProperty("notas")[0].GetProperty("inasistencias").GetInt32().Should().Be(2);
        ana.GetProperty("resultado").GetString().Should().Be("aprobado");
        var beto = Fila("Beto");
        beto.GetProperty("notas")[0].GetProperty("parciales")[1].GetInt32().Should().Be(70, "la nivelación se suma al parcial");
        beto.GetProperty("notas")[0].GetProperty("final").GetInt32().Should().Be(65);
        beto.GetProperty("resultado").GetString().Should().Be("recuperacion");
        Fila("Carla").GetProperty("resultado").GetString().Should().Be("reprobado");

        // Los cuadros de SACE de la sección, llenos, en un .zip.
        var zip = await c.GetAsync($"/api/v1/centro/secciones/{a}/cuadros-sace");
        zip.StatusCode.Should().Be(HttpStatusCode.OK, await zip.Content.ReadAsStringAsync());
        using var archivo = new ZipArchive(new MemoryStream(await zip.Content.ReadAsByteArrayAsync()));
        archivo.Entries.Select(e => e.Name).Should().Equal("MATEMÁTICAS.xls");
        var libro = new HSSFWorkbook(archivo.Entries[0].Open());
        libro.GetSheet("12345678~1~1123").GetRow(7).GetCell(4).NumericCellValue.Should().Be(80);

        // Los reportes del centro usan el mismo consolidado.
        var reportes = await ReadAsync(await c.GetAsync("/api/v1/centro/reportes"));
        reportes.GetProperty("matricula").GetProperty("activos").GetInt32().Should().Be(3);
        reportes.GetProperty("matricula").GetProperty("nuevos").GetInt32().Should().Be(3);
        reportes.GetProperty("matricula").GetProperty("porSeccion")[0].GetProperty("sinSexo").GetInt32().Should().Be(3);
        var rend = reportes.GetProperty("rendimiento")[0].GetProperty("asignaturas")[0];
        rend.GetProperty("evaluados").GetInt32().Should().Be(3);
        rend.GetProperty("aprobados").GetInt32().Should().Be(1);
        rend.GetProperty("promedio").GetDecimal().Should().Be(66.7m, "75, 65 y la recuperación de 60");
        reportes.GetProperty("riesgo").EnumerateArray().Select(r => r.GetProperty("nombre").GetString())
            .Should().BeEquivalentTo(["Beto", "Carla"]);
        reportes.GetProperty("asistencia")[0].GetProperty("porcentaje").ValueKind.Should().Be(JsonValueKind.Null);

        // Estadísticas por docente: su carga y el rendimiento de lo que cerró.
        var stats = await ReadAsync(await c.GetAsync("/api/v1/centro/estadisticas-docentes"));
        var conNotas = stats.GetProperty("docentes").EnumerateArray().Single(d => d.GetProperty("evaluados").GetInt32() > 0);
        conNotas.GetProperty("evaluados").GetInt32().Should().Be(3);
        conNotas.GetProperty("aprobados").GetInt32().Should().Be(1);
        conNotas.GetProperty("promedio").GetDecimal().Should().Be(66.7m);
        conNotas.GetProperty("cuadrosEnApp").GetInt32().Should().BeGreaterThan(0);
        stats.GetProperty("diasHabiles").GetInt32().Should().Be(0, "el año 2027 aún no empieza");

        // Asistente del centro (plan Pro): sin Pro no hay; con Pro redacta en segundo plano.
        (await c.PostAsJsonAsync($"/api/v1/centro/secciones/{a}/comentarios/generar", new { parcial = 2, todos = false }))
            .StatusCode.Should().Be(HttpStatusCode.Forbidden);
        var institucionId = (await ReadAsync(await c.GetAsync("/api/v1/centro"))).GetProperty("institucion").GetProperty("id").GetGuid();
        using (var scope = Fixture.Services.CreateScope())
            await scope.ServiceProvider.GetRequiredService<AppDbContext>().Instituciones
                .Where(i => i.Id == institucionId).ExecuteUpdateAsync(x => x.SetProperty(i => i.ConIa, true));

        async Task<JsonElement> ComentariosListosAsync()
        {
            for (var i = 0; i < 50; i++)
            {
                var r = await ReadAsync(await c.GetAsync($"/api/v1/centro/secciones/{a}/comentarios?parcial=2"));
                if (!r.GetProperty("enProceso").GetBoolean()) return r;
                await Task.Delay(100);
            }
            throw new TimeoutException();
        }
        var antes = GeneradorDePrueba.Peticiones.Count;
        (await ReadAsync(await c.PostAsJsonAsync($"/api/v1/centro/secciones/{a}/comentarios/generar", new { parcial = 2, todos = false })))
            .GetProperty("alumnos").GetArrayLength().Should().Be(3);
        var listos = await ComentariosListosAsync();
        listos.GetProperty("alumnos").EnumerateArray().Should().OnlyContain(x => x.GetProperty("deIa").GetBoolean());
        var enviadas = GeneradorDePrueba.Peticiones.Skip(antes).Select(p => p.Usuario).ToList();
        enviadas.Should().HaveCount(3).And.OnlyContain(u => u.Contains("MATEMÁTICAS") && !u.Contains("Ana") && !u.Contains("0801201400001"));

        var primero = listos.GetProperty("alumnos")[0].GetProperty("alumnoId").GetGuid();
        (await c.PutAsJsonAsync($"/api/v1/centro/secciones/{a}/comentarios/{primero}", new { parcial = 2, texto = "Escrito por la dirección." }))
            .StatusCode.Should().Be(HttpStatusCode.NoContent);
        await c.PostAsJsonAsync($"/api/v1/centro/secciones/{a}/comentarios/generar", new { parcial = 2, todos = true });
        var rehechos = await ComentariosListosAsync();
        rehechos.GetProperty("alumnos")[0].GetProperty("texto").GetString().Should().Be("Escrito por la dirección.", "lo editado no se reescribe");
        (await ReadAsync(await c.GetAsync($"/api/v1/centro/secciones/{a}/consolidado")))
            .GetProperty("alumnos")[0].GetProperty("comentario").GetString().Should().Be("Escrito por la dirección.");

        var informe = await ReadAsync(await c.PostAsync("/api/v1/centro/ia/informe", null));
        informe.GetProperty("recomendaciones").GetArrayLength().Should().BeGreaterThan(0);
        GeneradorDePrueba.Peticiones.Last().Usuario.Should().Contain("MATEMÁTICAS").And.NotContain("Beto").And.NotContain("Profe Mate");
        var borrador = await ReadAsync(await c.PostAsJsonAsync("/api/v1/centro/ia/comunicado", new { puntos = "Reunión el viernes 3 pm", destinatarios = (string?)null }));
        borrador.GetProperty("titulo").GetString().Should().Be("Reunión de padres");
        var respuesta = await ReadAsync(await c.PostAsJsonAsync("/api/v1/centro/ia/pregunta", new
        {
            pregunta = "¿Cómo va Matemáticas?", historial = new[] { new { pregunta = "Hola", respuesta = "Hola, ¿en qué te ayudo?" } },
        }));
        respuesta.GetProperty("texto").GetString().Should().NotBeNullOrWhiteSpace();
        var consulta = GeneradorDePrueba.Peticiones.Last();
        consulta.Sistema.Should().Contain("MATEMÁTICAS").And.Contain("Profe Mate").And.NotContain("Beto").And.NotContain("0801201400002");
        consulta.Historial.Should().ContainSingle();

        var estado = await ReadAsync(await c.GetAsync("/api/v1/centro/ia/estado"));
        estado.GetProperty("creditos").GetDecimal().Should().Be(7.5m, "5 boletas (3 y 2 al rehacer) ½, informe 3, comunicado ½, pregunta 1½");
        estado.GetProperty("limiteCreditos").GetInt32().Should().Be(25 * Math.Max(1, estado.GetProperty("docentes").GetInt32()));

        // El docente del centro con Pro (sin Pro propio) tiene 75 créditos, y lo suyo no gasta los de la dirección.
        var delDocente = await ReadAsync(await docente.GetAsync("/api/v1/ia/estado"));
        delDocente.GetProperty("habilitada").GetBoolean().Should().BeTrue();
        delDocente.GetProperty("limiteCreditos").GetInt32().Should().Be(75);

        // Otro centro no ve este consolidado.
        var otro = await CentroAsync();
        (await otro.GetAsync($"/api/v1/centro/secciones/{a}/consolidado")).StatusCode.Should().Be(HttpStatusCode.NotFound);
    }
}
