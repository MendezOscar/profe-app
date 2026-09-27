using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;
using ProfeApp.Domain.Common;
using ProfeApp.Domain.Instituciones;
using ProfeApp.Domain.Tenants;
using ProfeApp.Infrastructure.Identity;
using ProfeApp.Infrastructure.Persistence;

namespace ProfeApp.Infrastructure.Instituciones;

/// <summary>
/// Altas y control de cuentas: el administrador de un centro sobre sus docentes y la
/// plataforma sobre los centros. Nadie aquí toca las notas de un docente; el avance se
/// lee contando sus registros, sin abrirlos.
/// </summary>
public sealed class AdminService(
    AppDbContext db,
    UserManager<AppUser> users,
    ICurrentUser currentUser,
    IClock clock) : ICentroService, IPlataformaService
{
    private static readonly string[] Planes = ["pequeno", "mediano", "grande", "red"];

    // ── Centro ───────────────────────────────────────────────────────────────

    public async Task<Result<CentroDto>> ObtenerAsync(CancellationToken ct = default)
    {
        var institucion = await MiInstitucionAsync(ct);
        if (institucion is null) return Result<CentroDto>.Fail(Error.Forbidden("Tu cuenta no administra un centro."));

        var docentes = await DocentesDeAsync(institucion.Id, ct);
        var tenants = docentes.Where(d => d.TenantId is not null).Select(d => d.TenantId!.Value).ToList();

        // Los datos de cada docente están en su tenant: se cuentan saltando el filtro, sólo de estos tenants.
        var asignaturas = await db.Clases.IgnoreQueryFilters()
            .Where(c => tenants.Contains(c.TenantId) && c.EliminadaEn == null)
            .GroupBy(c => c.TenantId).Select(g => new { g.Key, N = g.Count() })
            .ToDictionaryAsync(x => x.Key, x => x.N, ct);
        var actividades = await db.Registros.IgnoreQueryFilters()
            .Where(r => tenants.Contains(r.TenantId) && r.Tipo == "actividad" && !r.Eliminado)
            .GroupBy(r => r.TenantId).Select(g => new { g.Key, N = g.Count() })
            .ToDictionaryAsync(x => x.Key, x => x.N, ct);
        var parciales = (await db.Registros.IgnoreQueryFilters()
                .Where(r => tenants.Contains(r.TenantId) && r.Tipo == "parcial")
                .Select(r => new { r.TenantId, r.Datos })
                .ToListAsync(ct))
            .Where(r => EstaCerrado(r.Datos))
            .GroupBy(r => r.TenantId)
            .ToDictionary(g => g.Key, g => g.Count());

        int De(Dictionary<Guid, int> d, Guid? t) => t is { } id && d.TryGetValue(id, out var n) ? n : 0;

        return new CentroDto(
            ADto(institucion, docentes.Count(d => d.IsActive)),
            docentes
                .OrderBy(d => d.FullName)
                .Select(d => new DocenteCentroDto(d.Id, d.FullName, d.Email!, d.IsActive, d.LastLoginAt,
                    De(asignaturas, d.TenantId), De(actividades, d.TenantId), De(parciales, d.TenantId)))
                .ToList());
    }

    public async Task<Result<CuentaCreada>> CrearDocenteAsync(CrearDocenteRequest request, CancellationToken ct = default)
    {
        var institucion = await MiInstitucionAsync(ct);
        if (institucion is null) return Result<CuentaCreada>.Fail(Error.Forbidden("Tu cuenta no administra un centro."));
        if (!institucion.Vigente(clock.Now))
            return Result<CuentaCreada>.Fail(Error.Forbidden("La licencia del centro no está vigente."));

        var activos = (await DocentesDeAsync(institucion.Id, ct)).Count(d => d.IsActive);
        if (activos >= institucion.MaxDocentes)
            return Result<CuentaCreada>.Fail(Error.Conflict(
                $"La licencia cubre {institucion.MaxDocentes} docentes y ya están todos. Desactiva uno o amplía el plan.", "cupo_lleno"));

        return await CrearCuentaAsync(request.Email, request.Nombre, Roles.Docente, institucion.Id, conEspacio: true, ct);
    }

    public async Task<Result> CambiarEstadoDocenteAsync(Guid docenteId, bool activo, CancellationToken ct = default)
    {
        var institucion = await MiInstitucionAsync(ct);
        if (institucion is null) return Result.Fail(Error.Forbidden("Tu cuenta no administra un centro."));
        var docente = await DocenteDelCentroAsync(institucion.Id, docenteId);
        if (docente is null) return Result.Fail(Error.NotFound("El docente"));

        if (activo && !docente.IsActive)
        {
            var activos = (await DocentesDeAsync(institucion.Id, ct)).Count(d => d.IsActive);
            if (activos >= institucion.MaxDocentes)
                return Result.Fail(Error.Conflict($"La licencia cubre {institucion.MaxDocentes} docentes.", "cupo_lleno"));
        }

        docente.IsActive = activo;
        await users.UpdateAsync(docente);
        // Desactivado, se cierran sus sesiones en todos los dispositivos.
        if (!activo) await db.RefreshTokens.Where(t => t.UserId == docente.Id).ExecuteDeleteAsync(ct);
        return Result.Success();
    }

    public async Task<Result<CuentaCreada>> RestablecerClaveAsync(Guid docenteId, CancellationToken ct = default)
    {
        var institucion = await MiInstitucionAsync(ct);
        if (institucion is null) return Result<CuentaCreada>.Fail(Error.Forbidden("Tu cuenta no administra un centro."));
        var docente = await DocenteDelCentroAsync(institucion.Id, docenteId);
        if (docente is null) return Result<CuentaCreada>.Fail(Error.NotFound("El docente"));

        var clave = ClaveTemporal();
        var token = await users.GeneratePasswordResetTokenAsync(docente);
        var result = await users.ResetPasswordAsync(docente, token, clave);
        if (!result.Succeeded)
            return Result<CuentaCreada>.Fail(Error.Validation(string.Join(" ", result.Errors.Select(e => e.Description))));
        docente.MustChangePassword = true;
        await users.UpdateAsync(docente);
        await db.RefreshTokens.Where(t => t.UserId == docente.Id).ExecuteDeleteAsync(ct);
        return new CuentaCreada(docente.Id, docente.Email!, docente.FullName, clave);
    }

    // ── Plataforma ───────────────────────────────────────────────────────────

    public async Task<Result<IReadOnlyList<InstitucionDto>>> InstitucionesAsync(CancellationToken ct = default)
    {
        var instituciones = await db.Instituciones.OrderBy(i => i.Nombre).ToListAsync(ct);
        var docentes = await CuposUsadosAsync(ct);
        return instituciones.Select(i => ADto(i, docentes.GetValueOrDefault(i.Id))).ToList();
    }

    public async Task<Result<InstitucionCreada>> CrearInstitucionAsync(CrearInstitucionRequest request, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(request.Nombre)) return Result<InstitucionCreada>.Fail(Error.Validation("El nombre del centro es obligatorio."));
        if (!Planes.Contains(request.Plan)) return Result<InstitucionCreada>.Fail(Error.Validation("Plan desconocido."));
        if (request.MaxDocentes is < 1 or > 5_000) return Result<InstitucionCreada>.Fail(Error.Validation("El cupo debe estar entre 1 y 5000."));

        var institucion = new Institucion
        {
            Nombre = request.Nombre.Trim(),
            Plan = request.Plan,
            MaxDocentes = request.MaxDocentes,
            VenceEn = request.VenceEn?.ToUniversalTime(),
            CreatedAt = clock.Now,
        };
        db.Instituciones.Add(institucion);
        await db.SaveChangesAsync(ct);

        var admin = await CrearCuentaAsync(request.AdminEmail, request.AdminNombre, Roles.AdminCentro, institucion.Id, conEspacio: false, ct);
        if (!admin.IsSuccess)
        {
            db.Instituciones.Remove(institucion);
            await db.SaveChangesAsync(ct);
            return Result<InstitucionCreada>.Fail(admin.Error!);
        }
        return new InstitucionCreada(ADto(institucion, 0), admin.Value!);
    }

    public async Task<Result<InstitucionDto>> ActualizarInstitucionAsync(Guid id, ActualizarInstitucionRequest request, CancellationToken ct = default)
    {
        var institucion = await db.Instituciones.FirstOrDefaultAsync(i => i.Id == id, ct);
        if (institucion is null) return Result<InstitucionDto>.Fail(Error.NotFound("El centro"));
        if (!Planes.Contains(request.Plan)) return Result<InstitucionDto>.Fail(Error.Validation("Plan desconocido."));
        if (request.MaxDocentes is < 1 or > 5_000) return Result<InstitucionDto>.Fail(Error.Validation("El cupo debe estar entre 1 y 5000."));

        institucion.Plan = request.Plan;
        institucion.MaxDocentes = request.MaxDocentes;
        institucion.VenceEn = request.VenceEn?.ToUniversalTime();
        institucion.Activa = request.Activa;
        await db.SaveChangesAsync(ct);
        return ADto(institucion, (await CuposUsadosAsync(ct)).GetValueOrDefault(id));
    }

    public Task<Result<CuentaCreada>> CrearDocentePersonalAsync(CrearDocenteRequest request, CancellationToken ct = default) =>
        CrearCuentaAsync(request.Email, request.Nombre, Roles.Docente, institucionId: null, conEspacio: true, ct);

    // ── Comunes ──────────────────────────────────────────────────────────────

    /// <summary>
    /// Cuenta nueva con contraseña temporal que hay que cambiar al entrar. El docente
    /// recibe su propio espacio de datos, igual que en el plan personal.
    /// </summary>
    private async Task<Result<CuentaCreada>> CrearCuentaAsync(
        string email, string nombre, string rol, Guid? institucionId, bool conEspacio, CancellationToken ct)
    {
        email = (email ?? "").Trim().ToLowerInvariant();
        if (!email.Contains('@')) return Result<CuentaCreada>.Fail(Error.Validation("El correo no es válido."));
        if (string.IsNullOrWhiteSpace(nombre)) return Result<CuentaCreada>.Fail(Error.Validation("El nombre es obligatorio."));
        if (await users.FindByEmailAsync(email) is not null)
            return Result<CuentaCreada>.Fail(Error.Conflict("Ya existe una cuenta con ese correo.", "email_taken"));

        var clave = ClaveTemporal();
        var user = new AppUser
        {
            Id = Guid.NewGuid(),
            UserName = email,
            Email = email,
            FullName = nombre.Trim(),
            InstitucionId = institucionId,
            MustChangePassword = true,
            CreatedAt = clock.Now,
        };

        // Con reintentos activos, la transacción va dentro de la estrategia de ejecución.
        var fallo = await db.Database.CreateExecutionStrategy().ExecuteAsync(async () =>
        {
            await using var tx = await db.Database.BeginTransactionAsync(ct);
            if (conEspacio)
            {
                var espacio = new Tenant { Name = user.FullName, CreatedAt = clock.Now };
                db.Tenants.Add(espacio);
                await db.SaveChangesAsync(ct);
                user.TenantId = espacio.Id;
            }
            var creado = await users.CreateAsync(user, clave);
            if (!creado.Succeeded) return string.Join(" ", creado.Errors.Select(e => e.Description));
            await users.AddToRoleAsync(user, rol);
            await tx.CommitAsync(ct);
            return null;
        });
        if (fallo is not null) return Result<CuentaCreada>.Fail(Error.Validation(fallo));
        return new CuentaCreada(user.Id, email, user.FullName, clave);
    }

    private async Task<Institucion?> MiInstitucionAsync(CancellationToken ct)
    {
        var yo = await users.FindByIdAsync(currentUser.RequireUserId().ToString());
        return yo?.InstitucionId is { } id ? await db.Instituciones.FirstOrDefaultAsync(i => i.Id == id, ct) : null;
    }

    /// <summary>Docentes del centro: los del rol Docente, no su administrador.</summary>
    private async Task<List<AppUser>> DocentesDeAsync(Guid institucionId, CancellationToken ct)
    {
        var docentes = await users.GetUsersInRoleAsync(Roles.Docente);
        return docentes.Where(u => u.InstitucionId == institucionId).ToList();
    }

    private async Task<AppUser?> DocenteDelCentroAsync(Guid institucionId, Guid docenteId)
    {
        var docente = await users.FindByIdAsync(docenteId.ToString());
        if (docente is null || docente.InstitucionId != institucionId) return null;
        return await users.IsInRoleAsync(docente, Roles.Docente) ? docente : null;
    }

    private async Task<Dictionary<Guid, int>> CuposUsadosAsync(CancellationToken ct) =>
        (await users.GetUsersInRoleAsync(Roles.Docente))
            .Where(u => u.InstitucionId is not null && u.IsActive)
            .GroupBy(u => u.InstitucionId!.Value)
            .ToDictionary(g => g.Key, g => g.Count());

    private static bool EstaCerrado(string? datos)
    {
        if (datos is null) return false;
        try
        {
            using var json = JsonDocument.Parse(datos);
            return json.RootElement.TryGetProperty("cerradoEn", out var c) && c.ValueKind == JsonValueKind.String;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    /// <summary>Fácil de dictar por teléfono y cumple la política: Profe + 4 dígitos + 2 letras.</summary>
    private static string ClaveTemporal()
    {
        const string letras = "abcdefghjkmnpqrstuvwxyz";
        return $"Profe{RandomNumberGenerator.GetInt32(1000, 10000)}"
               + letras[RandomNumberGenerator.GetInt32(letras.Length)]
               + letras[RandomNumberGenerator.GetInt32(letras.Length)];
    }

    private static InstitucionDto ADto(Institucion i, int docentes) =>
        new(i.Id, i.Nombre, i.Plan, i.MaxDocentes, docentes, i.VenceEn, i.Activa);
}
