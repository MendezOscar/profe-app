using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Configuration;
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

    /// <summary>
    /// La cuenta de quien opera ProfeApp (crea centros y cuentas del plan personal). Se
    /// toma de App:PlatformAdmin:Email y :Password; sin ellas no se crea. Si ya existe, no
    /// se toca: la contraseña se cambia desde la app.
    /// </summary>
    public static async Task EnsurePlatformAdminAsync(IServiceProvider services, IConfiguration configuration)
    {
        var email = configuration["App:PlatformAdmin:Email"]?.Trim().ToLowerInvariant();
        var password = configuration["App:PlatformAdmin:Password"];
        if (string.IsNullOrEmpty(email) || string.IsNullOrEmpty(password)) return;

        var users = services.GetRequiredService<UserManager<AppUser>>();
        if (await users.FindByEmailAsync(email) is not null) return;

        var admin = new AppUser
        {
            Id = Guid.NewGuid(),
            UserName = email,
            Email = email,
            FullName = configuration["App:PlatformAdmin:Name"] ?? "Administración ProfeApp",
            CreatedAt = DateTimeOffset.UtcNow,
        };
        var result = await users.CreateAsync(admin, password);
        if (result.Succeeded) await users.AddToRoleAsync(admin, Roles.PlatformAdmin);
        else
            services.GetRequiredService<ILoggerFactory>().CreateLogger("DataSeeder")
                .LogError("No se pudo crear el admin de plataforma: {Error}", string.Join(" ", result.Errors.Select(e => e.Description)));
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
