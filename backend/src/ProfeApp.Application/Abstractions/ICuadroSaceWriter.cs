using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;

namespace ProfeApp.Application.Abstractions;

public interface ICuadroSaceWriter
{
    Result<CuadroExportado> Rellenar(ExportarCuadroRequest request);
}
