using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;

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

    /// <summary>Docente nuevo, con su propio espacio: sirve para probar el aislamiento.</summary>
    protected async Task<HttpClient> RegisterAsync(string? email = null)
    {
        var client = Fixture.CreateClient();
        var response = await client.PostAsJsonAsync("/api/v1/auth/register", new
        {
            email = email ?? $"docente-{Guid.NewGuid():N}@prueba.hn",
            password = "Prueba1234!",
            fullName = "Docente de Prueba"
        });
        Authorize(client, await ReadAsync(response));
        return client;
    }

    protected static async Task<JsonElement> ReadAsync(HttpResponseMessage response)
    {
        var body = await response.Content.ReadAsStringAsync();
        response.IsSuccessStatusCode.Should().BeTrue($"{(int)response.StatusCode} {response.StatusCode}: {body}");
        return JsonSerializer.Deserialize<JsonElement>(body, Json);
    }

    private static void Authorize(HttpClient client, JsonElement payload)
    {
        var token = payload.GetProperty("tokens").GetProperty("accessToken").GetString();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
    }
}
