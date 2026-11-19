using System.Collections.Concurrent;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using ProfeApp.Application.Abstractions;
using Testcontainers.PostgreSql;

namespace ProfeApp.IntegrationTests.Infrastructure;

internal sealed class TestApp(string connectionString) : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        // Development para que el arranque aplique migraciones y siembre el docente demo.
        builder.UseEnvironment("Development");
        builder.ConfigureAppConfiguration((_, configuration) =>
            configuration.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:Default"] = connectionString,
                ["Jwt:Key"] = "clave-de-pruebas-integracion-con-mas-de-32-caracteres",
                ["App:SeedDemoData"] = "true",
                ["App:DemoPassword"] = "Demo1234!",
                ["App:DetailedSqlLogging"] = "false",
            }));
        // Los avisos al teléfono no salen a Firebase: se anotan para revisarlos.
        // Ni Firebase ni la IA salen a internet en las pruebas.
        builder.ConfigureTestServices(services =>
        {
            services.Replace(ServiceDescriptor.Singleton<IEnviadorPush, EnviadorDePrueba>());
            services.Replace(ServiceDescriptor.Singleton<IGeneradorIa, GeneradorDePrueba>());
        });
    }
}

/// <summary>Anota cada aviso enviado; un token que empieza con "muerto" se reporta como inválido.</summary>
public sealed class EnviadorDePrueba : IEnviadorPush
{
    public static readonly ConcurrentQueue<(string Token, string Titulo)> Enviados = new();

    public Task<IReadOnlyList<string>> EnviarAsync(IReadOnlyList<string> tokens, string titulo, string cuerpo, string? ruta, CancellationToken ct)
    {
        foreach (var t in tokens) Enviados.Enqueue((t, titulo));
        return Task.FromResult<IReadOnlyList<string>>(tokens.Where(t => t.StartsWith("muerto")).ToList());
    }
}

/// <summary>
/// Responde como lo haría el modelo según la función (por el esquema pedido) y anota cada
/// petición para revisar qué datos salieron.
/// </summary>
public sealed class GeneradorDePrueba : IGeneradorIa
{
    public static readonly ConcurrentQueue<PeticionIa> Peticiones = new();

    public bool Disponible => true;

    public Task<RespuestaIa> GenerarAsync(PeticionIa p, CancellationToken ct)
    {
        Peticiones.Enqueue(p);
        var texto = p.Esquema is null
            ? "El estudiante muestra compromiso con las tareas. Debe reforzar el examen."
            : p.Esquema["required"].GetRawText().Contains("rubros")
                ? """{"rubros":[{"nombre":"Tareas","puntos":30,"actividades":[{"titulo":"Tarea 1","puntos":30,"descripcion":"Resolver ejercicios.","semana":9}]},{"nombre":"Inventado","puntos":10,"actividades":[]},{"nombre":"Examen","puntos":70,"actividades":[{"titulo":"Examen parcial","puntos":70,"descripcion":"Prueba escrita.","semana":4}]}]}"""
                : """{"titulo":"Examen de fracciones","instrucciones":"Lee con atención.","preguntas":[{"tipo":"opcion_multiple","enunciado":"¿Cuánto es 1/2 + 1/4?","opciones":["3/4","2/6","1/8","1"],"respuesta":"3/4","puntos":5},{"tipo":"verdadero_falso","enunciado":"1/2 es mayor que 1/3.","opciones":["x"],"respuesta":"Verdadero","puntos":5}]}""";
        return Task.FromResult(new RespuestaIa(texto, "modelo-de-prueba", 100, 50));
    }
}

/// <summary>
/// Levanta la API contra un PostgreSQL real en Docker. Nada de dobles: los filtros de
/// tenant, los índices únicos y la idempotencia sólo se comprueban de verdad contra la base.
/// </summary>
public class ApiFixture : IAsyncLifetime
{
    private readonly PostgreSqlContainer _database = new PostgreSqlBuilder()
        .WithImage("postgres:15")
        .WithDatabase("profeapp_test")
        .WithUsername("profeapp")
        .WithPassword("profeapp")
        .Build();

    private TestApp? _app;

    public HttpClient CreateClient() => _app!.CreateClient();

    public IServiceProvider Services => _app!.Services;

    public async Task InitializeAsync()
    {
        await _database.StartAsync();
        _app = new TestApp(_database.GetConnectionString());
        // La primera petición fuerza el arranque: migraciones + seed.
        using var client = _app.CreateClient();
        (await client.GetAsync("/health")).EnsureSuccessStatusCode();
    }

    public async Task DisposeAsync()
    {
        if (_app is not null) await _app.DisposeAsync();
        await _database.DisposeAsync();
    }
}

[CollectionDefinition(Name)]
public sealed class ApiCollection : ICollectionFixture<ApiFixture>
{
    public const string Name = "api";
}
