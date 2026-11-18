namespace ProfeApp.Application.Contracts;

/// <summary>Logo, color y lema del centro para el carnet.</summary>
public sealed record MarcaCentroDto(string Color, string? Lema, bool TieneLogo);

public sealed record MarcaRequest(string? Color, string? Lema);

/// <summary>Imagen en base64 (sin el prefijo data:).</summary>
public sealed record ImagenRequest(string? Base64);

/// <summary>Todo lo que lleva un juego de carnets; imágenes en base64.</summary>
public sealed record CarnetsDto(string Centro, string Color, string? Lema, string? Logo, int Anio, IReadOnlyList<CarnetAlumnoDto> Alumnos);

public sealed record CarnetAlumnoDto(Guid AlumnoId, string Nombre, string Identidad, string Seccion, string Jornada, string? Foto);
