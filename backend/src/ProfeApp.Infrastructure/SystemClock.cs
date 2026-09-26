using Microsoft.Extensions.Options;
using ProfeApp.Application.Abstractions;

namespace ProfeApp.Infrastructure;

public sealed class ClockOptions
{
    public const string Section = "App";
    /// <summary>Zona del centro educativo: define qué es "hoy" para la asistencia.</summary>
    public string TimeZone { get; set; } = "America/Tegucigalpa";
}

public sealed class SystemClock(IOptions<ClockOptions> options) : IClock
{
    private readonly TimeZoneInfo _zone = Resolve(options.Value.TimeZone);

    public DateTimeOffset Now => DateTimeOffset.UtcNow;

    /// <summary>"Hoy" en Honduras: a las 19:00 no debe saltar al día siguiente como en UTC.</summary>
    public DateOnly Today => DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(DateTimeOffset.UtcNow, _zone).Date);

    private static TimeZoneInfo Resolve(string id)
    {
        try { return TimeZoneInfo.FindSystemTimeZoneById(id); }
        catch (TimeZoneNotFoundException) { return TimeZoneInfo.Utc; }
    }
}
