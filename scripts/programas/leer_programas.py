"""Pasa a JSON los programas curriculares sistematizados de Media (BTP y BCH) de la Secretaría
de Educación: por cada espacio curricular, grado, horas, competencias, resultados de
aprendizaje (RA) con sus criterios de evaluación (CE) y contenidos, y actividades sugeridas.

Entrada: el texto de cada PDF (una línea «=== PAGINA n» entre páginas), sacado con PDFKit.
    python3 -I leer_programas.py <texto.txt> <carrera> <salida.json>
"""
import difflib
import json
import re
import sys
import unicodedata

GRADOS = {'DECIMO': 10, 'UNDECIMO': 11, 'ONCEAVO': 11, 'DUODECIMO': 12, 'DOCEAVO': 12}


def plano(t):
    """Mayúsculas sin tildes ni signos: para comparar nombres."""
    t = ''.join(c for c in unicodedata.normalize('NFD', t.upper()) if unicodedata.category(c) != 'Mn')
    return re.sub(r'[^A-Z0-9 ]', ' ', re.sub(r'\s+', ' ', t)).strip()


def grado_de(t):
    t = plano(t)
    for nombre in ('DUODECIMO', 'DOCEAVO', 'UNDECIMO', 'ONCEAVO', 'DECIMO'):
        if nombre in t:
            return GRADOS[nombre]
    return None


def plan_de_estudios(lineas):
    """Las tablas «Plan de estudios del … grado»: (grado, asignatura, horas semanales) en orden."""
    plan, grado = [], None
    for l in lineas:
        if re.match(r'^Plan de estudios? del', l, re.I) and '....' not in l:
            grado = grado_de(l)
            continue
        if grado is None:
            continue
        if re.match(r'^(HORAS EN|TOTAL)', l, re.I):
            grado = None
            continue
        m = re.match(r'^\d+\.?\s*(.+?)\s+(\d{1,2})\s+(\d{2,3})$', l)
        if m and int(m.group(3)) == int(m.group(2)) * 40:
            plan.append((grado, m.group(1).strip(), int(m.group(2))))
    return plan


def parecido(a, b):
    a, b = plano(a), plano(b)
    if a == b:
        return 1.0
    if a and b and (a in b or b in a):
        return 0.9
    return difflib.SequenceMatcher(None, a, b).ratio()


def limpiar(lineas):
    """Quita encabezados y números de página, y une el texto en líneas útiles."""
    fuera = []
    for l in lineas:
        t = l.strip().replace('￼', '')
        if not t or t.startswith('=== PAGINA') or t.startswith('PAGINAS:') or re.fullmatch(r'\d{1,3}', t):
            continue
        if t.startswith('Secretaría de Educación') or t.startswith('Programas Curriculares del') \
                or t.startswith('Programa Curricular del') or 'Versión Preliminar' in t:
            continue
        fuera.append(t)
    return fuera


def unir(partes):
    texto = ' '.join(partes)
    texto = re.sub(r'\s+', ' ', texto).strip()
    return re.sub(r'(\w)- (\w)', r'\1\2', texto)


def vinetas(lineas):
    """Lista de viñetas (● …); las líneas sueltas continúan la anterior."""
    items = []
    for l in lineas:
        if not l:
            continue
        if l[0] in '●•▪◦-–' or re.match(r'^\d+\.\s', l):
            items.append([re.sub(r'^([●•▪◦\-–]|\d+\.)\s*', '', l)])
        elif items:
            items[-1].append(l)
        else:
            items.append([l])
    return [unir(i) for i in items if unir(i)]


def por_ra(lineas):
    """Contenidos agrupados bajo «RA1.», «RA2.»…; sin grupos, todos van a None."""
    grupos, actual = {}, None
    for l in lineas:
        m = re.match(r'^RA\s?(\d+)\.?\s*(.*)$', l)
        if m:
            actual = int(m.group(1))
            if m.group(2):
                grupos.setdefault(actual, []).append(m.group(2))
            continue
        grupos.setdefault(actual, []).append(l)
    return {k: vinetas(v) for k, v in grupos.items()}


def seccion(lineas, inicio, fines):
    """Las líneas entre la primera que empieza con [inicio] (con lo que siga en esa línea) y la
    siguiente que empieza con uno de [fines]."""
    i = next((k for k, l in enumerate(lineas) if l.lower().startswith(inicio.lower())), None)
    if i is None:
        return []
    j = next((k for k in range(i + 1, len(lineas)) if any(lineas[k].lower().startswith(f.lower()) for f in fines)),
             len(lineas))
    resto = lineas[i][len(inicio):].strip()
    return ([resto] if resto else []) + lineas[i + 1:j]


def espacio(bloque):
    texto = '\n'.join(bloque)
    nombre = None
    for k, l in enumerate(bloque):
        m = re.match(r'^Nombre del Espacio(?:\s+Curricular)?[:\s]*(.*)$', l, re.I)
        if m:
            # A veces el nombre va en otra línea: «Nombre del Espacio / Curricular / FÍSICA».
            resto = [x for x in [m.group(1)] + bloque[k + 1:k + 3] if x and plano(x) != 'CURRICULAR']
            nombre = re.sub(r'^Curricular[:\s]*', '', resto[0], flags=re.I) if resto else None
            break
    grado = re.search(r'^(?:Grado|Año al que pertenece)[:\s]+(.+)$', texto, re.I | re.M)
    duracion = [int(n) for l in seccion(bloque, 'Duración', ['Competencias']) for n in re.findall(r'\d+', l)]
    if not nombre:
        return None

    comp = seccion(bloque, 'Competencias del Espacio', ['Resultados de aprendizaje'])
    comp = [c for c in (re.sub(r'^Curricular\.?\s*', '', c, flags=re.I) for c in comp) if c]
    competencias = vinetas(comp) if any(re.match(r'^(\d+\.|●)', c) for c in comp) else ([unir(comp)] if comp else [])

    # Resultados y criterios: cada marca abre un elemento; lo demás continúa el último.
    tabla = seccion(bloque, 'Resultados de aprendizaje y Criterios', ['Contenidos formativos', 'Contenidos Conceptuales'])
    resultados, ra, ce = [], None, None
    for l in tabla:
        if re.match(r'^Resultados de aprendizaje\s+Criterios', l, re.I):
            continue
        m = re.match(r'^RA\s?(\d+)\.?\s*(.*)$', l)
        c = re.match(r'^CE\s?\.?\s?(\d+)\s?\.\s?(\d+)\.?\s*(.*)$', l)
        if m:
            ra = {'numero': int(m.group(1)), 'texto': [m.group(2)], 'criterios': []}
            resultados.append(ra)
            ce = None
        elif c and ra is not None:
            ce = {'codigo': f'CE{c.group(1)}.{c.group(2)}', 'texto': [c.group(3)]}
            # Un CE de otro RA (tablas partidas entre páginas): va con su RA.
            dueño = next((r for r in resultados if r['numero'] == int(c.group(1))), ra)
            dueño['criterios'].append(ce)
        elif ce is not None:
            ce['texto'].append(l)
        elif ra is not None:
            ra['texto'].append(l)

    conceptuales = por_ra(seccion(bloque, 'Contenidos Conceptuales', ['Contenidos Procedimentales']))
    procedimentales = por_ra(seccion(bloque, 'Contenidos Procedimentales', ['Contenidos Actitudinales']))
    actitudinales = vinetas(seccion(bloque, 'Contenidos Actitudinales', ['Actividades de E-A', 'Actividades de enseñanza']))
    relleno = ('significativas', 'del espacio', 'espacio curricular', 'curricular', 'de', 'e-a pertinentes', 'pertinentes')
    actividades = vinetas([l for l in seccion(bloque, 'Actividades de E-A', ['Metodologías', 'Metodologia'])
                           if l.lower().strip(' .') not in relleno and not l.lower().startswith('significativas')])
    metodologias = vinetas([l for l in seccion(bloque, 'Metodologías', ['Perfil del docente', 'Perfil docente', 'Requisitos'])
                            if l.lower().strip(' .') not in relleno])

    return {
        'asignatura': unir([nombre]).strip(' .:'),
        'grado': grado_de(grado.group(1)) if grado else None,
        'horasSemana': min(duracion) if duracion else None,
        'competencias': competencias,
        'resultados': [{
            'codigo': f"RA{r['numero']}",
            'texto': unir(r['texto']),
            'criterios': [{'codigo': c['codigo'], 'texto': unir(c['texto'])} for c in r['criterios']],
            'conceptuales': conceptuales.get(r['numero'], []),
            'procedimentales': procedimentales.get(r['numero'], []),
        } for r in resultados],
        'actitudinales': actitudinales,
        'actividades': actividades,
        'metodologias': metodologias,
    }


def main():
    origen, carrera, salida = sys.argv[1:4]
    lineas = limpiar(open(origen, encoding='utf-8').read().splitlines())
    cortes = [k for k, l in enumerate(lineas) if l.lower().startswith('datos generales')] + [len(lineas)]
    espacios = [e for e in (espacio(lineas[a:b]) for a, b in zip(cortes, cortes[1:])) if e]

    # Sin grado en la ficha, el de la anterior: los documentos van de décimo a duodécimo.
    for a, b in zip(espacios, espacios[1:]):
        b['grado'] = b['grado'] or a['grado']

    # El plan de estudios manda en grado y horas: en las fichas a veces vienen cambiados.
    # Se recorre en orden: cada ficha toma la primera asignatura parecida desde la última usada.
    plan = plan_de_estudios(lineas)
    k = 0
    for e in espacios:
        candidatos = [(parecido(e['asignatura'], n), i) for i, (_, n, _) in enumerate(plan) if i >= k]
        if candidatos and max(candidatos)[0] >= 0.75:
            _, i = max(candidatos, key=lambda c: (c[0], -c[1]))
            e['grado'], e['asignaturaPlan'], e['horasSemana'] = plan[i][0], plan[i][1], plan[i][2]
            k = i + 1
    json.dump({'carrera': carrera, 'espacios': espacios}, open(salida, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    sin_grado = sum(1 for e in espacios if not e['grado'])
    sin_ra = sum(1 for e in espacios if not e['resultados'])
    ces = sum(len(r['criterios']) for e in espacios for r in e['resultados'])
    fuera = sum(1 for e in espacios if 'asignaturaPlan' not in e)
    print(f'{carrera}: plan {len(plan)}, {len(espacios)} espacios ({fuera} fuera del plan), {ces} criterios, '
          f'sin grado {sin_grado}, sin RA {sin_ra}')


main()
