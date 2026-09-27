using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;

namespace ProfeApp.Application.Abstractions;

public interface IAuthService
{
    Task<Result<AuthResponse>> RegisterAsync(RegisterRequest request, string? ip, CancellationToken ct = default);
    Task<Result<AuthResponse>> LoginAsync(LoginRequest request, string? ip, CancellationToken ct = default);
    Task<Result<AuthResponse>> RefreshAsync(RefreshRequest request, string? ip, CancellationToken ct = default);
    Task<Result> LogoutAsync(string refreshToken, CancellationToken ct = default);
    Task<Result<CurrentUserDto>> GetCurrentAsync(CancellationToken ct = default);
    Task<Result> ChangePasswordAsync(ChangePasswordRequest request, CancellationToken ct = default);
    Task<Result> DeleteAccountAsync(DeleteAccountRequest request, CancellationToken ct = default);
}
