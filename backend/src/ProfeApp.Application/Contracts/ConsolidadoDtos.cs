namespace ProfeApp.Application.Contracts;

/// <summary>
/// Cuadro de la sección con todas sus asignaturas, armado con lo que cada docente cerró en
/// su cuadro de SACE. Reglas: aprueba con <c>NotaMinima</c>; la nivelación se suma al
/// parcial; la final es el promedio redondeado de los parciales; con final menor a la mínima
/// toca recuperación.
/// </summary>
public sealed record ConsolidadoDto(
    Guid SeccionId, string Seccion, string Jornada, string Centro, int Anio, int NotaMinima,
    IReadOnlyList<AsignaturaConsolidadoDto> Asignaturas, IReadOnlyList<AlumnoConsolidadoDto> Alumnos);

public sealed record AsignaturaConsolidadoDto(Guid ClaseId, string Nombre, string Docente, IReadOnlyList<string> Parciales, bool ConArchivo);

/// <summary><c>Notas</c> va en el orden de las asignaturas; null si el alumno no está en esa lista.</summary>
/// <summary><c>Conducta</c>: la del maestro guía en los parciales I a IV (null si falta).</summary>
public sealed record AlumnoConsolidadoDto(
    Guid AlumnoId, string Identidad, string Nombre, string EstadoMatricula,
    IReadOnlyList<NotaAsignaturaDto?> Notas, string Resultado, IReadOnlyList<string?>? Conducta = null);

/// <summary>
/// <c>Parciales</c>: nota de cada parcial ya con nivelación (null si falta). <c>Estado</c>:
/// en_curso, aprobada, recuperacion o reprobada.
/// </summary>
public sealed record NotaAsignaturaDto(IReadOnlyList<int?> Parciales, int? Final, int? Recuperacion, int Inasistencias, string Estado);
