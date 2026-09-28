namespace ProfeApp.Application.Contracts;

/// <summary>
/// Una clase tal como viaja entre el teléfono y el servidor. Sólo va lo que cambió: las
/// columnas y alumnos cuando cambió la plantilla (<c>ConPlantilla</c>), y las celdas nuevas.
/// El archivo sube sólo con una plantilla nueva y se baja aparte, con <c>/sync/archivo</c>.
/// </summary>
public sealed record ClaseSync(
    string Clave,
    string? CodigoCentro,
    string? Centro,
    string? Modalidad,
    string? GradoSeccion,
    string? Jornada,
    string? Asignatura,
    string Hoja,
    string ArchivoNombre,
    string? ArchivoBase64,
    DateTimeOffset PlantillaActualizadaEn,
    bool Eliminada,
    IReadOnlyList<ColumnaSync> Columnas,
    IReadOnlyList<AlumnoSync> Alumnos,
    IReadOnlyList<ValorSync> Valores,
    bool ConPlantilla = true);

public sealed record ColumnaSync(string Clave, string Grupo, string Nombre, string Tipo, int Col, int Orden);

public sealed record AlumnoSync(string Clave, string Identidad, string Documento, string Nombre, int Fila, int Orden, bool Activo);

/// <summary>Valor null = la celda se borró.</summary>
public sealed record ValorSync(string AlumnoClave, string ColumnaClave, int? Valor, DateTimeOffset ActualizadoEn);

/// <summary>
/// Una fila del plan de calificación (ver <c>Registro</c>). <c>Datos</c> es JSON que el
/// servidor no interpreta.
/// </summary>
public sealed record RegistroSync(string Tipo, string ClaseClave, string Clave, string? Datos, bool Eliminado, DateTimeOffset ActualizadoEn);

/// <summary>Registros es opcional: las versiones de la app sin planes no lo mandan.</summary>
public sealed record SyncPushRequest(IReadOnlyList<ClaseSync>? Clases, IReadOnlyList<RegistroSync>? Registros = null);

/// <summary>
/// Una página del pull. <c>Hasta</c> es el cursor para el próximo pull; si <c>Mas</c>, se
/// pide la página siguiente con el mismo <c>desde</c> y este <c>hasta</c>. Las clases van
/// sólo en la primera página. <c>Siguiente</c> marca el último registro entregado: se manda
/// como <c>despues</c> para seguir sin que la base tenga que saltar filas.
/// </summary>
public sealed record SyncPullResponse(
    DateTimeOffset Hasta, IReadOnlyList<ClaseSync> Clases, IReadOnlyList<RegistroSync> Registros, bool Mas = false,
    string? Siguiente = null);

public sealed record ArchivoClase(string Clave, string ArchivoBase64);
