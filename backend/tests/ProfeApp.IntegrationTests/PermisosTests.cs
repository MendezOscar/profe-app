using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using ProfeApp.Api.Common;
using ProfeApp.Infrastructure.Persistence;
using ProfeApp.IntegrationTests.Infrastructure;

namespace ProfeApp.IntegrationTests;

[Collection(ApiCollection.Name)]
public class PermisosTests(ApiFixture fixture)
{
    /// <summary>
    /// En producción la API usa un usuario con permisos por tabla: una tabla nueva sin permiso
    /// hace fallar todo lo que la consulta (pasó con tandas_ia).
    /// </summary>
    [Fact]
    public async Task Toda_tabla_tiene_permiso_para_el_usuario_de_la_API()
    {
        using var scope = fixture.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var tablas = await db.Database.SqlQueryRaw<string>(
            "SELECT table_name AS \"Value\" FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE'")
            .ToListAsync();
        tablas.Should().NotBeEmpty();
        tablas.Where(t => !System.Text.RegularExpressions.Regex.IsMatch(PermisosDeLaApi.Sql, $@"(?<![\w""]){t}(?![\w""])") &&
                          !PermisosDeLaApi.Sql.Contains($"\"{t}\""))
            .Should().BeEmpty("cada tabla nueva va en PermisosDeLaApi.Sql");
    }
}
