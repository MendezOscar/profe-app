"""Parte por área, grado y mes las programaciones de Básica (1.° a 9.°) de la Secretaría de
Educación. El texto viene en dos columnas mezcladas (estándares y contenidos), así que no se
ordena más: a la IA se le da el de los meses del parcial y ella lo interpreta.

    python3 -I leer_basica.py <salida.json> <texto.txt> [<texto.txt> …]
"""
import json
import re
import sys
import unicodedata

MESES = ['FEBRERO', 'MARZO', 'ABRIL', 'MAYO', 'JUNIO', 'JULIO', 'AGOSTO', 'SEPTIEMBRE', 'OCTUBRE', 'NOVIEMBRE']
GRADOS = {'PRIMER': 1, 'SEGUNDO': 2, 'TERCER': 3, 'CUARTO': 4, 'QUINTO': 5, 'SEXTO': 6,
          'SEPTIMO': 7, 'OCTAVO': 8, 'NOVENO': 9}
AREAS = {'ESPANOL': 'Español', 'MATEMATICAS': 'Matemáticas', 'CIENCIAS NATURALES': 'Ciencias Naturales',
         'CIENCIAS SOCIALES': 'Ciencias Sociales'}
RUIDO = re.compile(r'^(Estándar|Mes Estándar|y actitudinales|Contenidos conceptuales|Página|Lecciones|del libro del|'
                   r'docente|Secretaría de Educación|Programación del Área|Programaciones -|Lengua Oral$|Lectura$|Escritura$)',
                   re.I)


def plano(t):
    return ''.join(c for c in unicodedata.normalize('NFD', t.upper()) if unicodedata.category(c) != 'Mn')


def paginas(ruta):
    actual, todas = None, []
    for l in open(ruta, encoding='utf-8').read().splitlines():
        if l.startswith('=== PAGINA'):
            actual = []
            todas.append(actual)
        elif actual is not None:
            actual.append(l.strip().replace('￼', ''))
    return todas


def main():
    salida, *rutas = sys.argv[1:]
    bloques = {}  # (área, grado, mes) → líneas
    for ruta in rutas:
        area_archivo = next((v for k, v in AREAS.items() if k.replace(' ', '_') in plano(ruta).replace(' ', '_')), None)
        pags = paginas(ruta)
        info = []
        for p in pags:
            texto = plano('\n'.join(p))
            area = next((v for k, v in AREAS.items() if f'PROGRAMACIONES - {k}' in texto or f'AREA DE {k}' in texto), None)
            g = re.search(r'^(PRIMER|SEGUNDO|TERCER|CUARTO|QUINTO|SEXTO|SEPTIMO|OCTAVO|NOVENO) GRADO', texto, re.M)
            info.append([area, GRADOS[g.group(1)] if g else None])
        info[0][0] = info[0][0] or area_archivo
        # Cada grado empieza en una página que lo dice; las que no lo dicen siguen el de la anterior.
        for i in range(1, len(info)):
            info[i][0] = info[i][0] or info[i - 1][0]
            info[i][1] = info[i][1] or info[i - 1][1]
        mes = None
        anterior = None
        for p, (area, grado) in zip(pags, info):
            if not area or not grado:
                continue
            if (area, grado) != anterior:
                mes, anterior = 'FEBRERO', (area, grado)
            for l in p:
                if not l or re.fullmatch(r'\d{1,3}', l) or RUIDO.match(l) or 'USAID' in l or 'MIDEH' in l:
                    continue
                encabezado = [m for m in MESES if re.fullmatch(rf'({m})( Y \w+)?', plano(l))]
                if encabezado:
                    mes = encabezado[0]
                    continue
                if re.fullmatch(r'(PRIMER|SEGUNDO|TERCER|CUARTO|QUINTO|SEXTO|SEPTIMO|OCTAVO|NOVENO) GRADO( \d+)?', plano(l)):
                    continue
                bloques.setdefault((area, grado, mes), []).append(l)
    datos = {}
    for (area, grado, mes), lineas in sorted(bloques.items(), key=lambda x: (x[0][0], x[0][1], MESES.index(x[0][2]))):
        texto = re.sub(r'(\w)fi (\w)', r'\1fi\2', ' '.join(lineas))  # «signifi cado» → «significado»
        texto = re.sub(r'(\w)fl (\w)', r'\1fl\2', texto)
        datos.setdefault(f'{area}|{grado}', {'area': area, 'grado': grado, 'meses': []})['meses'].append(
            {'mes': mes.capitalize(), 'texto': re.sub(r'\s+', ' ', texto).strip()})
    json.dump(list(datos.values()), open(salida, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    for d in datos.values():
        print(d['area'], d['grado'], [(m['mes'][:3], len(m['texto'])) for m in d['meses']])


main()
