using ProfeApp.Domain.Common;

namespace ProfeApp.Domain.Cuadros;

/// <summary>
/// Respaldo en el servidor de una clase del teléfono: el cuadro de SACE más lo capturado.
/// El teléfono es la fuente de verdad; esto sirve para no perder nada y para usar otro
/// dispositivo. Todo se identifica por claves naturales (la de la clase, la identidad del
/// alumno, el encabezado de la columna), no por los id de cada teléfono.
/// </summary>
public class Clase : TenantEntity
{
    public string Clave { get; set; } = null!;
    public string? CodigoCentro { get; set; }
    public string? Centro { get; set; }
    public string? Modalidad { get; set; }
    public string? GradoSeccion { get; set; }
    public string? Jornada { get; set; }
    public string? Asignatura { get; set; }

    public string Hoja { get; set; } = null!;
    public string ArchivoNombre { get; set; } = null!;

    /// <summary>
    /// El archivo original, aparte: comparte la tabla pero no se lee al cargar la clase.
    /// Es lo más pesado y sólo hace falta al exportar o al bajarlo a otro dispositivo.
    /// </summary>
    public ClaseArchivo Archivo { get; set; } = new();

    /// <summary>Cuándo se importó la plantilla en el teléfono. Gana la más nueva.</summary>
    public DateTimeOffset PlantillaActualizadaEn { get; set; }

    /// <summary>Hora del servidor del último cambio a la plantilla: decide si el pull manda el archivo.</summary>
    public DateTimeOffset PlantillaModificadaEn { get; set; }

    /// <summary>Hora del servidor del último cambio de cualquier tipo: es el cursor del pull.</summary>
    public DateTimeOffset ModificadoEn { get; set; }

    /// <summary>
    /// Se conserva la fila como lápida para que los otros dispositivos se enteren del
    /// borrado; el archivo y los alumnos sí se eliminan.
    /// </summary>
    public DateTimeOffset? EliminadaEn { get; set; }

    public List<ClaseColumna> Columnas { get; set; } = [];
    public List<ClaseAlumno> Alumnos { get; set; } = [];
    public List<ClaseValor> Valores { get; set; } = [];
}

/// <summary>El cuadro de SACE tal como se importó. Misma fila que su <see cref="Clase"/>.</summary>
public class ClaseArchivo
{
    public Guid Id { get; set; }
    public byte[] Contenido { get; set; } = [];
}

public class ClaseColumna : TenantEntity
{
    public Guid ClaseId { get; set; }
    public string Clave { get; set; } = null!;
    public string Grupo { get; set; } = null!;
    public string Nombre { get; set; } = null!;
    public string Tipo { get; set; } = null!;
    public int Col { get; set; }
    public int Orden { get; set; }
}

public class ClaseAlumno : TenantEntity
{
    public Guid ClaseId { get; set; }
    public string Clave { get; set; } = null!;
    public string Identidad { get; set; } = null!;
    public string Documento { get; set; } = null!;
    public string Nombre { get; set; } = null!;
    public int Fila { get; set; }
    public int Orden { get; set; }
    public bool Activo { get; set; } = true;
}

/// <summary>Una celda capturada. Valor null es un borrado que también hay que propagar.</summary>
public class ClaseValor : TenantEntity
{
    public Guid ClaseId { get; set; }
    public string AlumnoClave { get; set; } = null!;
    public string ColumnaClave { get; set; } = null!;
    public int? Valor { get; set; }

    /// <summary>Hora del teléfono en que se capturó: entre dos dispositivos gana la más nueva.</summary>
    public DateTimeOffset ActualizadoEn { get; set; }

    /// <summary>Hora del servidor del último cambio: el pull sólo manda las celdas nuevas.</summary>
    public DateTimeOffset ModificadoEn { get; set; }
}
