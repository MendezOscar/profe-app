namespace ProfeApp.Application.Contracts;

/// <summary>Reportes del año actual del centro: matrícula, rendimiento, riesgo y asistencia.</summary>
public sealed record ReportesDto(
    int? Anio, MatriculaReporteDto Matricula, IReadOnlyList<RendimientoSeccionDto> Rendimiento,
    IReadOnlyList<AlumnoRiesgoDto> Riesgo, IReadOnlyList<AsistenciaSeccionDto> Asistencia,
    ConvivenciaReporteDto? Convivencia = null);

/// <summary>Incidencias del año por gravedad y por sección (de la sección donde ocurrieron), y excusas registradas.</summary>
public sealed record ConvivenciaReporteDto(int Leves, int Graves, int MuyGraves, int Abiertas, int Excusas, IReadOnlyList<ConvivenciaSeccionDto> PorSeccion);

public sealed record ConvivenciaSeccionDto(string Seccion, int Leves, int Graves, int MuyGraves);

/// <summary>Movimientos del año y matrícula activa por sección, sexo y edad (sin dato si la ficha no lo tiene).</summary>
public sealed record MatriculaReporteDto(
    int Activos, int Nuevos, int Reingresos, int TrasladosEntrantes, int Retirados, int Trasladados,
    IReadOnlyList<MatriculaSeccionDto> PorSeccion, IReadOnlyList<ConteoEdadDto> PorEdad);

public sealed record MatriculaSeccionDto(
    Guid SeccionId, string Seccion, string Jornada, int Activos, int Femenino, int Masculino, int SinSexo,
    int? Cupo, int Retirados, int Trasladados);

/// <summary><c>Edad</c> null = sin fecha de nacimiento.</summary>
public sealed record ConteoEdadDto(int? Edad, int Alumnos);

public sealed record RendimientoSeccionDto(Guid SeccionId, string Seccion, IReadOnlyList<RendimientoAsignaturaDto> Asignaturas);

/// <summary>
/// Con lo cerrado hasta hoy: la final si ya la hay, si no el promedio de los parciales
/// cerrados. <c>Aprobados</c>: cuántos llegan a la nota mínima.
/// </summary>
public sealed record RendimientoAsignaturaDto(string Asignatura, string Docente, int Evaluados, int Aprobados, decimal? Promedio);

public sealed record AlumnoRiesgoDto(Guid AlumnoId, string Nombre, string Seccion, IReadOnlyList<string> Motivos);

/// <summary>De la lista del día: porcentaje de asistencia (tardes cuentan como presentes).</summary>
public sealed record AsistenciaSeccionDto(Guid SeccionId, string Seccion, int Dias, int Ausencias, int Tardes, int Justificadas, decimal? Porcentaje);

/// <summary>
/// Estadísticas de cada docente del centro en el año actual. <c>DiasHabiles</c>: de lunes a
/// viernes desde el inicio del año hasta hoy, para comparar la lista del día.
/// </summary>
public sealed record EstadisticasDocentesDto(int? Anio, int DiasHabiles, IReadOnlyList<EstadisticaDocenteDto> Docentes);

/// <summary>
/// <c>CuadrosEnApp</c>: asignaturas que importó. <c>ListasRecientes</c>: listas de clase de los
/// últimos 30 días. <c>DiasListaDelDia</c>: días con lista en las secciones donde es guía (null si no
/// es guía). <c>Evaluados</c>/<c>Aprobados</c>/<c>Promedio</c>: de sus asignaturas, con lo cerrado.
/// </summary>
public sealed record EstadisticaDocenteDto(
    Guid Id, string Nombre, bool Activo, DateTimeOffset? UltimoAcceso, DateTimeOffset? UltimoTrabajo,
    int Secciones, int AsignaturasCarga, int Alumnos, int CuadrosEnApp, int ParcialesCerrados, int Actividades,
    int ListasRecientes, int SeccionesGuia, int? DiasListaDelDia, int ConductasPuestas, int Incidencias,
    int Evaluados, int Aprobados, decimal? Promedio);

// ── Tablero (primera pantalla del panel) ─────────────────────────────────────

/// <summary>Lo de hoy y lo pendiente del centro, con consultas livianas (sin consolidado).</summary>
public sealed record TableroDto(
    int? Anio, int DiasHabilesTranscurridos, int DiasHabilesAnio,
    int Alumnos, int Secciones, int Docentes, int MaxDocentes, int FamiliasConCuenta,
    HoyDto Hoy, IReadOnlyList<DiaAsistenciaDto> Tendencia,
    int IncidenciasAbiertas, IReadOnlyList<IncidenciaDto> IncidenciasRecientes,
    IReadOnlyList<DocenteInactivoDto> DocentesSinActividad, int ComunicadosMes);

/// <summary>Lista del día de hoy: cuántas secciones (con guía) la pasaron, quién faltó y excusas vigentes.</summary>
public sealed record HoyDto(
    DateOnly Fecha, int SeccionesConGuia, int SeccionesConLista, int Ausentes, int Tardes,
    IReadOnlyList<FaltaHoyDto> Faltas, int Excusas);

public sealed record FaltaHoyDto(Guid AlumnoId, string Nombre, string Seccion, string Estado);

/// <summary>Asistencia de la lista del día en un día con lista (tardes cuentan como presentes).</summary>
public sealed record DiaAsistenciaDto(DateOnly Fecha, int Secciones, decimal Porcentaje);

/// <summary><c>UltimoTrabajo</c> null: nunca respaldó nada.</summary>
public sealed record DocenteInactivoDto(Guid Id, string Nombre, DateTimeOffset? UltimoTrabajo);
