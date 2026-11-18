namespace ProfeApp.Application.Contracts;

/// <summary>Reportes del año actual del centro: matrícula, rendimiento, riesgo y asistencia.</summary>
public sealed record ReportesDto(
    int? Anio, MatriculaReporteDto Matricula, IReadOnlyList<RendimientoSeccionDto> Rendimiento,
    IReadOnlyList<AlumnoRiesgoDto> Riesgo, IReadOnlyList<AsistenciaSeccionDto> Asistencia);

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
