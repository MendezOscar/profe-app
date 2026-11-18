using System.Security.Cryptography;

namespace ProfeApp.Infrastructure.Centros;

/// <summary>
/// Códigos de familia: 8 caracteres sin los que se confunden (0/O, 1/I/L), fáciles de dictar.
/// 31^8 combinaciones y la redención va con límite por IP: no se adivinan.
/// </summary>
internal static class CodigosFamilia
{
    private const string Letras = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
    public static readonly TimeSpan Vigencia = TimeSpan.FromDays(30);
    public const int MaxCuentasPorAlumno = 4;

    public static string Generar() =>
        new(Enumerable.Range(0, 8).Select(_ => Letras[RandomNumberGenerator.GetInt32(Letras.Length)]).ToArray());

    /// <summary>"abcd-2345" → "ABCD2345".</summary>
    public static string Normalizar(string? codigo) =>
        new((codigo ?? "").Where(char.IsLetterOrDigit).Select(char.ToUpperInvariant).Take(12).ToArray());

    public static string Mostrar(string codigo) => codigo.Length == 8 ? $"{codigo[..4]}-{codigo[4..]}" : codigo;
}
