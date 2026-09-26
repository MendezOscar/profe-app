namespace ProfeApp.Application.Contracts;

/// <summary>
/// Una clase completa tal como viaja entre el teléfono y el servidor. El archivo sólo va
/// cuando la plantilla cambió: es lo más pesado y casi nunca cambia.
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
    IReadOnlyList<ValorSync> Valores);

public sealed record ColumnaSync(string Clave, string Grupo, string Nombre, string Tipo, int Col, int Orden);

public sealed record AlumnoSync(string Clave, string Identidad, string Documento, string Nombre, int Fila, int Orden, bool Activo);

/// <summary>Valor null = la celda se borró.</summary>
public sealed record ValorSync(string AlumnoClave, string ColumnaClave, int? Valor, DateTimeOffset ActualizadoEn);

public sealed record SyncPushRequest(IReadOnlyList<ClaseSync> Clases);

/// <summary><c>Hasta</c> es el cursor para el próximo pull.</summary>
public sealed record SyncPullResponse(DateTimeOffset Hasta, IReadOnlyList<ClaseSync> Clases);
