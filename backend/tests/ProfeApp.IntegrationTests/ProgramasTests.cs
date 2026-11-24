using ProfeApp.Infrastructure.Programas;

namespace ProfeApp.IntegrationTests;

/// <summary>Los programas oficiales se encuentran con lo que trae el cuadro de SACE.</summary>
public class ProgramasTests
{
    private readonly ProgramasCurriculares _programas = new();

    [Fact]
    public void Encuentra_la_asignatura_de_un_BTP_por_modalidad_grado_y_nombre()
    {
        var p = _programas.Buscar("BACHILLERATO TÉCNICO PROFESIONAL EN MERCADOTECNIA", "DÉCIMO GRADO SECCIÓN 1", "MATEMÁTICAS");
        Assert.NotNull(p);
        Assert.Equal("Mercadotecnia", p.Carrera);
        Assert.Equal(10, p.Grado);
        Assert.Equal(5, p.HorasSemana);
        Assert.Equal("RA1", p.Resultados[0].Codigo);
        Assert.True(p.Resultados.Count >= 9);

        // Undécimo, aunque la ficha del documento diga duodécimo: manda el plan de estudios.
        Assert.Equal(11, _programas.Buscar("BACHILLERATO TÉCNICO PROFESIONAL EN MERCADOTECNIA", "ONCEAVO GRADO SECCIÓN 2",
            "INVESTIGACIÓN DE MERCADOS I")?.Grado);
        Assert.Equal("Informática con Orientación en Robótica", _programas.Buscar(
            "BACHILLERATO TÉCNICO PROFESIONAL EN INFORMÁTICA CON ORIENTACIÓN EN ROBÓTICA", "DÉCIMO GRADO", "ESPAÑOL")?.Carrera);
        Assert.Equal("Ciencias y Humanidades", _programas.Buscar("BACHILLERATO EN CIENCIAS Y HUMANIDADES", "UNDÉCIMO GRADO", "QUÍMICA")?.Carrera);
    }

    [Fact]
    public void Sin_programa_devuelve_null()
    {
        Assert.Null(_programas.Buscar("BACHILLERATO TÉCNICO PROFESIONAL EN MERCADOTECNIA", "DÉCIMO GRADO", "ASIGNATURA QUE NO EXISTE"));
        Assert.Null(_programas.Buscar("NO APLICA", "DÉCIMO GRADO", "MATEMÁTICA"));
        Assert.Null(_programas.Buscar("NO APLICA", "TERCER GRADO SECCIÓN 1", "EDUCACIÓN FÍSICA"));
    }

    [Fact]
    public void El_contexto_trae_los_criterios_elegidos_o_los_meses_del_parcial()
    {
        var media = _programas.Contexto("BACHILLERATO TÉCNICO PROFESIONAL EN MERCADOTECNIA", "DÉCIMO GRADO", "MATEMÁTICA", "PARCIAL I", ["RA2"]);
        Assert.NotNull(media);
        Assert.Contains("CE2.6", media);
        Assert.DoesNotContain("CE1.1", media);

        var basica = _programas.Buscar("NO APLICA", "TERCER GRADO SECCIÓN 1", "CIENCIAS NATURALES");
        Assert.NotNull(basica);
        Assert.Equal("Ciencias Naturales", basica.Asignatura);
        Assert.NotEmpty(basica.Meses);
        var parcial = _programas.Contexto("NO APLICA", "TERCER GRADO SECCIÓN 1", "CIENCIAS NATURALES", "PARCIAL IV", null);
        Assert.NotNull(parcial);
        Assert.Contains("Septiembre", parcial);
        Assert.DoesNotContain("Febrero:", parcial);
    }
}
