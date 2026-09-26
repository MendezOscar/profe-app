using Microsoft.EntityFrameworkCore;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;
using System.Text.Json;
using ProfeApp.Domain.Cuadros;
using ProfeApp.Domain.Planes;

namespace ProfeApp.Application.Services;

/// <summary>
/// Respaldo y sincronización entre dispositivos del mismo docente. Cada celda se resuelve
/// por separado con "gana el cambio más nuevo", así dos teléfonos pueden capturar columnas
/// distintas de la misma clase sin pisarse. Todo es idempotente: reenviar lo mismo no
/// cambia nada, y la app puede reintentar sin miedo.
/// </summary>
public sealed class SyncService(IAppDbContext db, IClock clock)
{
    private const int MaxClasesPorPush = 50;
    private const int MaxArchivoBytes = 5 * 1024 * 1024;
    private const int MaxRegistrosPorPush = 2_000;

    public async Task<Result> PushAsync(SyncPushRequest request, CancellationToken ct = default)
    {
        var clases = request.Clases ?? [];
        var registros = request.Registros ?? [];
        if (clases.Count > MaxClasesPorPush)
            return Result.Fail(Error.Validation($"Se pueden enviar hasta {MaxClasesPorPush} clases por vez."));
        if (registros.Count > MaxRegistrosPorPush)
            return Result.Fail(Error.Validation($"Se pueden enviar hasta {MaxRegistrosPorPush} registros por vez."));

        foreach (var entrante in clases)
        {
            var error = await AplicarAsync(entrante, ct);
            if (error is not null) return Result.Fail(error);
        }
        var errorRegistros = await AplicarRegistrosAsync(registros, ct);
        if (errorRegistros is not null) return Result.Fail(errorRegistros);

        await db.SaveChangesAsync(ct);
        return Result.Success();
    }

    public async Task<Result<SyncPullResponse>> PullAsync(DateTimeOffset? desde, CancellationToken ct = default)
    {
        // El cursor se toma antes de consultar: lo que se guarde mientras tanto entra en el próximo pull.
        var hasta = clock.Now;
        var inicio = desde ?? DateTimeOffset.MinValue;

        var clases = await db.Clases
            .AsNoTracking()
            .AsSplitQuery()
            .Include(c => c.Columnas)
            .Include(c => c.Alumnos)
            .Include(c => c.Valores)
            .Where(c => c.ModificadoEn > inicio)
            .OrderBy(c => c.ModificadoEn)
            .ToListAsync(ct);

        var registros = await db.Registros
            .AsNoTracking()
            .Where(r => r.ModificadoEn > inicio)
            .OrderBy(r => r.ModificadoEn)
            .Select(r => new RegistroSync(r.Tipo, r.ClaseClave, r.Clave, r.Datos, r.Eliminado, r.ActualizadoEn))
            .ToListAsync(ct);

        return new SyncPullResponse(
            hasta,
            clases.Select(c => ADto(c, incluirArchivo: c.PlantillaModificadaEn > inicio)).ToList(),
            registros);
    }

    /// <summary>Por fila, gana el cambio más nuevo según la hora del teléfono.</summary>
    private async Task<Error?> AplicarRegistrosAsync(IReadOnlyList<RegistroSync> entrantes, CancellationToken ct)
    {
        if (entrantes.Count == 0) return null;
        foreach (var r in entrantes)
        {
            if (r is null || !Registro.Tipos.Contains(r.Tipo) || string.IsNullOrWhiteSpace(r.Clave)
                || r.Clave.Length > 200 || r.ClaseClave is null || r.ClaseClave.Length > 600)
                return Error.Validation("Registro incompleto.");
            if (r.Datos is not null && (r.Datos.Length > Registro.MaxDatos || !EsJson(r.Datos)))
                return Error.Validation("Registro con datos inválidos.");
        }

        // Candidatos por clase y clave; el cruce exacto (tipo, clase, clave) se hace en memoria.
        var claseClaves = entrantes.Select(r => r.ClaseClave).Distinct().ToList();
        var claves = entrantes.Select(r => r.Clave).Distinct().ToList();
        var existentes = (await db.Registros
                .Where(r => claseClaves.Contains(r.ClaseClave) && claves.Contains(r.Clave))
                .ToListAsync(ct))
            .ToDictionary(r => (r.Tipo, r.ClaseClave, r.Clave));

        var now = clock.Now;
        foreach (var r in entrantes)
        {
            var clave = (r.Tipo, r.ClaseClave, r.Clave);
            if (!existentes.TryGetValue(clave, out var registro))
            {
                registro = new Registro { Tipo = r.Tipo, ClaseClave = r.ClaseClave, Clave = r.Clave, ActualizadoEn = DateTimeOffset.MinValue };
                existentes[clave] = registro;
                db.Registros.Add(registro);
            }
            var cuando = r.ActualizadoEn.ToUniversalTime();
            if (cuando <= registro.ActualizadoEn) continue;
            registro.Datos = r.Datos;
            registro.Eliminado = r.Eliminado;
            registro.ActualizadoEn = cuando;
            registro.ModificadoEn = now;
        }
        return null;
    }

    private static bool EsJson(string texto)
    {
        try
        {
            using var _ = JsonDocument.Parse(texto);
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private async Task<Error?> AplicarAsync(ClaseSync entrante, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(entrante.Clave) || entrante.Columnas is null || entrante.Alumnos is null || entrante.Valores is null)
            return Error.Validation("Clase incompleta.");

        var now = clock.Now;
        var clase = await db.Clases
            .Include(c => c.Columnas)
            .Include(c => c.Alumnos)
            .Include(c => c.Valores)
            .AsSplitQuery()
            .FirstOrDefaultAsync(c => c.Clave == entrante.Clave, ct);

        if (entrante.Eliminada)
        {
            if (clase is null || clase.EliminadaEn is not null) return null;
            // Sólo se borra si nadie importó una plantilla más nueva después.
            if (clase.PlantillaActualizadaEn > entrante.PlantillaActualizadaEn) return null;
            clase.EliminadaEn = now;
            clase.ModificadoEn = now;
            clase.Archivo = [];
            db.ClaseColumnas.RemoveRange(clase.Columnas);
            db.ClaseAlumnos.RemoveRange(clase.Alumnos);
            db.ClaseValores.RemoveRange(clase.Valores);
            return null;
        }

        byte[]? archivo = null;
        if (entrante.ArchivoBase64 is not null)
        {
            try { archivo = Convert.FromBase64String(entrante.ArchivoBase64); }
            catch (FormatException) { return Error.Validation("El archivo de la clase no llegó completo."); }
            if (archivo.Length > MaxArchivoBytes) return Error.Validation("El archivo de la clase es demasiado grande.");
        }

        var plantillaNueva = clase is null
            || clase.EliminadaEn is not null
            || entrante.PlantillaActualizadaEn > clase.PlantillaActualizadaEn;

        if (plantillaNueva)
        {
            // Sin archivo no hay cómo exportar después: no se acepta una clase nueva sin él.
            if (archivo is null) return clase is null || clase.EliminadaEn is not null
                ? Error.Validation("Falta el archivo de la clase.", "archivo_requerido")
                : null;

            if (clase is null)
            {
                clase = new Clase { Clave = entrante.Clave };
                db.Clases.Add(clase);
            }
            clase.EliminadaEn = null;
            clase.CodigoCentro = entrante.CodigoCentro;
            clase.Centro = entrante.Centro;
            clase.Modalidad = entrante.Modalidad;
            clase.GradoSeccion = entrante.GradoSeccion;
            clase.Jornada = entrante.Jornada;
            clase.Asignatura = entrante.Asignatura;
            clase.Hoja = entrante.Hoja;
            clase.ArchivoNombre = entrante.ArchivoNombre;
            clase.Archivo = archivo;
            clase.PlantillaActualizadaEn = entrante.PlantillaActualizadaEn.ToUniversalTime();
            clase.PlantillaModificadaEn = now;

            // En su lugar y no borrar y crear: el índice único (clase, clave) no admite
            // tener la columna vieja y la nueva a la vez dentro del mismo guardado.
            var columnas = clase.Columnas.ToDictionary(c => c.Clave);
            var vigentes = entrante.Columnas.Select(c => c.Clave).ToHashSet();
            foreach (var sobra in clase.Columnas.Where(c => !vigentes.Contains(c.Clave)).ToList())
            {
                clase.Columnas.Remove(sobra);
                db.ClaseColumnas.Remove(sobra);
            }
            foreach (var c in entrante.Columnas)
            {
                if (!columnas.TryGetValue(c.Clave, out var columna))
                {
                    columna = new ClaseColumna { ClaseId = clase.Id, Clave = c.Clave };
                    clase.Columnas.Add(columna);
                    db.ClaseColumnas.Add(columna);
                }
                columna.Grupo = c.Grupo;
                columna.Nombre = c.Nombre;
                columna.Tipo = c.Tipo;
                columna.Col = c.Col;
                columna.Orden = c.Orden;
            }

            var previos = clase.Alumnos.ToDictionary(a => a.Clave);
            foreach (var a in previos.Values) a.Activo = false;
            foreach (var a in entrante.Alumnos)
            {
                if (!previos.TryGetValue(a.Clave, out var alumno))
                {
                    alumno = new ClaseAlumno { ClaseId = clase.Id, Clave = a.Clave };
                    clase.Alumnos.Add(alumno);
                    db.ClaseAlumnos.Add(alumno);
                }
                alumno.Identidad = a.Identidad;
                alumno.Documento = a.Documento;
                alumno.Nombre = a.Nombre;
                alumno.Fila = a.Fila;
                alumno.Orden = a.Orden;
                alumno.Activo = a.Activo;
            }
        }
        else if (clase!.EliminadaEn is not null)
        {
            return null;
        }
        if (clase is null) return null;

        var valores = clase.Valores.ToDictionary(v => (v.AlumnoClave, v.ColumnaClave));
        foreach (var v in entrante.Valores)
        {
            if (v.Valor is < 0 or > 9_999) return Error.Validation("Hay valores fuera de rango.");
            if (!valores.TryGetValue((v.AlumnoClave, v.ColumnaClave), out var actual))
            {
                actual = new ClaseValor { ClaseId = clase.Id, AlumnoClave = v.AlumnoClave, ColumnaClave = v.ColumnaClave, ActualizadoEn = DateTimeOffset.MinValue };
                valores[(v.AlumnoClave, v.ColumnaClave)] = actual;
                clase.Valores.Add(actual);
                db.ClaseValores.Add(actual);
            }
            // Npgsql sólo guarda timestamptz en UTC.
            var cuando = v.ActualizadoEn.ToUniversalTime();
            if (cuando <= actual.ActualizadoEn) continue;
            actual.Valor = v.Valor;
            actual.ActualizadoEn = cuando;
        }

        clase.ModificadoEn = now;
        return null;
    }

    private static ClaseSync ADto(Clase c, bool incluirArchivo) => new(
        c.Clave, c.CodigoCentro, c.Centro, c.Modalidad, c.GradoSeccion, c.Jornada, c.Asignatura,
        c.Hoja, c.ArchivoNombre,
        incluirArchivo && c.EliminadaEn is null ? Convert.ToBase64String(c.Archivo) : null,
        c.PlantillaActualizadaEn,
        c.EliminadaEn is not null,
        c.Columnas.OrderBy(x => x.Orden).Select(x => new ColumnaSync(x.Clave, x.Grupo, x.Nombre, x.Tipo, x.Col, x.Orden)).ToList(),
        c.Alumnos.OrderBy(x => x.Orden).Select(x => new AlumnoSync(x.Clave, x.Identidad, x.Documento, x.Nombre, x.Fila, x.Orden, x.Activo)).ToList(),
        c.Valores.Select(x => new ValorSync(x.AlumnoClave, x.ColumnaClave, x.Valor, x.ActualizadoEn)).ToList());
}
