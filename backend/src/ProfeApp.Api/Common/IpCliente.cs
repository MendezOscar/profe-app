using System.Net;

namespace ProfeApp.Api.Common;

/// <summary>
/// La IP real de quien llama. Render pone a Cloudflare delante y Cloudflare escribe la IP del
/// cliente en CF-Connecting-IP, pisando la que el cliente mande. X-Forwarded-For no sirve:
/// su último valor es un nodo de la red de Render que cambia en cada petición (los límites
/// por IP nunca se llenaban) y el cliente puede inventar los demás.
/// Null en pruebas y llamadas locales: ahí no se limita.
/// </summary>
public static class IpCliente
{
    public static string? De(HttpContext http)
    {
        var cf = http.Request.Headers["CF-Connecting-IP"].ToString();
        if (cf.Length is > 0 and <= 45 && IPAddress.TryParse(cf, out var ip)) return ip.ToString();
        var remota = http.Connection.RemoteIpAddress;
        return remota is null || IPAddress.IsLoopback(remota) ? null : remota.ToString();
    }
}
