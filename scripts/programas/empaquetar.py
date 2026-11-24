"""Junta lo leído por leer_programas.py y leer_basica.py en los archivos que usa la API
(comprimidos, uno por carrera, en ProfeApp.Infrastructure/Programas/Datos).

    python3 -I empaquetar.py <carpeta con N.json, carreras.json y basica.json> <carpeta de salida>
"""
import gzip
import json
import os
import re
import sys
import unicodedata


def slug(t):
    t = ''.join(c for c in unicodedata.normalize('NFD', t.lower()) if unicodedata.category(c) != 'Mn')
    return re.sub(r'[^a-z0-9]+', '-', t).strip('-')


def guardar(ruta, datos):
    with gzip.open(ruta, 'wt', encoding='utf-8', compresslevel=9) as f:
        json.dump(datos, f, ensure_ascii=False, separators=(',', ':'))


origen, destino = sys.argv[1:3]
os.makedirs(destino, exist_ok=True)
for viejo in os.listdir(destino):
    if viejo.endswith('.json.gz'):
        os.remove(os.path.join(destino, viejo))
carreras = json.load(open(os.path.join(origen, 'carreras.json'), encoding='utf-8'))
for n, nombre in carreras.items():
    d = json.load(open(os.path.join(origen, f'{n}.json'), encoding='utf-8'))
    espacios = []
    for e in d['espacios']:
        if not e['resultados'] or not e['grado']:
            continue  # sin resultados de aprendizaje no aporta: la IA sigue con los temas del docente
        e.pop('metodologias', None)
        espacios.append(e)
    guardar(os.path.join(destino, f'media-{slug(nombre)}.json.gz'), {'carrera': nombre, 'espacios': espacios})
guardar(os.path.join(destino, 'basica.json.gz'), json.load(open(os.path.join(origen, 'basica.json'), encoding='utf-8')))
total = sum(os.path.getsize(os.path.join(destino, f)) for f in os.listdir(destino))
print(f'{len(carreras)} carreras + básica, {total / 1e6:.1f} MB')
