using System.Collections.Concurrent;
using System.Globalization;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Contracts;

namespace ProfeApp.Infrastructure.Programas;

/// <summary>
/// Programas curriculares oficiales de la Secretaría de Educación, ya leídos de sus PDF
/// (scripts/programas): de Media, por carrera, cada espacio curricular con sus resultados de
/// aprendizaje (RA), criterios de evaluación (CE) y contenidos; de Básica (1.° a 9.°), el texto
/// de cada mes por área. Vienen dentro del ensamblado, comprimidos, y cada carrera se carga la
/// primera vez que alguien la pide.
/// </summary>
public sealed partial class ProgramasCurriculares : IProgramasCurriculares
{
    private static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true };
    private static readonly string[] Meses = ["Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre"];

    /// <summary>Meses de cada parcial en el calendario escolar de Honduras (febrero a noviembre).</summary>
    private static readonly Dictionary<string, string[]> MesesParcial = new()
    {
        ["I"] = ["Febrero", "Marzo", "Abril"],
        ["II"] = ["Mayo", "Junio"],
        ["III"] = ["Julio", "Agosto"],
        ["IV"] = ["Septiembre", "Octubre", "Noviembre"],
    };

    private readonly ConcurrentDictionary<string, Carrera> _carreras = new();
    private readonly Lazy<List<AreaBasica>> _basica = new(() => Leer<List<AreaBasica>>("basica.json.gz"));
    private readonly Lazy<Dictionary<string, string>> _recursos = new(() =>
        typeof(ProgramasCurriculares).Assembly.GetManifestResourceNames()
            .Where(n => n.Contains(".media-", StringComparison.Ordinal))
            .ToDictionary(n => n, n => n));

    public ProgramaDto? Buscar(string? modalidad, string? grado, string? asignatura)
    {
        var encontrado = Encontrar(modalidad, grado, asignatura);
        return encontrado switch
        {
            { Carrera: { } c, Espacio: { } e } => new ProgramaDto(
                c.Nombre, e.Asignatura, e.Grado ?? 0, e.HorasSemana,
                e.Resultados.Select(r => new ResultadoProgramaDto(r.Codigo, r.Texto, r.Criterios.Count)).ToList(), []),
            { Basica: { } b } => new ProgramaDto(
                "Educación Básica", b.Area, b.Grado, null, [], b.Meses.Select(m => m.Mes).ToList()),
            _ => null,
        };
    }

    public string? Contexto(string? modalidad, string? grado, string? asignatura, string? parcial, IReadOnlyList<string>? resultados)
    {
        var encontrado = Encontrar(modalidad, grado, asignatura);
        var sb = new StringBuilder();
        switch (encontrado)
        {
            case { Carrera: { } c, Espacio: { } e }:
            {
                var elegidos = (resultados ?? []).ToHashSet(StringComparer.OrdinalIgnoreCase);
                var ras = e.Resultados.Where(r => elegidos.Count == 0 || elegidos.Contains(r.Codigo)).ToList();
                if (ras.Count == 0) return null;
                sb.AppendLine($"Programa oficial de la Secretaría de Educación: {e.Asignatura}, {e.Grado}.° grado, " +
                              $"{(c.Nombre == "Ciencias y Humanidades" ? "Bachillerato en Ciencias y Humanidades" : $"BTP en {c.Nombre}")}" +
                              (e.HorasSemana is { } h ? $", {h} horas de clase por semana." : "."));
                if (e.Competencias.Count > 0) sb.AppendLine("Competencias: " + string.Join(" ", e.Competencias.Take(3)));
                sb.AppendLine("Resultados de aprendizaje de este parcial, con sus criterios de evaluación y contenidos:");
                foreach (var r in ras)
                {
                    sb.AppendLine($"{r.Codigo}. {r.Texto}");
                    foreach (var ce in r.Criterios) sb.AppendLine($"  {ce.Codigo}. {ce.Texto}");
                    if (r.Conceptuales.Count > 0) sb.AppendLine("  Contenidos conceptuales: " + string.Join("; ", r.Conceptuales));
                    if (r.Procedimentales.Count > 0) sb.AppendLine("  Contenidos procedimentales: " + string.Join("; ", r.Procedimentales));
                }
                if (e.Actitudinales.Count > 0) sb.AppendLine("Contenidos actitudinales: " + string.Join("; ", e.Actitudinales.Take(8)));
                if (e.Actividades.Count > 0) sb.AppendLine("Actividades sugeridas por el programa: " + string.Join("; ", e.Actividades.Take(10)));
                break;
            }
            case { Basica: { } b }:
            {
                var meses = MesesParcial.GetValueOrDefault(Romano(parcial) ?? "") ?? Meses;
                var texto = string.Join("\n", b.Meses.Where(m => meses.Contains(m.Mes)).Select(m => $"{m.Mes}: {m.Texto}"));
                if (texto.Length == 0) return null;
                sb.AppendLine($"Programación oficial de la Secretaría de Educación: {b.Area}, {b.Grado}.° grado, meses de este parcial " +
                              $"({string.Join(", ", meses).ToLowerInvariant()}). Viene de un PDF a dos columnas, así que " +
                              "estándares y contenidos pueden estar mezclados; los números sueltos son lecciones del libro del docente:");
                sb.AppendLine(texto);
                break;
            }
            default:
                return null;
        }
        var contexto = sb.ToString();
        return contexto.Length > 9000 ? contexto[..9000] : contexto;
    }

    // ── Búsqueda ─────────────────────────────────────────────────────────────

    private Hallazgo? Encontrar(string? modalidad, string? grado, string? asignatura)
    {
        var n = GradoDe(grado);
        if (n is null || string.IsNullOrWhiteSpace(asignatura)) return null;
        if (n <= 9)
        {
            var area = AreaDe(asignatura);
            var b = area is null ? null : _basica.Value.FirstOrDefault(x => x.Area == area && x.Grado == n);
            return b is null ? null : new Hallazgo(null, null, b);
        }
        var carrera = CarreraDe(modalidad);
        if (carrera is null) return null;
        var mejor = carrera.Espacios
            .Where(e => e.Grado == n)
            .Select(e => (e, p: Math.Max(Parecido(asignatura, e.Asignatura), Parecido(asignatura, e.AsignaturaPlan ?? ""))))
            .OrderByDescending(x => x.p)
            .FirstOrDefault();
        return mejor.e is not null && mejor.p >= 0.8 ? new Hallazgo(carrera, mejor.e, null) : null;
    }

    private Carrera? CarreraDe(string? modalidad)
    {
        if (string.IsNullOrWhiteSpace(modalidad)) return null;
        var m = Prefijo().Replace(Plano(modalidad), "").Trim();
        if (m.Length == 0 || m == "NO APLICA") return null;
        var mejor = _recursos.Value.Keys
            .Select(r => (r, p: Parecido(m, Regex.Replace(r[(r.IndexOf(".media-", StringComparison.Ordinal) + 7)..^8], "-", " "))))
            .OrderByDescending(x => x.p)
            .FirstOrDefault();
        if (mejor.r is null || mejor.p < 0.75) return null;
        return _carreras.GetOrAdd(mejor.r, r => LeerRecurso<Carrera>(r));
    }

    private static string? AreaDe(string asignatura)
    {
        var a = Plano(asignatura);
        if (a.Contains("ESPANOL")) return "Español";
        if (a.Contains("MATEMATICA")) return "Matemáticas";
        if (a.Contains("NATURALES")) return "Ciencias Naturales";
        if (a.Contains("SOCIALES")) return "Ciencias Sociales";
        return null;
    }

    /// <summary>«ONCEAVO GRADO SECCIÓN 12» → 11.</summary>
    internal static int? GradoDe(string? grado)
    {
        var g = Plano(grado ?? "");
        (string, int)[] nombres =
        [
            ("DUODECIMO", 12), ("DOCEAVO", 12), ("UNDECIMO", 11), ("ONCEAVO", 11), ("DECIMO", 10), ("NOVENO", 9),
            ("OCTAVO", 8), ("SEPTIMO", 7), ("SEXTO", 6), ("QUINTO", 5), ("CUARTO", 4), ("TERCER", 3), ("SEGUNDO", 2), ("PRIMER", 1),
        ];
        foreach (var (nombre, n) in nombres)
            if (g.Contains(nombre)) return n;
        var m = Regex.Match(g, @"(\d+)\s*(GRADO)");
        return m.Success ? int.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture) : null;
    }

    /// <summary>«PARCIAL III» → «III».</summary>
    private static string? Romano(string? parcial) =>
        Regex.Match(Plano(parcial ?? ""), @"\b(IV|III|II|I)\b") is { Success: true } m ? m.Value : null;

    internal static string Plano(string t)
    {
        var sb = new StringBuilder();
        foreach (var c in t.ToUpperInvariant().Normalize(NormalizationForm.FormD))
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark)
                sb.Append(char.IsLetterOrDigit(c) ? c : ' ');
        return Espacios().Replace(sb.ToString(), " ").Trim();
    }

    /// <summary>1 si son iguales; 0.9 si uno contiene al otro (y no es mucho más corto); si no, por letras.</summary>
    internal static double Parecido(string a, string b)
    {
        a = Plano(a);
        b = Plano(b);
        if (a.Length == 0 || b.Length == 0) return 0;
        if (a == b) return 1;
        var (corto, largo) = a.Length <= b.Length ? (a, b) : (b, a);
        if ($" {largo} ".Contains($" {corto} ") && corto.Length >= largo.Length * 0.5) return 0.9;
        return 1 - (double)Distancia(a, b) / Math.Max(a.Length, b.Length);
    }

    private static int Distancia(string a, string b)
    {
        var previa = Enumerable.Range(0, b.Length + 1).ToArray();
        for (var i = 1; i <= a.Length; i++)
        {
            var actual = new int[b.Length + 1];
            actual[0] = i;
            for (var j = 1; j <= b.Length; j++)
                actual[j] = Math.Min(Math.Min(actual[j - 1] + 1, previa[j] + 1), previa[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
            previa = actual;
        }
        return previa[b.Length];
    }

    private static T Leer<T>(string archivo) =>
        LeerRecurso<T>(typeof(ProgramasCurriculares).Assembly.GetManifestResourceNames().Single(n => n.EndsWith("." + archivo, StringComparison.Ordinal)));

    private static T LeerRecurso<T>(string recurso)
    {
        using var s = typeof(ProgramasCurriculares).Assembly.GetManifestResourceStream(recurso)!;
        using var gz = new GZipStream(s, CompressionMode.Decompress);
        return JsonSerializer.Deserialize<T>(gz, Json)!;
    }

    [GeneratedRegex(@"^(BACHILLERATO\s+)?(TECNICO\s+PROFESIONAL\s+)?(BTP\s+)?(EN\s+)?")]
    private static partial Regex Prefijo();

    [GeneratedRegex(@"\s+")]
    private static partial Regex Espacios();

    // ── Lo que hay en los archivos ───────────────────────────────────────────

    private sealed record Hallazgo(Carrera? Carrera, Espacio? Espacio, AreaBasica? Basica);

    private sealed record Carrera([property: JsonPropertyName("carrera")] string Nombre, List<Espacio> Espacios);

    private sealed record Espacio(
        string Asignatura, string? AsignaturaPlan, int? Grado, int? HorasSemana, List<string> Competencias,
        List<Resultado> Resultados, List<string> Actitudinales, List<string> Actividades);

    private sealed record Resultado(string Codigo, string Texto, List<Criterio> Criterios, List<string> Conceptuales, List<string> Procedimentales);

    private sealed record Criterio(string Codigo, string Texto);

    private sealed record AreaBasica(string Area, int Grado, List<MesBasica> Meses);

    private sealed record MesBasica(string Mes, string Texto);
}
