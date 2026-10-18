using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using System.Security.Claims;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.ResponseCompression;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Microsoft.OpenApi.Models;
using ProfeApp.Api.Auth;
using ProfeApp.Api.Common;
using ProfeApp.Api.Endpoints;
using ProfeApp.Application.Abstractions;
using ProfeApp.Domain.Common;
using ProfeApp.Infrastructure;
using ProfeApp.Infrastructure.Persistence;
using ProfeApp.Infrastructure.Seed;
using Serilog;

var builder = WebApplication.CreateBuilder(args);

// Render inyecta el puerto a escuchar en PORT.
var injectedPort = builder.Configuration["PORT"];
if (!string.IsNullOrWhiteSpace(injectedPort))
    builder.WebHost.UseUrls($"http://0.0.0.0:{injectedPort}");

builder.Host.UseSerilog((context, logger) => logger
    .ReadFrom.Configuration(context.Configuration)
    .WriteTo.Console());

builder.Services.AddProfeAppInfrastructure(builder.Configuration);

builder.Services.AddHttpContextAccessor();
builder.Services.AddScoped<ITenantContext, HttpTenantContext>();
builder.Services.AddScoped<ICurrentUser, HttpCurrentUser>();

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer();
builder.Services.AddSingleton<IPostConfigureOptions<JwtBearerOptions>, JwtBearerSetup>();

builder.Services.AddAuthorizationBuilder()
    .AddPolicy(Policies.DocenteOnly, policy => policy.RequireRole(Roles.Docente))
    .AddPolicy(Policies.PlatformOnly, policy => policy.RequireRole(Roles.PlatformAdmin))
    .AddPolicy(Policies.CentroOnly, policy => policy.RequireRole(Roles.AdminCentro));

builder.Services.AddProblemDetails();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "ProfeApp API",
        Version = "v1",
        Description = "Respaldo y sincronización del cuadro de notas del docente para SACE."
    });
    options.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Name = "Authorization",
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        In = ParameterLocation.Header
    });
    options.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        [new OpenApiSecurityScheme { Reference = new OpenApiReference { Id = "Bearer", Type = ReferenceType.SecurityScheme } }] = []
    });
});

var corsOrigins = builder.Configuration.GetSection("App:CorsOrigins").Get<string[]>() ?? [];
builder.Services.AddCors(options => options.AddDefaultPolicy(policy =>
{
    if (corsOrigins.Length > 0)
        // Sin AllowCredentials: el token va en el encabezado Authorization, no hay cookies.
        policy.WithOrigins(corsOrigins).WithHeaders("Authorization", "Content-Type", "X-Client-Request-Id").WithMethods("GET", "POST", "PUT", "DELETE")
            .SetPreflightMaxAge(TimeSpan.FromHours(1));
    else if (builder.Environment.IsDevelopment())
        // Flutter web en desarrollo usa un puerto distinto en cada arranque.
        policy.SetIsOriginAllowed(_ => true).AllowAnyHeader().AllowAnyMethod().AllowCredentials();
}));

// Render termina TLS en su proxy: sin esto el esquema llega mal. La IP del cliente no sale de
// aquí sino de IpCliente (CF-Connecting-IP): X-Forwarded-For se puede inventar.
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedProto;
    options.KnownNetworks.Clear();
    options.KnownProxies.Clear();
});

// El docente rural sincroniza con datos móviles caros: el JSON comprimido pesa la quinta parte.
builder.Services.AddResponseCompression(options =>
{
    options.EnableForHttps = true;
    options.Providers.Add<BrotliCompressionProvider>();
    options.Providers.Add<GzipCompressionProvider>();
});

builder.Services.AddHealthChecks().AddDbContextCheck<AppDbContext>();

// Límites para que un cliente con errores (o un abuso) no tumbe la API para todos.
// Sin IP conocida (pruebas, llamadas internas) no se limita.
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.OnRejected = async (context, ct) =>
    {
        context.HttpContext.Response.ContentType = "application/problem+json";
        await context.HttpContext.Response.WriteAsJsonAsync(new
        {
            status = 429,
            title = "Demasiadas solicitudes. Espera un momento y vuelve a intentar.",
            code = "demasiadas_solicitudes",
        }, ct);
    };

    // Por IP real (ver IpCliente). Sin IP conocida (pruebas, llamadas locales) no se limita.
    static RateLimitPartition<string> PorIp(HttpContext http, int permitidas) => IpCliente.De(http) is { } ip
        ? RateLimitPartition.GetFixedWindowLimiter(ip, _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = permitidas,
            Window = TimeSpan.FromMinutes(1),
        })
        : RateLimitPartition.GetNoLimiter("sin-ip");
    static string? UsuarioDe(HttpContext http) => http.User.FindFirstValue("sub") ?? http.User.FindFirstValue(ClaimTypes.NameIdentifier);

    // Intentos de login por IP: frena probar contraseñas contra muchos correos. 20 y no 10: un
    // colegio entero sale por la misma IP y entra a primera hora. Por correo, AuthService.
    options.AddPolicy(Limites.Login, http => PorIp(http, 20));

    // Sync por docente: de sobra para un primer pull por páginas, corta un bucle de reintentos.
    options.AddPolicy(Limites.Usuario, http =>
    {
        var usuario = UsuarioDe(http);
        return usuario is null || IpCliente.De(http) is null
            ? RateLimitPartition.GetNoLimiter("sin-usuario")
            : RateLimitPartition.GetTokenBucketLimiter(usuario, _ => new TokenBucketRateLimiterOptions
            {
                TokenLimit = 240,
                TokensPerPeriod = 60,
                ReplenishmentPeriod = TimeSpan.FromSeconds(30),
                QueueLimit = 20,
                QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
            });
    });

    // Cambiar la contraseña o borrar la cuenta: pocas veces por docente. Con un token robado
    // no se puede probar contraseñas en serie (además está el bloqueo de la cuenta).
    options.AddPolicy(Limites.Sensible, http =>
    {
        var usuario = UsuarioDe(http);
        return usuario is null || IpCliente.De(http) is null
            ? RateLimitPartition.GetNoLimiter("sin-usuario")
            : RateLimitPartition.GetFixedWindowLimiter(usuario, _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 5,
                Window = TimeSpan.FromMinutes(5),
            });
    });

    // Renovar y cerrar sesión, y /health (toca la base), por IP: generoso (un colegio entero
    // detrás de una misma IP), corta bucles e inundaciones.
    options.AddPolicy(Limites.Renovar, http => PorIp(http, 120));

    // Exportar abre el libro completo en memoria: en la semana de cierre todos exportan a
    // la vez. Pocas a la vez y el resto espera su turno, en lugar de quedarse sin memoria.
    options.AddConcurrencyLimiter(Limites.Exportar, limiter =>
    {
        limiter.PermitLimit = builder.Configuration.GetValue("App:ExportacionesSimultaneas", 4);
        limiter.QueueLimit = 100;
        limiter.QueueProcessingOrder = QueueProcessingOrder.OldestFirst;
    });

    // Red de seguridad para toda la API, encima de los límites de cada ruta: por docente (o por
    // IP sin sesión), muy por arriba del uso normal. Y exportar, por docente: que nadie llene
    // solo la cola de la semana de cierre.
    options.GlobalLimiter = PartitionedRateLimiter.CreateChained(
        PartitionedRateLimiter.Create<HttpContext, string>(http =>
            IpCliente.De(http) is not { } ip
                ? RateLimitPartition.GetNoLimiter("sin-ip")
                : RateLimitPartition.GetTokenBucketLimiter(UsuarioDe(http) ?? ip, _ => new TokenBucketRateLimiterOptions
                {
                    TokenLimit = 600,
                    TokensPerPeriod = 100,
                    ReplenishmentPeriod = TimeSpan.FromSeconds(10),
                })),
        PartitionedRateLimiter.Create<HttpContext, string>(http =>
            IpCliente.De(http) is not null && http.Request.Path.StartsWithSegments("/api/v1/cuadros/exportar") && UsuarioDe(http) is { } usuario
                ? RateLimitPartition.GetFixedWindowLimiter(usuario, _ => new FixedWindowRateLimiterOptions
                {
                    PermitLimit = 10,
                    Window = TimeSpan.FromMinutes(1),
                })
                : RateLimitPartition.GetNoLimiter("otra-ruta")));
});

var app = builder.Build();

app.UseForwardedHeaders();
if (!app.Environment.IsDevelopment()) app.UseHsts();
// La API sólo devuelve JSON y archivos: el navegador no debe interpretarlos como página.
app.Use((context, next) =>
{
    var h = context.Response.Headers;
    h.XContentTypeOptions = "nosniff";
    h.XFrameOptions = "DENY";
    h["Referrer-Policy"] = "no-referrer";
    // Swagger (sólo en desarrollo) necesita scripts y estilos propios.
    if (!app.Environment.IsDevelopment()) h.ContentSecurityPolicy = "default-src 'none'; frame-ancestors 'none'";
    return next(context);
});
app.UseResponseCompression();
app.UseSerilogRequestLogging();
app.UseExceptionHandler();
app.UseStatusCodePages();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI(options => options.SwaggerEndpoint("/swagger/v1/swagger.json", "ProfeApp API v1"));
}

app.UseCors();
app.UseAuthentication();
app.UseAuthorization();
app.UseRateLimiter();

app.MapHealthChecks("/health").RequireRateLimiting(Limites.Renovar);
// Sonda de vida que no toca la base: si la base tropieza, la plataforma no debe reiniciar
// la API por eso; la app reintenta la sincronización sola.
app.MapHealthChecks("/health/live", new HealthCheckOptions { Predicate = _ => false });

app.MapAuthEndpoints();
app.MapCuadroEndpoints();
app.MapSyncEndpoints();
app.MapAdminEndpoints();

// Migraciones automáticas en desarrollo; en producción son opt-in (App:ApplyMigrationsOnStartup).
if (app.Environment.IsDevelopment() || app.Configuration.GetValue<bool>("App:ApplyMigrationsOnStartup"))
{
    using var scope = app.Services.CreateScope();
    await scope.ServiceProvider.GetRequiredService<AppDbContext>().Database.MigrateAsync();
}

using (var scope = app.Services.CreateScope())
{
    try
    {
        await DataSeeder.EnsureRolesAsync(scope.ServiceProvider);
        await DataSeeder.EnsurePlatformAdminAsync(scope.ServiceProvider, app.Configuration);
        // Nunca en producción, aunque alguien active la bandera por error.
        if (!app.Environment.IsProduction() && app.Configuration.GetValue<bool>("App:SeedDemoData"))
            await DataSeeder.SeedDemoAsync(scope.ServiceProvider, app.Configuration);
    }
    catch (Exception error)
    {
        // Sin esquema todavía (producción antes de migrar) la API igual debe levantar.
        scope.ServiceProvider.GetRequiredService<ILoggerFactory>()
            .CreateLogger("Seed")
            .LogError(error, "Falló la carga de roles o datos demo; la API arranca igual.");
    }
}

app.Run();

public partial class Program;
