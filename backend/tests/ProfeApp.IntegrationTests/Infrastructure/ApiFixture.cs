using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
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
                ["App:DetailedSqlLogging"] = "false",
            }));
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
