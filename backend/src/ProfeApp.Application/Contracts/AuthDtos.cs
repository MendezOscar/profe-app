namespace ProfeApp.Application.Contracts;

/// <summary>Alta del docente. Crea su espacio (tenant) y lo deja con sesión iniciada.</summary>
public sealed record RegisterRequest(string Email, string Password, string FullName, string? DeviceName = null);
public sealed record LoginRequest(string Email, string Password, string? DeviceName = null);
public sealed record RefreshRequest(string RefreshToken);

public sealed record AuthTokens(
    string AccessToken,
    DateTimeOffset AccessTokenExpiresAt,
    string RefreshToken,
    DateTimeOffset RefreshTokenExpiresAt);

public sealed record CurrentUserDto(
    Guid UserId,
    string Email,
    string FullName,
    string Role,
    Guid? TenantId,
    bool MustChangePassword);

public sealed record AuthResponse(AuthTokens Tokens, CurrentUserDto User);

/// <summary><c>RefreshToken</c>: el de este dispositivo, que sigue con sesión; los demás se cierran.</summary>
public sealed record ChangePasswordRequest(string CurrentPassword, string NewPassword, string? RefreshToken = null);

/// <summary>Se pide la contraseña para que un teléfono prestado no pueda borrar la cuenta.</summary>
public sealed record DeleteAccountRequest(string Password);
