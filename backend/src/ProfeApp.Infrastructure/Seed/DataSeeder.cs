using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Contracts;
using ProfeApp.Domain.Common;
using ProfeApp.Infrastructure.Identity;

namespace ProfeApp.Infrastructure.Seed;

public static class DataSeeder
{
    public const string DemoEmail = "docente@demo.hn";
    public const string DemoPassword = "Demo1234!";

    /// <summary>Los roles hacen falta siempre, también en producción: el registro asigna Docente.</summary>
    public static async Task EnsureRolesAsync(IServiceProvider services)
    {
        var roles = services.GetRequiredService<RoleManager<AppRole>>();
        foreach (var role in Roles.All)
            if (!await roles.RoleExistsAsync(role))
                await roles.CreateAsync(new AppRole(role));
    }

    /// <summary>Un docente de demostración para desarrollo, dado de alta por el mismo registro que usa la app.</summary>
    public static async Task SeedDemoAsync(IServiceProvider services, CancellationToken ct = default)
    {
        var users = services.GetRequiredService<UserManager<AppUser>>();
        var logger = services.GetRequiredService<ILoggerFactory>().CreateLogger("DataSeeder");

        if (await users.FindByEmailAsync(DemoEmail) is not null) return;

        var result = await services.GetRequiredService<IAuthService>()
            .RegisterAsync(new RegisterRequest(DemoEmail, DemoPassword, "Docente Demo"), null, ct);
        if (!result.IsSuccess)
            logger.LogError("No se pudo crear el docente demo: {Error}", result.Error!.Message);
    }
}
