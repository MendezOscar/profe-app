using NPOI.HSSF.UserModel;
using NPOI.SS.UserModel;
using NPOI.XSSF.UserModel;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;

namespace ProfeApp.Infrastructure.Sace;

/// <summary>
/// Rellena el cuadro de SACE con lo capturado. Sólo toca las celdas pedidas y sólo con
/// números: el nombre de la hoja (que parece ser el id de la clase en SACE), los estilos,
/// las combinaciones y todo lo demás quedan como vinieron. Ver docs/formato-sace.md.
/// </summary>
public sealed class CuadroSaceWriter : ICuadroSaceWriter
{
    // Un cuadro real pesa ~30 KB y tiene unos 40 alumnos por 9 columnas.
    private const int MaxBytes = 5 * 1024 * 1024;
    private const int MaxCeldas = 20_000;
    private const int MaxValor = 9_999;

    public Result<CuadroExportado> Rellenar(ExportarCuadroRequest request)
    {
        if (request.Celdas is null || string.IsNullOrWhiteSpace(request.Hoja) || request.ArchivoBase64 is null)
            return Fail("Faltan datos del cuadro.");

        byte[] original;
        try
        {
            original = Convert.FromBase64String(request.ArchivoBase64);
        }
        catch (FormatException)
        {
            return Fail("El archivo no llegó completo.");
        }

        if (original.Length is 0 or > MaxBytes) return Fail("El archivo está vacío o es demasiado grande.");
        if (request.Celdas.Count > MaxCeldas) return Fail("Demasiadas celdas para un cuadro de notas.");
        if (request.Celdas.Any(c => c.Fila < 0 || c.Col < 0 || c.Valor is < 0 or > MaxValor))
            return Fail("Hay celdas o valores fuera de rango.");

        var esXls = original.Length > 4 && original[0] == 0xD0 && original[1] == 0xCF;
        var esXlsx = original.Length > 4 && original[0] == 0x50 && original[1] == 0x4B;
        if (!esXls && !esXlsx) return Fail("El archivo no es un cuadro de Excel.");

        IWorkbook workbook;
        try
        {
            using var input = new MemoryStream(original);
            workbook = esXls ? new HSSFWorkbook(input) : new XSSFWorkbook(input);
        }
        catch (Exception)
        {
            return Fail("No se pudo abrir el archivo: puede estar dañado.");
        }

        var sheet = workbook.GetSheet(request.Hoja);
        if (sheet is null) return Fail("El archivo no tiene la hoja del cuadro. ¿Es el mismo que se importó?");

        foreach (var celda in request.Celdas)
        {
            var row = sheet.GetRow(celda.Fila) ?? sheet.CreateRow(celda.Fila);
            var cell = row.GetCell(celda.Col) ?? row.CreateCell(celda.Col);
            // Sobre la celda existente, para conservar el estilo que le dio SACE.
            if (celda.Valor is { } valor) cell.SetCellValue(valor);
            else cell.SetCellType(CellType.Blank);
        }

        using var output = new MemoryStream();
        workbook.Write(output, true);
        return new CuadroExportado(
            output.ToArray(),
            request.NombreArchivo,
            esXls ? "application/vnd.ms-excel" : "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
    }

    private static Result<CuadroExportado> Fail(string message) =>
        Result<CuadroExportado>.Fail(Error.Validation(message, "cuadro_invalido"));
}
