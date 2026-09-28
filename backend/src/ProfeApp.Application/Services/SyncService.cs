using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using ProfeApp.Application.Abstractions;
using ProfeApp.Application.Common;
using ProfeApp.Application.Contracts;
using ProfeApp.Domain.Cuadros;
using ProfeApp.Domain.Planes;

namespace ProfeApp.Application.Services;

/// <summary>
/// Respaldo y sincronización entre dispositivos del mismo docente. Cada celda se resuelve
/// por separado con "gana el cambio más nuevo", así dos teléfonos pueden capturar columnas
/// distintas de la misma clase sin pisarse. Todo es idempotente: reenviar lo mismo no
/// cambia nada, y la app puede reintentar sin miedo.
///
/// Pensado para crecer: sólo viaja lo que cambió, el pull va por páginas y el archivo de
/// SACE (lo más pesado) no se lee de la base salvo cuando hace falta.
/// </summary>
public sealed class SyncService(IAppDbContext db, IClock clock)
{
    private const int MaxClasesPorPush = 50;
    private const int MaxArchivoBytes = 5 * 1024 * 1024;
    private const int MaxRegistrosPorPush = 2_000;
    private const int MaxValoresPorClase = 20_000;
    public const int RegistrosPorPagina = 1_000;

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

    /// <summary>
    /// Lo cambiado desde <paramref name="desde"/> hasta <paramref name="hasta"/> (la primera
    /// página lo fija con la hora del servidor). Las clases, sin archivo, van en la página 0;
    /// los registros, de a <see cref="RegistrosPorPagina"/>.
    /// </summary>
    public async Task<Result<SyncPullResponse>> PullAsync(
        DateTimeOffset? desde, DateTimeOffset? hasta = null, int pagina = 0, string? despues = null, CancellationToken ct = default)
    {
        if (pagina < 0) return Result<SyncPullResponse>.Fail(Error.Validation("Página inválida."));
        (DateTimeOffset En, Guid Id)? cursor = null;
        if (despues is not null)
        {
            if (LeerCursor(despues) is not { } leido) return Result<SyncPullResponse>.Fail(Error.Validation("Cursor inválido."));
            cursor = leido;
        }
        // El cursor se toma antes de consultar: lo que se guarde mientras tanto entra en el próximo pull.
        var fin = (hasta ?? clock.Now).ToUniversalTime();
        var inicio = (desde ?? DateTimeOffset.MinValue).ToUniversalTime();
        var todo = desde is null;

        var clases = new List<ClaseSync>();
        if (pagina == 0 && cursor is null)
        {
            var cambiadas = await db.Clases.AsNoTracking()
                .Where(c => c.ModificadoEn > inicio && c.ModificadoEn <= fin)
                .OrderBy(c => c.ModificadoEn)
                .ToListAsync(ct);
            var ids = cambiadas.Select(c => c.Id).ToList();
            var conPlantilla = cambiadas.Where(c => todo || c.PlantillaModificadaEn > inicio).Select(c => c.Id).ToList();

            var columnas = (await db.ClaseColumnas.AsNoTracking().Where(x => conPlantilla.Contains(x.ClaseId)).ToListAsync(ct))
                .ToLookup(x => x.ClaseId);
            var alumnos = (await db.ClaseAlumnos.AsNoTracking().Where(x => conPlantilla.Contains(x.ClaseId)).ToListAsync(ct))
                .ToLookup(x => x.ClaseId);
            // Sólo las celdas que cambiaron; en el primer pull, todas.
            var valores = (await db.ClaseValores.AsNoTracking()
                    .Where(v => ids.Contains(v.ClaseId) && (todo || (v.ModificadoEn > inicio && v.ModificadoEn <= fin)))
                    .ToListAsync(ct))
                .ToLookup(v => v.ClaseId);

            clases = cambiadas.Select(c => ADto(c, conPlantilla.Contains(c.Id), columnas[c.Id], alumnos[c.Id], valores[c.Id])).ToList();
        }

        // Con cursor, la base sigue desde el último entregado por el índice; sin él (clientes
        // viejos que mandan "pagina"), salta filas.
        var consulta = cursor is { } c
            ? db.Registros.FromSql($"SELECT * FROM registros WHERE (modificado_en, id) > ({c.En}, {c.Id})")
            : db.Registros;
        consulta = consulta.AsNoTracking()
            .Where(r => r.ModificadoEn > inicio && r.ModificadoEn <= fin)
            .OrderBy(r => r.ModificadoEn).ThenBy(r => r.Id);
        if (cursor is null) consulta = consulta.Skip(pagina * RegistrosPorPagina);
        var filas = await consulta
            .Take(RegistrosPorPagina + 1)
            .Select(r => new { r.Id, r.ModificadoEn, Dto = new RegistroSync(r.Tipo, r.ClaseClave, r.Clave, r.Datos, r.Eliminado, r.ActualizadoEn) })
            .ToListAsync(ct);
        var mas = filas.Count > RegistrosPorPagina;
        if (mas) filas.RemoveAt(filas.Count - 1);
        var siguiente = mas ? $"{filas[^1].ModificadoEn.UtcTicks}_{filas[^1].Id:N}" : null;

        return new SyncPullResponse(fin, clases, filas.Select(x => x.Dto).ToList(), mas, siguiente);
    }

    private static (DateTimeOffset, Guid)? LeerCursor(string texto)
    {
        var partes = texto.Split('_');
        return partes.Length == 2 && long.TryParse(partes[0], out var ticks) && ticks >= 0 && ticks <= DateTimeOffset.MaxValue.UtcTicks
            && Guid.TryParse(partes[1], out var id)
            ? (new DateTimeOffset(ticks, TimeSpan.Zero), id)
            : null;
    }

    /// <summary>El cuadro original de una clase, para el dispositivo que todavía no lo tiene.</summary>
    public async Task<Result<ArchivoClase>> ArchivoAsync(string clave, CancellationToken ct = default)
    {
        var archivo = await db.Clases.AsNoTracking()
            .Where(c => c.Clave == clave && c.EliminadaEn == null)
            .Select(c => c.Archivo.Contenido)
            .FirstOrDefaultAsync(ct);
        return archivo is null || archivo.Length == 0
            ? Result<ArchivoClase>.Fail(Error.NotFound("La clase"))
            : new ArchivoClase(clave, Convert.ToBase64String(archivo));
    }

    private async Task<Error?> AplicarAsync(ClaseSync entrante, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(entrante.Clave) || entrante.Valores is null)
            return Error.Validation("Clase incompleta.");
        if (entrante.Valores.Count > MaxValoresPorClase) return Error.Validation("Demasiadas celdas en una clase.");

        var now = clock.Now;
        // Sin columnas, alumnos, valores ni archivo: cada cosa se carga sólo si se va a usar.
        var clase = await db.Clases.FirstOrDefaultAsync(c => c.Clave == entrante.Clave, ct);

        if (entrante.Eliminada)
        {
            if (clase is null || clase.EliminadaEn is not null) return null;
            // Sólo se borra si nadie importó una plantilla más nueva después.
            if (clase.PlantillaActualizadaEn > entrante.PlantillaActualizadaEn) return null;
            clase.EliminadaEn = now;
            clase.ModificadoEn = now;
            await db.Entry(clase).Reference(c => c.Archivo).LoadAsync(ct);
            clase.Archivo.Contenido = [];
            await db.ClaseColumnas.Where(x => x.ClaseId == clase.Id).ExecuteDeleteAsync(ct);
            await db.ClaseAlumnos.Where(x => x.ClaseId == clase.Id).ExecuteDeleteAsync(ct);
            await db.ClaseValores.Where(x => x.ClaseId == clase.Id).ExecuteDeleteAsync(ct);
            await db.Registros.Where(r => r.ClaseClave == clase.Clave).ExecuteDeleteAsync(ct);
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
            if (archivo is null || !entrante.ConPlantilla || entrante.Columnas is null || entrante.Alumnos is null)
                return clase is null || clase.EliminadaEn is not null
                    ? Error.Validation("Falta el archivo de la clase.", "archivo_requerido")
                    : null;

            List<ClaseColumna> columnasActuales = [];
            List<ClaseAlumno> alumnosActuales = [];
            if (clase is null)
            {
                clase = new Clase { Clave = entrante.Clave };
                clase.Archivo.Id = clase.Id;
                db.Clases.Add(clase);
            }
            else
            {
                await db.Entry(clase).Reference(c => c.Archivo).LoadAsync(ct);
                columnasActuales = await db.ClaseColumnas.Where(x => x.ClaseId == clase.Id).ToListAsync(ct);
                alumnosActuales = await db.ClaseAlumnos.Where(x => x.ClaseId == clase.Id).ToListAsync(ct);
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
            clase.Archivo.Contenido = archivo;
            clase.PlantillaActualizadaEn = entrante.PlantillaActualizadaEn.ToUniversalTime();
            clase.PlantillaModificadaEn = now;

            // En su lugar y no borrar y crear: el índice único (clase, clave) no admite
            // tener la columna vieja y la nueva a la vez dentro del mismo guardado.
            var columnas = columnasActuales.ToDictionary(c => c.Clave);
            var vigentes = entrante.Columnas.Select(c => c.Clave).ToHashSet();
            foreach (var sobra in columnasActuales.Where(c => !vigentes.Contains(c.Clave)))
                db.ClaseColumnas.Remove(sobra);
            foreach (var c in entrante.Columnas)
            {
                if (!columnas.TryGetValue(c.Clave, out var columna))
                {
                    columna = new ClaseColumna { ClaseId = clase.Id, Clave = c.Clave };
                    db.ClaseColumnas.Add(columna);
                }
                columna.Grupo = c.Grupo;
                columna.Nombre = c.Nombre;
                columna.Tipo = c.Tipo;
                columna.Col = c.Col;
                columna.Orden = c.Orden;
            }

            var previos = alumnosActuales.ToDictionary(a => a.Clave);
            foreach (var a in alumnosActuales) a.Activo = false;
            foreach (var a in entrante.Alumnos)
            {
                if (!previos.TryGetValue(a.Clave, out var alumno))
                {
                    alumno = new ClaseAlumno { ClaseId = clase.Id, Clave = a.Clave };
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

        // Sólo las celdas que llegaron: se buscan por alumno y se cruzan en memoria.
        if (entrante.Valores.Count > 0)
        {
            var alumnosDeLasCeldas = entrante.Valores.Select(v => v.AlumnoClave).Distinct().ToList();
            var valores = (await db.ClaseValores
                    .Where(v => v.ClaseId == clase.Id && alumnosDeLasCeldas.Contains(v.AlumnoClave))
                    .ToListAsync(ct))
                .ToDictionary(v => (v.AlumnoClave, v.ColumnaClave));
            foreach (var v in entrante.Valores)
            {
                if (v.Valor is < 0 or > 9_999) return Error.Validation("Hay valores fuera de rango.");
                if (!valores.TryGetValue((v.AlumnoClave, v.ColumnaClave), out var actual))
                {
                    actual = new ClaseValor { ClaseId = clase.Id, AlumnoClave = v.AlumnoClave, ColumnaClave = v.ColumnaClave, ActualizadoEn = DateTimeOffset.MinValue };
                    valores[(v.AlumnoClave, v.ColumnaClave)] = actual;
                    db.ClaseValores.Add(actual);
                }
                // Npgsql sólo guarda timestamptz en UTC.
                var cuando = v.ActualizadoEn.ToUniversalTime();
                if (cuando <= actual.ActualizadoEn) continue;
                actual.Valor = v.Valor;
                actual.ActualizadoEn = cuando;
                actual.ModificadoEn = now;
            }
        }

        clase.ModificadoEn = now;
        return null;
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
        // El tipo va en el filtro para que se use el índice (tenant, tipo, clase, clave) completo.
        var tipos = entrantes.Select(r => r.Tipo).Distinct().ToList();
        var existentes = (await db.Registros
                .Where(r => tipos.Contains(r.Tipo) && claseClaves.Contains(r.ClaseClave) && claves.Contains(r.Clave))
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

    private static ClaseSync ADto(
        Clase c, bool conPlantilla, IEnumerable<ClaseColumna> columnas, IEnumerable<ClaseAlumno> alumnos, IEnumerable<ClaseValor> valores) => new(
        c.Clave, c.CodigoCentro, c.Centro, c.Modalidad, c.GradoSeccion, c.Jornada, c.Asignatura,
        c.Hoja, c.ArchivoNombre,
        null,
        c.PlantillaActualizadaEn,
        c.EliminadaEn is not null,
        conPlantilla ? columnas.OrderBy(x => x.Orden).Select(x => new ColumnaSync(x.Clave, x.Grupo, x.Nombre, x.Tipo, x.Col, x.Orden)).ToList() : [],
        conPlantilla ? alumnos.OrderBy(x => x.Orden).Select(x => new AlumnoSync(x.Clave, x.Identidad, x.Documento, x.Nombre, x.Fila, x.Orden, x.Activo)).ToList() : [],
        valores.Select(x => new ValorSync(x.AlumnoClave, x.ColumnaClave, x.Valor, x.ActualizadoEn)).ToList(),
        conPlantilla && c.EliminadaEn is null);
}
