using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Services;
using ProfeApp.Infrastructure.Cobros;
using ProfeApp.Infrastructure.Identity;
using ProfeApp.Infrastructure.Instituciones;
using ProfeApp.Infrastructure.Mantenimiento;
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
            var connection = configuration.GetConnectionString("Default");
            if (string.IsNullOrWhiteSpace(connection))
                throw new InvalidOperationException("Falta ConnectionStrings:Default (usa dotnet user-secrets o una variable de entorno).");
            options.UseNpgsql(connection, npgsql => npgsql.EnableRetryOnFailure(3));
            options.AddInterceptors(provider.GetRequiredService<AuditingInterceptor>());
            if (configuration.GetValue<bool>("App:DetailedSqlLogging"))
                options.EnableSensitiveDataLogging().EnableDetailedErrors();
        });
        services.AddScoped<IAppDbContext>(provider => provider.GetRequiredService<AppDbContext>());

        services.Configure<PasswordHasherOptions>(o => o.IterationCount = AuthService.IteracionesHash);
        services.AddSingleton<TokensRevocados>();
        services.AddIdentityCore<AppUser>(options =>
            {
                options.Password.RequiredLength = 8;
                options.Password.RequireNonAlphanumeric = false;
                options.User.RequireUniqueEmail = true;
                options.Lockout.MaxFailedAccessAttempts = 10;
                options.Lockout.DefaultLockoutTimeSpan = TimeSpan.FromMinutes(15);
                options.Lockout.AllowedForNewUsers = true;
            })
            .AddRoles<AppRole>()
            .AddErrorDescriber<IdentityErrorsEs>()
            .AddEntityFrameworkStores<AppDbContext>()
            .AddTokenProvider<DataProtectorTokenProvider<AppUser>>(TokenOptions.DefaultProvider);
        services.AddDataProtection();

        services.AddScoped<TokenService>();
        services.AddMemoryCache();
        services.AddScoped<CobroService>();
        services.AddScoped<ICobroService>(p => p.GetRequiredService<CobroService>());
        services.AddScoped<IAuthService, AuthService>();
        services.AddSingleton<ICuadroSaceWriter, CuadroSaceWriter>();
        services.AddScoped<SyncService>();
        services.AddScoped<AdminService>();
        services.AddSingleton<LimpiezaService>();
        services.AddHostedService(p => p.GetRequiredService<LimpiezaService>());
        services.AddScoped<ICentroService>(p => p.GetRequiredService<AdminService>());
        services.AddScoped<IPlataformaService>(p => p.GetRequiredService<AdminService>());
        services.AddScoped<Centros.EstructuraCentroService>();
        services.AddScoped<IEstructuraCentroService>(p => p.GetRequiredService<Centros.EstructuraCentroService>());
        services.AddScoped<IMatriculaService, Centros.MatriculaService>();
        services.AddScoped<Centros.HorarioService>();
        services.AddScoped<IHorarioService>(p => p.GetRequiredService<Centros.HorarioService>());
        services.AddScoped<IMiCargaService, Centros.MiCargaService>();
        // Avisos al teléfono: cola en memoria y envío en segundo plano por Firebase.
        services.AddSingleton<Push.ColaPush>();
        services.AddSingleton<IAvisosPush>(p => p.GetRequiredService<Push.ColaPush>());
        services.AddSingleton<IEnviadorPush, Push.EnviadorFirebase>();
        services.AddHostedService<Push.ServicioPush>();
        services.AddScoped<IDispositivosService, Push.DispositivosService>();
        services.AddScoped<Centros.ConsolidadoService>();
        services.AddScoped<IConsolidadoService>(p => p.GetRequiredService<Centros.ConsolidadoService>());
        services.AddScoped<IReportesService, Centros.ReportesService>();
        services.AddScoped<IFamiliasCentroService, Centros.FamiliasCentroService>();
        services.AddScoped<IPadresService, Centros.PadresService>();
        services.AddScoped<IConvivenciaService, Centros.ConvivenciaService>();
        services.AddScoped<ICarnetService, Centros.CarnetService>();

        return services;
    }
}
