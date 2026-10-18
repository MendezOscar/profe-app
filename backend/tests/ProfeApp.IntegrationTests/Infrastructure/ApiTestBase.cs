using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Contracts;

namespace ProfeApp.IntegrationTests.Infrastructure;

[Collection(ApiCollection.Name)]
public abstract class ApiTestBase(ApiFixture fixture)
{
    protected static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    protected ApiFixture Fixture { get; } = fixture;

    protected async Task<HttpClient> LoginAsync(string email = "docente@demo.hn", string password = "Demo1234!")
    {
        var client = Fixture.CreateClient();
        var response = await client.PostAsJsonAsync("/api/v1/auth/login", new { email, password });
        Authorize(client, await ReadAsync(response));
        return client;
    }

    /// <summary>
    /// Docente nuevo, con su propio espacio: sirve para probar el aislamiento. Se crea con
    /// el servicio porque la API no tiene registro público.
    /// </summary>
    /// <summary>Contraseña que ponen las pruebas al cambiar una temporal.</summary>
    protected const string ClaveNueva = "Nueva-Clave-1234";

    /// <summary>Entra con la clave temporal y la cambia, como obliga el servidor antes de dejar usar la API.</summary>
    protected async Task<HttpClient> EntrarConTemporalAsync(string email, string temporal)
    {
        var client = await LoginAsync(email, temporal);
        (await client.PostAsJsonAsync("/api/v1/auth/change-password", new { currentPassword = temporal, newPassword = ClaveNueva }))
            .IsSuccessStatusCode.Should().BeTrue();
        return client;
    }

    protected async Task<HttpClient> RegisterAsync(string? email = null)
    {
        using var scope = Fixture.Services.CreateScope();
        var result = await scope.ServiceProvider.GetRequiredService<IAuthService>().RegisterAsync(
            new RegisterRequest(email ?? $"docente-{Guid.NewGuid():N}@prueba.hn", "Prueba1234!", "Docente de Prueba"), null);
        result.IsSuccess.Should().BeTrue(result.Error?.Message);

        var client = Fixture.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", result.Value.Tokens.AccessToken);
        Refresh.AddOrUpdate(client, result.Value.Tokens.RefreshToken);
        return client;
    }

    protected static async Task<JsonElement> ReadAsync(HttpResponseMessage response)
    {
        var body = await response.Content.ReadAsStringAsync();
        response.IsSuccessStatusCode.Should().BeTrue($"{(int)response.StatusCode} {response.StatusCode}: {body}");
        return JsonSerializer.Deserialize<JsonElement>(body, Json);
    }

    private static readonly System.Runtime.CompilerServices.ConditionalWeakTable<HttpClient, string> Refresh = new();

    /// <summary>El refresh token con que quedó logueado el cliente.</summary>
    protected static string RefreshDe(HttpClient client) => Refresh.TryGetValue(client, out var t) ? t : throw new InvalidOperationException("Sin sesión.");

    protected static void Autorizar(HttpClient client, JsonElement payload) => Authorize(client, payload);

    private static void Authorize(HttpClient client, JsonElement payload)
    {
        var tokens = payload.GetProperty("tokens");
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", tokens.GetProperty("accessToken").GetString());
        Refresh.AddOrUpdate(client, tokens.GetProperty("refreshToken").GetString()!);
    }
}
