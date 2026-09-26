using System.Net;
using System.Net.Http.Json;
using NPOI.HSSF.UserModel;
using NPOI.SS.UserModel;
using NPOI.SS.Util;
using ProfeApp.IntegrationTests.Infrastructure;

namespace ProfeApp.IntegrationTests;

public class ExportarCuadroTests(ApiFixture fixture) : ApiTestBase(fixture)
{
    private const string Hoja = "12345678~1~1123";

    [Fact]
    public async Task Rellena_solo_las_celdas_pedidas_y_conserva_hoja_estilos_y_combinaciones()
    {
        var client = await LoginAsync();

        var response = await client.PostAsJsonAsync("/api/v1/cuadros/exportar", new
        {
            archivoBase64 = Convert.ToBase64String(CuadroDePrueba()),
            nombreArchivo = "QUIMICA_SECCION_2.xls",
            hoja = Hoja,
            celdas = new object[]
            {
                new { fila = 7, col = 3, valor = 2 },    // inasistencias, estaba vacía
                new { fila = 7, col = 4, valor = 88 },   // nota, estaba vacía
                new { fila = 8, col = 4, valor = (int?)null }, // el docente borró la nota
            }
        });

        response.StatusCode.Should().Be(HttpStatusCode.OK, await response.Content.ReadAsStringAsync());
        response.Content.Headers.ContentType!.MediaType.Should().Be("application/vnd.ms-excel");
        response.Content.Headers.ContentDisposition!.FileName.Should().Contain("QUIMICA_SECCION_2.xls");

        var workbook = new HSSFWorkbook(new MemoryStream(await response.Content.ReadAsByteArrayAsync()));
        workbook.NumberOfSheets.Should().Be(1);
        var sheet = workbook.GetSheet(Hoja);
        sheet.Should().NotBeNull("SACE parece reconocer la clase por el nombre de la hoja");

        sheet.GetRow(7).GetCell(3).NumericCellValue.Should().Be(2);
        sheet.GetRow(7).GetCell(4).NumericCellValue.Should().Be(88);
        sheet.GetRow(8).GetCell(4).CellType.Should().Be(CellType.Blank);

        // Lo que no se pidió queda igual: textos, la nota de otro alumno y el estilo de la celda.
        sheet.GetRow(5).GetCell(1).StringCellValue.Should().Be("IDENTIDAD");
        sheet.GetRow(8).GetCell(3).NumericCellValue.Should().Be(1);
        sheet.GetRow(7).GetCell(4).CellStyle.IsLocked.Should().BeFalse();
        sheet.NumMergedRegions.Should().Be(3);
    }

    [Fact]
    public async Task Un_archivo_que_no_es_Excel_se_rechaza()
    {
        var client = await LoginAsync();

        var response = await client.PostAsJsonAsync("/api/v1/cuadros/exportar", new
        {
            archivoBase64 = Convert.ToBase64String("no soy un excel"u8.ToArray()),
            nombreArchivo = "x.xls",
            hoja = Hoja,
            celdas = Array.Empty<object>()
        });

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Sin_sesion_no_se_exporta()
    {
        var response = await Fixture.CreateClient().PostAsJsonAsync("/api/v1/cuadros/exportar", new
        {
            archivoBase64 = Convert.ToBase64String(CuadroDePrueba()),
            nombreArchivo = "x.xls",
            hoja = Hoja,
            celdas = Array.Empty<object>()
        });

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    /// <summary>Un cuadro con la forma del de SACE: encabezados combinados y celdas de nota con estilo.</summary>
    private static byte[] CuadroDePrueba()
    {
        var workbook = new HSSFWorkbook();
        var sheet = workbook.CreateSheet(Hoja);
        var editable = workbook.CreateCellStyle();
        editable.IsLocked = false;

        sheet.CreateRow(0).CreateCell(0).SetCellValue("050100235M02 | INSTITUTO DE PRUEBA");
        sheet.AddMergedRegion(new CellRangeAddress(0, 0, 0, 14));
        var encabezado = sheet.CreateRow(5);
        encabezado.CreateCell(0).SetCellValue("DOCUMENTO");
        encabezado.CreateCell(1).SetCellValue("IDENTIDAD");
        encabezado.CreateCell(2).SetCellValue("NOMBRE");
        encabezado.CreateCell(3).SetCellValue("PARCIAL I");
        sheet.AddMergedRegion(new CellRangeAddress(5, 5, 3, 4));
        sheet.AddMergedRegion(new CellRangeAddress(5, 6, 1, 1));

        for (var fila = 7; fila <= 8; fila++)
        {
            var row = sheet.CreateRow(fila);
            row.CreateCell(0).SetCellValue("HND");
            row.CreateCell(1).SetCellValue($"050120090000{fila}");
            row.CreateCell(2).SetCellValue($"ALUMNO {fila}");
            foreach (var col in new[] { 3, 4 }) row.CreateCell(col).CellStyle = editable;
        }
        sheet.GetRow(8).GetCell(3).SetCellValue(1);
        sheet.GetRow(8).GetCell(4).SetCellValue(70);

        using var output = new MemoryStream();
        workbook.Write(output, true);
        return output.ToArray();
    }
}
