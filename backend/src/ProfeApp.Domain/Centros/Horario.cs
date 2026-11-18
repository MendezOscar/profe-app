using ProfeApp.Domain.Common;

namespace ProfeApp.Domain.Centros;

/// <summary>Período de clase (o receso) de una jornada: 1.ª hora de 7:00 a 7:45.</summary>
public class BloqueHorario : EntidadDeCentro
{
    public string Jornada { get; set; } = null!;
    public int Orden { get; set; }
    public TimeOnly Inicio { get; set; }
    public TimeOnly Fin { get; set; }
    public bool EsReceso { get; set; }
}

/// <summary>
/// Qué asignatura tiene una sección en un día y bloque. El docente sale de la carga
/// docente (si cambia la carga, cambia el horario); el aula, de la sección salvo que se indique otra.
/// </summary>
public class HorarioClase : EntidadDeCentro
{
    public Guid SeccionId { get; set; }

    /// <summary>1 = lunes … 6 = sábado.</summary>
    public int Dia { get; set; }

    public Guid BloqueId { get; set; }
    public Guid AsignaturaGradoId { get; set; }
    public Guid? AulaId { get; set; }
}

/// <summary>Lista del día de una sección, que pasa su maestro guía.</summary>
public class TomaAsistenciaDiaria : EntidadDeCentro
{
    public Guid SeccionId { get; set; }
    public DateOnly Fecha { get; set; }
    public Guid TomadaPor { get; set; }
    public DateTimeOffset TomadaEn { get; set; }
}

/// <summary>Falta de un alumno en la lista del día. Sin marca es presente. <c>Estado</c>: A, T o J.</summary>
public class MarcaAsistenciaDiaria : EntidadDeCentro
{
    public Guid TomaId { get; set; }
    public Guid AlumnoId { get; set; }
    public string Estado { get; set; } = null!;
}
