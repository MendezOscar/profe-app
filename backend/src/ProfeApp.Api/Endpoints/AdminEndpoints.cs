using ProfeApp.Api.Common;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Contracts;
using ProfeApp.Domain.Common;

namespace ProfeApp.Api.Endpoints;

public static class AdminEndpoints
{
    public static void MapAdminEndpoints(this IEndpointRouteBuilder app)
    {
        var centro = app.MapGroup("/api/v1/centro").WithTags("Centro").RequireAuthorization(Policies.CentroOnly)
            .RequireRateLimiting(Limites.Usuario);

        centro.MapGet("/", async (ICentroService s, CancellationToken ct) => (await s.ObtenerAsync(ct)).ToHttp())
            .WithSummary("El centro, su licencia y el avance de cada docente.");
        centro.MapPost("/docentes", async (CrearDocenteRequest r, ICentroService s, CancellationToken ct) =>
                (await s.CrearDocenteAsync(r, ct)).ToHttp())
            .WithSummary("Da de alta un docente con contraseña temporal.");
        centro.MapPost("/docentes/{id:guid}/activar", async (Guid id, ICentroService s, CancellationToken ct) =>
            (await s.CambiarEstadoDocenteAsync(id, true, ct)).ToHttp());
        centro.MapPost("/docentes/{id:guid}/desactivar", async (Guid id, ICentroService s, CancellationToken ct) =>
            (await s.CambiarEstadoDocenteAsync(id, false, ct)).ToHttp());
        centro.MapPost("/docentes/{id:guid}/restablecer-clave", async (Guid id, ICentroService s, CancellationToken ct) =>
            (await s.RestablecerClaveAsync(id, ct)).ToHttp());

        // Organización académica: años lectivos, grados y asignaturas, aulas, secciones y carga.
        centro.MapGet("/estructura", async (Guid? anioId, IEstructuraCentroService s, CancellationToken ct) =>
                (await s.ObtenerAsync(anioId, ct)).ToHttp())
            .WithSummary("Años lectivos, grados con asignaturas, aulas, secciones del año (por defecto el actual) y docentes.");
        centro.MapPost("/anios", async (AnioLectivoRequest r, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.GuardarAnioAsync(null, r, ct)).ToHttp());
        centro.MapPut("/anios/{id:guid}", async (Guid id, AnioLectivoRequest r, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.GuardarAnioAsync(id, r, ct)).ToHttp());
        centro.MapPost("/grados", async (GradoRequest r, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.GuardarGradoAsync(null, r, ct)).ToHttp());
        centro.MapPost("/grados/plantilla", async (PlantillaGradosRequest r, IEstructuraCentroService s, CancellationToken ct) =>
                (await s.PlantillaGradosAsync(r, ct)).ToHttp(n => Results.Ok(new { creados = n })))
            .WithSummary("Crea los grados de Honduras que falten en los niveles pedidos.");
        centro.MapPut("/grados/{id:guid}", async (Guid id, GradoRequest r, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.GuardarGradoAsync(id, r, ct)).ToHttp());
        centro.MapDelete("/grados/{id:guid}", async (Guid id, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.EliminarGradoAsync(id, ct)).ToHttp());
        centro.MapPost("/asignaturas", async (AgregarAsignaturasRequest r, IEstructuraCentroService s, CancellationToken ct) =>
                (await s.AgregarAsignaturasAsync(r, ct)).ToHttp(n => Results.Ok(new { creadas = n })))
            .WithSummary("Agrega las mismas asignaturas a varios grados.");
        centro.MapPut("/asignaturas/{id:guid}", async (Guid id, NombreRequest r, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.RenombrarAsignaturaAsync(id, r, ct)).ToHttp());
        centro.MapDelete("/asignaturas/{id:guid}", async (Guid id, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.EliminarAsignaturaAsync(id, ct)).ToHttp());
        centro.MapPost("/aulas", async (AulaRequest r, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.GuardarAulaAsync(null, r, ct)).ToHttp());
        centro.MapPut("/aulas/{id:guid}", async (Guid id, AulaRequest r, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.GuardarAulaAsync(id, r, ct)).ToHttp());
        centro.MapDelete("/aulas/{id:guid}", async (Guid id, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.EliminarAulaAsync(id, ct)).ToHttp());
        centro.MapPost("/secciones", async (SeccionRequest r, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.GuardarSeccionAsync(null, r, ct)).ToHttp());
        centro.MapPut("/secciones/{id:guid}", async (Guid id, SeccionRequest r, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.GuardarSeccionAsync(id, r, ct)).ToHttp());
        centro.MapDelete("/secciones/{id:guid}", async (Guid id, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.EliminarSeccionAsync(id, ct)).ToHttp());
        centro.MapPut("/secciones/{id:guid}/carga", async (Guid id, CargaRequest r, IEstructuraCentroService s, CancellationToken ct) =>
                (await s.GuardarCargaAsync(id, r, ct)).ToHttp())
            .WithSummary("Reemplaza qué docente da cada asignatura en la sección.");

        // Matrícula y fichas: la lista de cada sección se importa del archivo de SACE.
        centro.MapGet("/secciones/{id:guid}/alumnos", async (Guid id, IMatriculaService s, CancellationToken ct) =>
            (await s.AlumnosDeSeccionAsync(id, ct)).ToHttp());
        centro.MapPost("/secciones/{id:guid}/importar", async (Guid id, ImportarAlumnosRequest r, IMatriculaService s, CancellationToken ct) =>
                (await s.ImportarAsync(id, r, ct)).ToHttp())
            .WithSummary("Matricula en la sección a los alumnos leídos del archivo de SACE.");
        centro.MapPost("/secciones/{id:guid}/alumnos", async (Guid id, MatricularRequest r, IMatriculaService s, CancellationToken ct) =>
            (await s.MatricularAsync(id, r, ct)).ToHttp());
        centro.MapGet("/alumnos", async (string? buscar, int? pagina, IMatriculaService s, CancellationToken ct) =>
                (await s.BuscarAsync(buscar, pagina ?? 0, ct)).ToHttp())
            .WithSummary("Alumnos del centro por nombre o identidad, por páginas.");
        centro.MapGet("/alumnos/{id:guid}", async (Guid id, IMatriculaService s, CancellationToken ct) =>
            (await s.FichaAsync(id, ct)).ToHttp());
        centro.MapPut("/alumnos/{id:guid}", async (Guid id, FichaAlumnoRequest r, IMatriculaService s, CancellationToken ct) =>
            (await s.GuardarFichaAsync(id, r, ct)).ToHttp());
        centro.MapPost("/matriculas/{id:guid}/baja", async (Guid id, BajaRequest r, IMatriculaService s, CancellationToken ct) =>
            (await s.DarDeBajaAsync(id, r, ct)).ToHttp());
        centro.MapPost("/matriculas/{id:guid}/reactivar", async (Guid id, IMatriculaService s, CancellationToken ct) =>
            (await s.ReactivarAsync(id, ct)).ToHttp());
        centro.MapPut("/matriculas/{id:guid}/seccion", async (Guid id, CambioSeccionRequest r, IMatriculaService s, CancellationToken ct) =>
            (await s.CambiarSeccionAsync(id, r, ct)).ToHttp());

        // Familias: código para que el padre cree su cuenta, cuentas vinculadas y comunicados.
        centro.MapGet("/alumnos/{id:guid}/familia", async (Guid id, IFamiliasCentroService s, CancellationToken ct) =>
            (await s.FamiliaAsync(id, ct)).ToHttp());
        centro.MapPost("/alumnos/{id:guid}/familia/codigo", async (Guid id, IFamiliasCentroService s, CancellationToken ct) =>
                (await s.GenerarCodigoAsync(id, ct)).ToHttp())
            .WithSummary("Código nuevo para la familia (30 días); anula el anterior.");
        centro.MapDelete("/alumnos/{id:guid}/familia/{usuarioId:guid}", async (Guid id, Guid usuarioId, IFamiliasCentroService s, CancellationToken ct) =>
            (await s.QuitarAccesoAsync(id, usuarioId, ct)).ToHttp());
        centro.MapGet("/comunicados", async (IFamiliasCentroService s, CancellationToken ct) => (await s.ComunicadosAsync(ct)).ToHttp());
        centro.MapPost("/comunicados", async (ComunicadoRequest r, IFamiliasCentroService s, CancellationToken ct) =>
            (await s.PublicarAsync(r, ct)).ToHttp());
        centro.MapDelete("/comunicados/{id:guid}", async (Guid id, IFamiliasCentroService s, CancellationToken ct) =>
            (await s.EliminarComunicadoAsync(id, ct)).ToHttp());

        // Horario: bloques por jornada, horario de cada sección (sin choques) y lista del día.
        centro.MapGet("/bloques", async (IHorarioService s, CancellationToken ct) => (await s.BloquesAsync(ct)).ToHttp());
        centro.MapPost("/bloques", async (BloqueRequest r, IHorarioService s, CancellationToken ct) => (await s.GuardarBloqueAsync(null, r, ct)).ToHttp());
        centro.MapPut("/bloques/{id:guid}", async (Guid id, BloqueRequest r, IHorarioService s, CancellationToken ct) =>
            (await s.GuardarBloqueAsync(id, r, ct)).ToHttp());
        centro.MapDelete("/bloques/{id:guid}", async (Guid id, IHorarioService s, CancellationToken ct) => (await s.EliminarBloqueAsync(id, ct)).ToHttp());
        centro.MapGet("/secciones/{id:guid}/horario", async (Guid id, IHorarioService s, CancellationToken ct) =>
            (await s.HorarioSeccionAsync(id, ct)).ToHttp());
        centro.MapPut("/secciones/{id:guid}/horario", async (Guid id, HorarioSeccionRequest r, IHorarioService s, CancellationToken ct) =>
                (await s.GuardarHorarioAsync(id, r, ct)).ToHttp())
            .WithSummary("Reemplaza el horario de la sección; no guarda si un docente o un aula queda en dos lugares a la vez.");
        centro.MapGet("/docentes/{id:guid}/horario", async (Guid id, IHorarioService s, CancellationToken ct) =>
            (await s.HorarioDocenteAsync(id, ct)).ToHttp());
        centro.MapGet("/horario/choques", async (IHorarioService s, CancellationToken ct) => (await s.ChoquesAsync(ct)).ToHttp())
            .WithSummary("Choques del año actual (por ejemplo, tras cambiar la carga docente).");
        centro.MapGet("/asistencia-diaria", async (DateOnly? fecha, IHorarioService s, IClock clock, CancellationToken ct) =>
                (await s.AsistenciaDelDiaAsync(fecha ?? clock.Today, ct)).ToHttp())
            .WithSummary("Qué secciones pasaron lista ese día y quién faltó.");

        // Consolidado de la sección con lo que cerró cada docente, y sus cuadros de SACE llenos.
        centro.MapGet("/secciones/{id:guid}/consolidado", async (Guid id, IConsolidadoService s, CancellationToken ct) =>
                (await s.SeccionAsync(id, ct)).ToHttp())
            .WithSummary("Notas de cada alumno en todas las asignaturas de la sección, con final, recuperación y resultado.");
        centro.MapGet("/secciones/{id:guid}/cuadros-sace", async (Guid id, IConsolidadoService s, CancellationToken ct) =>
                (await s.CuadrosSaceAsync(id, ct)).ToHttp(c => Results.File(c.Contenido, c.ContentType, c.NombreArchivo)))
            .RequireRateLimiting(Limites.Exportar)
            .WithSummary("Los cuadros de SACE de la sección, llenos con lo que capturó cada docente, en un .zip.");

        // Excusas y permisos: quien pasa lista ve al alumno como falta justificada.
        centro.MapGet("/excusas", async (DateOnly? desde, Guid? alumnoId, IConvivenciaService s, CancellationToken ct) =>
            (await s.ExcusasAsync(desde, alumnoId, ct)).ToHttp());
        centro.MapPost("/excusas", async (ExcusaRequest r, IConvivenciaService s, CancellationToken ct) =>
            (await s.RegistrarExcusaAsync(r, ct)).ToHttp());
        centro.MapDelete("/excusas/{id:guid}", async (Guid id, IConvivenciaService s, CancellationToken ct) =>
            (await s.EliminarExcusaAsync(id, ct)).ToHttp());

        centro.MapGet("/reportes", async (IReportesService s, CancellationToken ct) => (await s.ResumenAsync(ct)).ToHttp())
            .WithSummary("Matrícula, rendimiento, alumnos en riesgo y asistencia del año actual.");

        // Personal: dirección, subdirección, secretaría y orientación.
        centro.MapGet("/personal", async (IEstructuraCentroService s, CancellationToken ct) => (await s.PersonalAsync(ct)).ToHttp());
        centro.MapPost("/personal", async (CrearPersonalRequest r, IEstructuraCentroService s, CancellationToken ct) =>
                (await s.CrearPersonalAsync(r, ct)).ToHttp())
            .WithSummary("Cuenta de personal con contraseña temporal; no cuenta en el cupo de docentes.");
        centro.MapPut("/personal/{id:guid}/cargo", async (Guid id, CargoRequest r, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.CambiarCargoAsync(id, r, ct)).ToHttp());
        centro.MapPost("/personal/{id:guid}/activar", async (Guid id, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.CambiarEstadoPersonalAsync(id, true, ct)).ToHttp());
        centro.MapPost("/personal/{id:guid}/desactivar", async (Guid id, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.CambiarEstadoPersonalAsync(id, false, ct)).ToHttp());
        centro.MapPost("/personal/{id:guid}/restablecer-clave", async (Guid id, IEstructuraCentroService s, CancellationToken ct) =>
            (await s.RestablecerClavePersonalAsync(id, ct)).ToHttp());

        // El maestro guía pasa la lista del día de su sección.
        app.MapGet("/api/v1/mi-centro/secciones/{id:guid}/asistencia", async (Guid id, DateOnly? fecha, IHorarioService s, IClock clock, CancellationToken ct) =>
                (await s.ListaDiariaAsync(id, fecha ?? clock.Today, ct)).ToHttp())
            .WithTags("Centro").RequireAuthorization(Policies.DocenteOnly).RequireRateLimiting(Limites.Usuario);
        app.MapPut("/api/v1/mi-centro/secciones/{id:guid}/asistencia", async (Guid id, ListaDiariaRequest r, IHorarioService s, CancellationToken ct) =>
                (await s.GuardarListaDiariaAsync(id, r, ct)).ToHttp())
            .WithTags("Centro").RequireAuthorization(Policies.DocenteOnly).RequireRateLimiting(Limites.Usuario);

        // Teléfono que recibe avisos (cualquier usuario con sesión).
        app.MapPost("/api/v1/dispositivos", async (DispositivoRequest r, IDispositivosService s, CancellationToken ct) =>
                (await s.RegistrarAsync(r, ct)).ToHttp())
            .WithTags("Avisos").RequireAuthorization().RequireRateLimiting(Limites.Usuario);

        // El maestro guía pone la conducta (A–E) de su sección en cada parcial.
        app.MapGet("/api/v1/mi-centro/secciones/{id:guid}/conducta", async (Guid id, int? parcial, IHorarioService s, CancellationToken ct) =>
                (await s.ConductaAsync(id, parcial ?? 1, ct)).ToHttp())
            .WithTags("Centro").RequireAuthorization(Policies.DocenteOnly).RequireRateLimiting(Limites.Usuario);
        app.MapPut("/api/v1/mi-centro/secciones/{id:guid}/conducta", async (Guid id, ConductaRequest r, IHorarioService s, CancellationToken ct) =>
                (await s.GuardarConductaAsync(id, r, ct)).ToHttp())
            .WithTags("Centro").RequireAuthorization(Policies.DocenteOnly).RequireRateLimiting(Limites.Usuario);

        // Excusas del día de los alumnos del docente, para marcarlos al pasar lista.
        app.MapGet("/api/v1/mi-centro/excusas", async (DateOnly? fecha, IConvivenciaService s, IClock clock, CancellationToken ct) =>
                Results.Ok(await s.ExcusasDelDocenteAsync(fecha ?? clock.Today, ct)))
            .WithTags("Centro").RequireAuthorization(Policies.DocenteOnly).RequireRateLimiting(Limites.Usuario);

        // El docente ve lo que su centro le asignó.
        app.MapGet("/api/v1/mi-centro/carga", async (IMiCargaService s, CancellationToken ct) => Results.Ok(await s.ObtenerAsync(ct)))
            .WithTags("Centro").RequireAuthorization(Policies.DocenteOnly).RequireRateLimiting(Limites.Usuario)
            .WithSummary("Secciones del año actual donde el docente da clase o es guía, con su lista de matrícula.");

        // Padres: sus hijos vinculados, su avance y los comunicados del centro.
        var padres = app.MapGroup("/api/v1/padres").WithTags("Padres").RequireAuthorization(Policies.PadreOnly)
            .RequireRateLimiting(Limites.Usuario);
        padres.MapGet("/hijos", async (IPadresService s, CancellationToken ct) => Results.Ok(await s.HijosAsync(ct)));
        padres.MapPost("/vincular", async (CodigoRequest r, IPadresService s, CancellationToken ct) => (await s.VincularAsync(r, ct)).ToHttp())
            .RequireRateLimiting(Limites.Sensible)
            .WithSummary("Agrega otro hijo con el código que dio el centro.");
        padres.MapGet("/hijos/{id:guid}", async (Guid id, IPadresService s, CancellationToken ct) => (await s.ResumenAsync(id, ct)).ToHttp())
            .WithSummary("Notas por asignatura y parcial, asistencia y próximas entregas del hijo.");
        padres.MapGet("/comunicados", async (IPadresService s, CancellationToken ct) => Results.Ok(await s.ComunicadosAsync(ct)));
        padres.MapPost("/comunicados/{id:guid}/leido", async (Guid id, IPadresService s, CancellationToken ct) =>
            (await s.MarcarLeidoAsync(id, ct)).ToHttp());

        var plataforma = app.MapGroup("/api/v1/plataforma").WithTags("Plataforma").RequireAuthorization(Policies.PlatformOnly)
            .RequireRateLimiting(Limites.Usuario);

        plataforma.MapGet("/instituciones", async (IPlataformaService s, CancellationToken ct) =>
            (await s.InstitucionesAsync(ct)).ToHttp());
        plataforma.MapPost("/instituciones", async (CrearInstitucionRequest r, IPlataformaService s, CancellationToken ct) =>
                (await s.CrearInstitucionAsync(r, ct)).ToHttp())
            .WithSummary("Crea un centro con licencia y su administrador.");
        plataforma.MapPut("/instituciones/{id:guid}", async (Guid id, ActualizarInstitucionRequest r, IPlataformaService s, CancellationToken ct) =>
            (await s.ActualizarInstitucionAsync(id, r, ct)).ToHttp());
        plataforma.MapPost("/docentes", async (CrearDocenteRequest r, IPlataformaService s, CancellationToken ct) =>
                (await s.CrearDocentePersonalAsync(r, ct)).ToHttp())
            .WithSummary("Cuenta de docente del plan personal, con contraseña temporal.");
        plataforma.MapGet("/docentes", async (string? buscar, int? pagina, IPlataformaService s, CancellationToken ct) =>
                (await s.DocentesAsync(buscar, pagina ?? 0, ct)).ToHttp())
            .WithSummary("Docentes del plan personal, por páginas, con su cobro.");

        // Cobro: lo mismo para un docente (por su usuario) que para un centro.
        foreach (var (ruta, tipo) in new[] { ("docentes", TipoCuenta.Docente), ("instituciones", TipoCuenta.Centro) })
        {
            plataforma.MapPut($"/{ruta}/{{id:guid}}/plan", async (Guid id, PlanCobroRequest r, IPlataformaService s, CancellationToken ct) =>
                (await s.FijarPlanAsync(tipo, id, r, ct)).ToHttp());
            plataforma.MapPost($"/{ruta}/{{id:guid}}/pagos", async (Guid id, RegistrarPagoRequest r, IPlataformaService s, CancellationToken ct) =>
                    (await s.RegistrarPagoAsync(tipo, id, r, ct)).ToHttp())
                .WithSummary("Anota un pago y corre el vencimiento.");
            plataforma.MapGet($"/{ruta}/{{id:guid}}/pagos", async (Guid id, IPlataformaService s, CancellationToken ct) =>
                (await s.PagosAsync(tipo, id, ct)).ToHttp());
            plataforma.MapPost($"/{ruta}/{{id:guid}}/suspender", async (Guid id, IPlataformaService s, CancellationToken ct) =>
                (await s.CambiarEstadoAsync(tipo, id, false, ct)).ToHttp());
            plataforma.MapPost($"/{ruta}/{{id:guid}}/reactivar", async (Guid id, IPlataformaService s, CancellationToken ct) =>
                (await s.CambiarEstadoAsync(tipo, id, true, ct)).ToHttp());
            plataforma.MapPost($"/{ruta}/{{id:guid}}/reponer-clave", async (Guid id, IPlataformaService s, CancellationToken ct) =>
                (await s.ReponerClaveAsync(tipo, id, ct)).ToHttp());
        }
    }
}
