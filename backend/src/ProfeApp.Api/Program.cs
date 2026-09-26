using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.ResponseCompression;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Microsoft.OpenApi.Models;
using ProfeApp.Api.Auth;
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
    .AddPolicy(Policies.PlatformOnly, policy => policy.RequireRole(Roles.PlatformAdmin));

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
        policy.WithOrigins(corsOrigins).AllowAnyHeader().AllowAnyMethod().AllowCredentials();
    else if (builder.Environment.IsDevelopment())
        // Flutter web en desarrollo usa un puerto distinto en cada arranque.
        policy.SetIsOriginAllowed(_ => true).AllowAnyHeader().AllowAnyMethod().AllowCredentials();
}));

// Render termina TLS en su proxy: sin esto el esquema y la IP del cliente llegan mal.
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
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

var app = builder.Build();

app.UseForwardedHeaders();
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

app.MapHealthChecks("/health");
// Sonda de vida que no toca la base: con Neon, consultarla cada pocos segundos
// impediría que la base se suspenda.
app.MapHealthChecks("/health/live", new HealthCheckOptions { Predicate = _ => false });

app.MapAuthEndpoints();

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
        if (app.Configuration.GetValue<bool>("App:SeedDemoData"))
            await DataSeeder.SeedDemoAsync(scope.ServiceProvider);
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
