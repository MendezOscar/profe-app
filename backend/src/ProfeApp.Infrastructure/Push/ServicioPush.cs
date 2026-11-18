using System.Threading.Channels;
using FirebaseAdmin;
using FirebaseAdmin.Messaging;
using Google.Apis.Auth.OAuth2;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using ProfeApp.Application.Abstractions;
using ProfeApp.Infrastructure.Persistence;

namespace ProfeApp.Infrastructure.Push;

/// <summary>Cola en memoria: los avisos se mandan en segundo plano, fuera de la petición.</summary>
public sealed class ColaPush : IAvisosPush
{
    private readonly Channel<AvisoPush> _cola = Channel.CreateBounded<AvisoPush>(
        new BoundedChannelOptions(1000) { FullMode = BoundedChannelFullMode.DropOldest });

    public void Encolar(AvisoPush aviso)
    {
        if (aviso.Usuarios.Count > 0) _cola.Writer.TryWrite(aviso);
    }

    internal ChannelReader<AvisoPush> Lector => _cola.Reader;
}

/// <summary>Toma los avisos de la cola, busca los teléfonos de cada usuario y los manda.</summary>
public sealed class ServicioPush(ColaPush cola, IServiceScopeFactory scopes, IEnviadorPush enviador, ILogger<ServicioPush> log)
    : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        await foreach (var aviso in cola.Lector.ReadAllAsync(ct))
        {
            try
            {
                using var scope = scopes.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                var usuarios = aviso.Usuarios.Distinct().ToList();
                var tokens = await db.DispositivosPush.Where(d => usuarios.Contains(d.UsuarioId)).Select(d => d.Token).ToListAsync(ct);
                if (tokens.Count == 0) continue;
                var muertos = new List<string>();
                // FCM admite hasta 500 tokens por envío.
                foreach (var tanda in tokens.Chunk(500))
                    muertos.AddRange(await enviador.EnviarAsync(tanda, aviso.Titulo, aviso.Cuerpo, aviso.Ruta, ct));
                if (muertos.Count > 0)
                    await db.DispositivosPush.Where(d => muertos.Contains(d.Token)).ExecuteDeleteAsync(ct);
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                break;
            }
            catch (Exception e)
            {
                log.LogWarning(e, "No se pudo mandar un aviso al teléfono.");
            }
        }
    }
}

/// <summary>Envío por Firebase Cloud Messaging con la cuenta de servicio de Firebase:CredencialesJson.</summary>
public sealed class EnviadorFirebase : IEnviadorPush
{
    private readonly FirebaseMessaging? _mensajeria;

    public EnviadorFirebase(IConfiguration configuration, ILogger<EnviadorFirebase> log)
    {
        var json = configuration["Firebase:CredencialesJson"];
        if (string.IsNullOrWhiteSpace(json))
        {
            log.LogInformation("Sin Firebase:CredencialesJson: los avisos al teléfono quedan apagados.");
            return;
        }
        var app = FirebaseApp.DefaultInstance ?? FirebaseApp.Create(new AppOptions
        {
            Credential = CredentialFactory.FromJson<ServiceAccountCredential>(json).ToGoogleCredential(),
        });
        _mensajeria = FirebaseMessaging.GetMessaging(app);
    }

    public async Task<IReadOnlyList<string>> EnviarAsync(
        IReadOnlyList<string> tokens, string titulo, string cuerpo, string? ruta, CancellationToken ct)
    {
        if (_mensajeria is null) return [];
        var respuesta = await _mensajeria.SendEachForMulticastAsync(new MulticastMessage
        {
            Tokens = tokens,
            Notification = new Notification { Title = titulo, Body = cuerpo },
            Data = ruta is null ? null : new Dictionary<string, string> { ["ruta"] = ruta },
            Android = new AndroidConfig { Priority = Priority.High, Notification = new AndroidNotification { ChannelId = "familia" } },
            Apns = new ApnsConfig { Aps = new Aps { Sound = "default" } },
        }, ct);
        return respuesta.Responses
            .Select((r, i) => (r, i))
            .Where(x => x.r.Exception?.MessagingErrorCode is MessagingErrorCode.Unregistered or MessagingErrorCode.InvalidArgument)
            .Select(x => tokens[x.i])
            .ToList();
    }
}
