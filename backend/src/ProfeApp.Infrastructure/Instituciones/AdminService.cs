using System.Security.Cryptography;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;
using ProfeApp.Domain.Cobros;
using ProfeApp.Domain.Common;
using ProfeApp.Domain.Instituciones;
using ProfeApp.Domain.Tenants;
using ProfeApp.Infrastructure.Cobros;
using ProfeApp.Infrastructure.Identity;
using ProfeApp.Infrastructure.Persistence;

namespace ProfeApp.Infrastructure.Instituciones;

/// <summary>
/// Altas y control de cuentas: el administrador de un centro sobre sus docentes y la
/// plataforma sobre los centros y los docentes del plan personal, con su cobro. Nadie aquí
/// toca las notas de un docente; el avance se lee contando sus registros, sin abrirlos.
/// </summary>
public sealed class AdminService(
    AppDbContext db,
    UserManager<AppUser> users,
    ICurrentUser currentUser,
    CobroService cobros,
    IClock clock) : ICentroService, IPlataformaService
{
    private static readonly string[] Planes = ["pequeno", "mediano", "grande", "red"];
    private const int DocentesPorPagina = 50;

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
        // Cerrado = datos.cerradoEn no nulo. Se cuenta en la base, sin traer el JSON.
        var parciales = (await db.Database
                .SqlQuery<ConteoPorTenant>($@"SELECT tenant_id AS ""TenantId"", count(*)::int AS ""N"" FROM registros
                    WHERE tipo = 'parcial' AND tenant_id = ANY({tenants.ToArray()}) AND datos->>'cerradoEn' IS NOT NULL
                    GROUP BY tenant_id")
                .ToListAsync(ct))
            .ToDictionary(x => x.TenantId, x => x.N);

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
        if (!institucion.Activa || SituacionCobro.Para(institucion, clock.Today).SoloLectura)
            return Result<CuentaCreada>.Fail(Error.Forbidden("La licencia del centro no está al día."));

        var activos = await DocentesQuery().CountAsync(u => u.InstitucionId == institucion.Id && u.IsActive, ct);
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
            var activos = await DocentesQuery().CountAsync(u => u.InstitucionId == institucion.Id && u.IsActive, ct);
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
        return await ReponerAsync(docente, ct);
    }

    // ── Plataforma ───────────────────────────────────────────────────────────

    public async Task<Result<IReadOnlyList<InstitucionDto>>> InstitucionesAsync(CancellationToken ct = default)
    {
        var instituciones = await db.Instituciones.AsNoTracking().OrderBy(i => i.Nombre).ToListAsync(ct);
        var ids = instituciones.Select(i => i.Id).ToList();
        var docentes = await CuposUsadosAsync(ct);
        var admins = (await (from u in db.Users
                    join ur in db.UserRoles on u.Id equals ur.UserId
                    join r in db.Roles on ur.RoleId equals r.Id
                    where r.Name == Roles.AdminCentro && u.InstitucionId != null
                    select new { Id = u.InstitucionId!.Value, u.Email })
                .ToListAsync(ct))
            .DistinctBy(a => a.Id).ToDictionary(a => a.Id, a => a.Email);
        var pagos = await UltimosPagosAsync(ids, ct);
        return instituciones
            .Select(i => ADto(i, docentes.GetValueOrDefault(i.Id), admins.GetValueOrDefault(i.Id), pagos.GetValueOrDefault(i.Id)))
            .ToList();
    }

    public async Task<Result<InstitucionCreada>> CrearInstitucionAsync(CrearInstitucionRequest request, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(request.Nombre) || request.Nombre.Length > 200)
            return Result<InstitucionCreada>.Fail(Error.Validation("El nombre del centro es obligatorio (hasta 200 caracteres)."));
        if (!Planes.Contains(request.Plan)) return Result<InstitucionCreada>.Fail(Error.Validation("Plan desconocido."));
        if (request.MaxDocentes is < 1 or > 5_000) return Result<InstitucionCreada>.Fail(Error.Validation("El cupo debe estar entre 1 y 5000."));

        var institucion = new Institucion
        {
            Nombre = request.Nombre.Trim(),
            Plan = request.Plan,
            MaxDocentes = request.MaxDocentes,
            PagadoHasta = request.PagadoHasta,
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
        return new InstitucionCreada(ADto(institucion, 0, admin.Value!.Email), admin.Value!);
    }

    public async Task<Result<InstitucionDto>> ActualizarInstitucionAsync(Guid id, ActualizarInstitucionRequest request, CancellationToken ct = default)
    {
        var institucion = await db.Instituciones.FirstOrDefaultAsync(i => i.Id == id, ct);
        if (institucion is null) return Result<InstitucionDto>.Fail(Error.NotFound("El centro"));
        if (!Planes.Contains(request.Plan)) return Result<InstitucionDto>.Fail(Error.Validation("Plan desconocido."));
        if (request.MaxDocentes is < 1 or > 5_000) return Result<InstitucionDto>.Fail(Error.Validation("El cupo debe estar entre 1 y 5000."));

        institucion.Plan = request.Plan;
        institucion.MaxDocentes = request.MaxDocentes;
        await db.SaveChangesAsync(ct);
        return ADto(institucion, (await CuposUsadosAsync(ct)).GetValueOrDefault(id));
    }

    public Task<Result<CuentaCreada>> CrearDocentePersonalAsync(CrearDocenteRequest request, CancellationToken ct = default) =>
        CrearCuentaAsync(request.Email, request.Nombre, Roles.Docente, institucionId: null, conEspacio: true, ct);

    /// <summary>
    /// Los docentes del plan personal, de a <see cref="DocentesPorPagina"/>: pueden ser miles.
    /// Los conteos y el último pago se piden sólo para los de la página.
    /// </summary>
    public async Task<Result<PaginaDocentes>> DocentesAsync(string? buscar, int pagina, CancellationToken ct = default)
    {
        if (pagina < 0) return Result<PaginaDocentes>.Fail(Error.Validation("Página inválida."));
        var consulta =
            from u in DocentesQuery().Where(u => u.InstitucionId == null)
            join t in db.Tenants on u.TenantId equals t.Id
            select new { u, t };
        if (buscar?.Trim() is { Length: > 0 and <= 100 } texto)
        {
            var patron = $"%{texto.Replace("\\", "\\\\").Replace("%", "\\%").Replace("_", "\\_")}%";
            consulta = consulta.Where(x => EF.Functions.ILike(x.u.FullName, patron) || EF.Functions.ILike(x.u.Email!, patron));
        }

        var total = await consulta.CountAsync(ct);
        var filas = await consulta
            .OrderBy(x => x.u.FullName).ThenBy(x => x.u.Id)
            .Skip(pagina * DocentesPorPagina).Take(DocentesPorPagina)
            .Select(x => new { x.u.Id, x.u.FullName, x.u.Email, x.u.CreatedAt, x.u.LastLoginAt, Tenant = x.t })
            .AsNoTracking()
            .ToListAsync(ct);

        var tenants = filas.Select(f => f.Tenant.Id).ToList();
        var asignaturas = await db.Clases.IgnoreQueryFilters()
            .Where(c => tenants.Contains(c.TenantId) && c.EliminadaEn == null)
            .GroupBy(c => c.TenantId).Select(g => new { g.Key, N = g.Count() })
            .ToDictionaryAsync(x => x.Key, x => x.N, ct);
        var pagos = await UltimosPagosAsync(tenants, ct);

        var docentes = filas.Select(f => new DocentePlataformaDto(
                f.Id, f.FullName, f.Email!, f.Tenant.IsActive, f.CreatedAt, f.LastLoginAt,
                asignaturas.GetValueOrDefault(f.Tenant.Id),
                CobroService.Describir(SituacionCobro.Para(f.Tenant, clock.Today), esCentro: false, f.Tenant.Nivel),
                pagos.GetValueOrDefault(f.Tenant.Id)))
            .ToList();
        return new PaginaDocentes(docentes, total, (pagina + 1) * DocentesPorPagina < total);
    }

    public async Task<Result<CobroDto>> FijarPlanAsync(TipoCuenta tipo, Guid id, PlanCobroRequest request, CancellationToken ct = default)
    {
        var (cuenta, cuentaId) = await CuentaAsync(tipo, id, ct);
        if (cuenta is null) return Result<CobroDto>.Fail(Error.NotFound(tipo == TipoCuenta.Centro ? "El centro" : "El docente"));
        if (request.Monto is < 0 or > 1_000_000) return Result<CobroDto>.Fail(Error.Validation("El monto va de 0 a 1,000,000."));
        if (request.DiasGracia is < 0 or > 60) return Result<CobroDto>.Fail(Error.Validation("Los días de gracia van de 0 a 60."));
        if (request.PlanNombre?.Length > 80) return Result<CobroDto>.Fail(Error.Validation("El nombre del plan admite hasta 80 caracteres."));
        if (request.ComoPagar?.Length > 500) return Result<CobroDto>.Fail(Error.Validation("Cómo pagar admite hasta 500 caracteres."));
        if (request.Nivel is not null && (tipo == TipoCuenta.Centro || !NivelesDocente.Todos.Contains(request.Nivel)))
            return Result<CobroDto>.Fail(Error.Validation("Nivel desconocido."));

        cuenta.PlanNombre = Limpio(request.PlanNombre);
        cuenta.Monto = request.Monto;
        cuenta.PagadoHasta = request.PagadoHasta;
        cuenta.DiasGracia = request.DiasGracia;
        cuenta.ComoPagar = Limpio(request.ComoPagar);
        if (cuenta is Tenant espacio) espacio.Nivel = request.Nivel;
        await db.SaveChangesAsync(ct);
        cobros.Olvidar(cuentaId);
        return Describir(cuenta);
    }

    public async Task<Result<CobroDto>> RegistrarPagoAsync(TipoCuenta tipo, Guid id, RegistrarPagoRequest request, CancellationToken ct = default)
    {
        var (cuenta, cuentaId) = await CuentaAsync(tipo, id, ct);
        if (cuenta is null) return Result<CobroDto>.Fail(Error.NotFound(tipo == TipoCuenta.Centro ? "El centro" : "El docente"));
        if (request.Monto is < 0 or > 1_000_000) return Result<CobroDto>.Fail(Error.Validation("El monto va de 0 a 1,000,000."));
        if (request.Periodos is < 0 or > 36) return Result<CobroDto>.Fail(Error.Validation("Los períodos van de 0 a 36."));
        if (request.Referencia?.Length > 200) return Result<CobroDto>.Fail(Error.Validation("La referencia admite hasta 200 caracteres."));

        // Se suma al vencimiento que ya tenía, no a hoy: el día de cobro no se corre porque
        // pagó tarde. Una cuenta sin fecha arranca desde hoy.
        var hoy = clock.Today;
        var desde = cuenta.PagadoHasta ?? hoy;
        var hasta = request.PagadoHasta ?? desde.AddMonths(request.Periodos);
        if (hasta < cuenta.PagadoHasta)
            return Result<CobroDto>.Fail(Error.Validation("El pago no puede dejar un vencimiento anterior al que ya tenía."));

        db.Pagos.Add(new Pago
        {
            CuentaId = cuentaId,
            PagadoEl = request.PagadoEl ?? hoy,
            Monto = request.Monto,
            Periodos = request.Periodos,
            CubreHasta = hasta,
            Referencia = Limpio(request.Referencia),
            CreatedAt = clock.Now,
        });
        cuenta.PagadoHasta = hasta;
        await db.SaveChangesAsync(ct);
        cobros.Olvidar(cuentaId);
        return Describir(cuenta);
    }

    /// <summary>Del último hacia atrás y con tope: en pantalla caben los de este año.</summary>
    public async Task<Result<IReadOnlyList<PagoDto>>> PagosAsync(TipoCuenta tipo, Guid id, CancellationToken ct = default)
    {
        var (cuenta, cuentaId) = await CuentaAsync(tipo, id, ct);
        if (cuenta is null) return Result<IReadOnlyList<PagoDto>>.Fail(Error.NotFound(tipo == TipoCuenta.Centro ? "El centro" : "El docente"));
        return await db.Pagos.AsNoTracking()
            .Where(p => p.CuentaId == cuentaId)
            .OrderByDescending(p => p.PagadoEl).ThenByDescending(p => p.CreatedAt)
            .Take(24)
            .Select(p => new PagoDto(p.Id, p.PagadoEl, p.Monto, p.Periodos, p.CubreHasta, p.Referencia))
            .ToListAsync(ct);
    }

    /// <summary>Suspendida, nadie de la cuenta entra y se cierran sus sesiones. Los datos quedan.</summary>
    public async Task<Result> CambiarEstadoAsync(TipoCuenta tipo, Guid id, bool activa, CancellationToken ct = default)
    {
        var (cuenta, cuentaId) = await CuentaAsync(tipo, id, ct);
        switch (cuenta)
        {
            case Tenant espacio:
                espacio.IsActive = activa;
                break;
            case Institucion centro:
                centro.Activa = activa;
                break;
            default:
                return Result.Fail(Error.NotFound(tipo == TipoCuenta.Centro ? "El centro" : "El docente"));
        }
        await db.SaveChangesAsync(ct);
        cobros.Olvidar(cuentaId);
        if (!activa)
        {
            var usuarios = tipo == TipoCuenta.Centro
                ? db.Users.Where(u => u.InstitucionId == cuentaId).Select(u => u.Id)
                : db.Users.Where(u => u.Id == id).Select(u => u.Id);
            await db.RefreshTokens.Where(t => usuarios.Contains(t.UserId)).ExecuteDeleteAsync(ct);
        }
        return Result.Success();
    }

    public async Task<Result<CuentaCreada>> ReponerClaveAsync(TipoCuenta tipo, Guid id, CancellationToken ct = default)
    {
        var usuario = tipo == TipoCuenta.Centro
            ? await (from u in db.Users
                    join ur in db.UserRoles on u.Id equals ur.UserId
                    join r in db.Roles on ur.RoleId equals r.Id
                    where r.Name == Roles.AdminCentro && u.InstitucionId == id
                    orderby u.CreatedAt
                    select u).FirstOrDefaultAsync(ct)
            : await DocentesQuery().FirstOrDefaultAsync(u => u.Id == id && u.InstitucionId == null, ct);
        if (usuario is null)
            return Result<CuentaCreada>.Fail(Error.NotFound(tipo == TipoCuenta.Centro ? "El administrador del centro" : "El docente"));
        return await ReponerAsync(usuario, ct);
    }

    // ── Comunes ──────────────────────────────────────────────────────────────

    /// <summary>
    /// Cuenta nueva con contraseña temporal que hay que cambiar al entrar. El docente
    /// recibe su propio espacio de datos, igual que en el plan personal.
    /// </summary>
    private async Task<Result<CuentaCreada>> CrearCuentaAsync(
        string email, string nombre, string rol, Guid? institucionId, bool conEspacio, CancellationToken ct)
    {
        email = (email ?? "").Trim().ToLowerInvariant();
        if (!AuthService.CorreoValido(email)) return Result<CuentaCreada>.Fail(Error.Validation("El correo no es válido."));
        if (string.IsNullOrWhiteSpace(nombre) || nombre.Length > 120)
            return Result<CuentaCreada>.Fail(Error.Validation("El nombre es obligatorio (hasta 120 caracteres)."));
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

    /// <summary>Docentes del centro: los del rol Docente, no su administrador. Filtrado en la base.</summary>
    private Task<List<AppUser>> DocentesDeAsync(Guid institucionId, CancellationToken ct) =>
        DocentesQuery().Where(u => u.InstitucionId == institucionId).ToListAsync(ct);

    private IQueryable<AppUser> DocentesQuery() =>
        from u in db.Users
        join ur in db.UserRoles on u.Id equals ur.UserId
        join r in db.Roles on ur.RoleId equals r.Id
        where r.Name == Roles.Docente
        select u;

    private async Task<AppUser?> DocenteDelCentroAsync(Guid institucionId, Guid docenteId)
    {
        var docente = await users.FindByIdAsync(docenteId.ToString());
        if (docente is null || docente.InstitucionId != institucionId) return null;
        return await users.IsInRoleAsync(docente, Roles.Docente) ? docente : null;
    }

    private Task<Dictionary<Guid, int>> CuposUsadosAsync(CancellationToken ct) =>
        DocentesQuery()
            .Where(u => u.InstitucionId != null && u.IsActive)
            .GroupBy(u => u.InstitucionId!.Value)
            .Select(g => new { g.Key, N = g.Count() })
            .ToDictionaryAsync(x => x.Key, x => x.N, ct);

    private sealed record ConteoPorTenant(Guid TenantId, int N);

    /// <summary>La cuenta que se cobra: el espacio del docente personal o el centro.</summary>
    private async Task<(ICobrable? Cuenta, Guid CuentaId)> CuentaAsync(TipoCuenta tipo, Guid id, CancellationToken ct)
    {
        if (tipo == TipoCuenta.Centro)
            return (await db.Instituciones.FirstOrDefaultAsync(i => i.Id == id, ct), id);
        var tenantId = await DocentesQuery().Where(u => u.Id == id && u.InstitucionId == null)
            .Select(u => u.TenantId).FirstOrDefaultAsync(ct);
        if (tenantId is not { } espacio) return (null, Guid.Empty);
        return (await db.Tenants.FirstOrDefaultAsync(t => t.Id == espacio, ct), espacio);
    }

    /// <summary>Sin pagos, la cuenta no aparece: <c>GetValueOrDefault</c> da null, no una fecha vacía.</summary>
    private Task<Dictionary<Guid, DateOnly?>> UltimosPagosAsync(List<Guid> cuentas, CancellationToken ct) =>
        db.Pagos.Where(p => cuentas.Contains(p.CuentaId))
            .GroupBy(p => p.CuentaId).Select(g => new { g.Key, Ultimo = g.Max(p => p.PagadoEl) })
            .ToDictionaryAsync(x => x.Key, x => (DateOnly?)x.Ultimo, ct);

    private CobroDto Describir(ICobrable cuenta) =>
        CobroService.Describir(SituacionCobro.Para(cuenta, clock.Today), cuenta is Institucion, (cuenta as Tenant)?.Nivel);

    /// <summary>Contraseña temporal nueva; se cierran sus sesiones.</summary>
    private async Task<Result<CuentaCreada>> ReponerAsync(AppUser usuario, CancellationToken ct)
    {
        var clave = ClaveTemporal();
        var token = await users.GeneratePasswordResetTokenAsync(usuario);
        var result = await users.ResetPasswordAsync(usuario, token, clave);
        if (!result.Succeeded)
            return Result<CuentaCreada>.Fail(Error.Validation(string.Join(" ", result.Errors.Select(e => e.Description))));
        usuario.MustChangePassword = true;
        await users.UpdateAsync(usuario);
        await db.RefreshTokens.Where(t => t.UserId == usuario.Id).ExecuteDeleteAsync(ct);
        return new CuentaCreada(usuario.Id, usuario.Email!, usuario.FullName, clave);
    }

    private static string? Limpio(string? texto) => string.IsNullOrWhiteSpace(texto) ? null : texto.Trim();

    /// <summary>Fácil de dictar por teléfono y cumple la política: Profe + 4 dígitos + 2 letras.</summary>
    private static string ClaveTemporal()
    {
        const string letras = "abcdefghjkmnpqrstuvwxyz";
        return $"Profe{RandomNumberGenerator.GetInt32(1000, 10000)}"
               + letras[RandomNumberGenerator.GetInt32(letras.Length)]
               + letras[RandomNumberGenerator.GetInt32(letras.Length)];
    }

    private InstitucionDto ADto(Institucion i, int docentes, string? admin = null, DateOnly? ultimoPago = null) =>
        new(i.Id, i.Nombre, i.Plan, i.MaxDocentes, docentes, i.Activa, Describir(i), i.CreatedAt, admin, ultimoPago);
}
