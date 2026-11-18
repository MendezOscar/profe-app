using ProfeApp.Application.Contracts;

namespace ProfeApp.Application.Abstractions;

/// <summary>Lo que el centro le asignó al docente que llama.</summary>
public interface IMiCargaService
{
    Task<MiCargaDto> ObtenerAsync(CancellationToken ct = default);
}
