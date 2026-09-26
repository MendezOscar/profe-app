namespace ProfeApp.Application.Contracts;

/// <summary>
/// El cuadro original de SACE más lo que el docente capturó. El servidor no guarda nada:
/// rellena el archivo y lo devuelve.
/// </summary>
public sealed record ExportarCuadroRequest(
    string ArchivoBase64,
    string NombreArchivo,
    string Hoja,
    IReadOnlyList<CeldaCuadro> Celdas);

/// <summary>Fila y columna en base 0, como las lee la app. Valor null deja la celda vacía.</summary>
public sealed record CeldaCuadro(int Fila, int Col, int? Valor);

public sealed record CuadroExportado(byte[] Contenido, string NombreArchivo, string ContentType);
