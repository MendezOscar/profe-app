using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using ProfeApp.Application.Abstractions;
using ProfeApp.Infrastructure.Identity;
using ProfeApp.Infrastructure.Persistence;
using ProfeApp.Infrastructure.Sace;

namespace ProfeApp.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddProfeAppInfrastructure(
        this IServiceCollection services, IConfiguration configuration)
    {
        services.Configure<JwtOptions>(configuration.GetSection(JwtOptions.Section));
        services.Configure<ClockOptions>(configuration.GetSection(ClockOptions.Section));

        services.AddSingleton<IClock, SystemClock>();
        services.AddScoped<AuditingInterceptor>();

        services.AddDbContext<AppDbContext>((provider, options) =>
        {
            options.UseNpgsql(
                configuration.GetConnectionString("Default"),
                npgsql => npgsql.EnableRetryOnFailure(3));
            options.AddInterceptors(provider.GetRequiredService<AuditingInterceptor>());
            if (configuration.GetValue<bool>("App:DetailedSqlLogging"))
                options.EnableSensitiveDataLogging().EnableDetailedErrors();
        });
        services.AddScoped<IAppDbContext>(provider => provider.GetRequiredService<AppDbContext>());

        services.AddIdentityCore<AppUser>(options =>
            {
                options.Password.RequiredLength = 8;
                options.Password.RequireNonAlphanumeric = false;
                options.User.RequireUniqueEmail = true;
                options.Lockout.MaxFailedAccessAttempts = 10;
            })
            .AddRoles<AppRole>()
            .AddEntityFrameworkStores<AppDbContext>()
            .AddTokenProvider<DataProtectorTokenProvider<AppUser>>(TokenOptions.DefaultProvider);
        services.AddDataProtection();

        services.AddScoped<TokenService>();
        services.AddScoped<IAuthService, AuthService>();
        services.AddSingleton<ICuadroSaceWriter, CuadroSaceWriter>();

        return services;
    }
}
