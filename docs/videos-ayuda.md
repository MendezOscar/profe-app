# Videos de ayuda

Cinco videos cortos, verticales (1080 × 1920, .mp4), que siguen los «Primeros pasos» de la app.
Cada paso va escrito en pantalla y narrado con las voces del Mac (Paulina en los impares, Eddy en
los pares), con música de fondo que baja mientras se habla.
Se graban solos sobre el panel web local con la cuenta demo y cuadros de SACE inventados (centro,
alumnos e identidades con prefijo `9999` ficticios). Los archivos quedan en `videos-ayuda/`
(fuera del repositorio) y se suben a YouTube; la página de soporte enlaza a cada uno.

## Para YouTube

Subirlos como **No listados** o **Públicos**, en una lista «Cómo usar ProfeApp», en este orden.
En cada descripción, al final: `Ayuda: https://profeapphn.com/soporte`.

| Archivo | Título | Descripción |
| --- | --- | --- |
| `1-importa-tus-cuadros.mp4` | Importa tus cuadros de SACE · ProfeApp | Descarga de SACE el cuadro de cada asignatura e impórtalos todos a la vez. Tus alumnos quedan listos y trabajas sin internet. |
| `2-arma-tu-rubrica.mp4` | Arma la rúbrica del parcial · ProfeApp | Reparte los 100 puntos del parcial en rubros: tareas, trabajos, proyecto, examen. La app te avisa si faltan puntos. |
| `3-califica-una-actividad.mp4` | Crea una actividad y califica · ProfeApp | Crea una tarea o un examen y califica alumno por alumno; se guarda solo. |
| `4-pasa-lista.mp4` | Pasa lista en segundos · ProfeApp | Todos empiezan presentes: marcas solo ausencias, llegadas tarde y faltas justificadas. |
| `5-cierra-y-exporta.mp4` | Cierra el parcial y exporta para SACE · ProfeApp | Cierra el parcial: NOTA TOTAL e INASISTENCIAS se llenan solas. Exporta el cuadro y súbelo en SACE. |

## Volver a grabarlos

Cuando cambie la interfaz. Necesita `ffmpeg` (`brew install ffmpeg`) y la música en
`videos-ayuda/musica.mp3` (pista de la Biblioteca de audio de YouTube, «Thinking of You» de
Televisions; sin ella sale solo con voz). Todo corre en la máquina local; `reiniciar-local.sh` **borra la base
de desarrollo** (no toca producción).

```sh
cd scripts/videos-ayuda && npm install && python3 cuadros.py
docker start profeapp-db && ./reiniciar-local.sh        # API local en :5081 con el docente demo
(cd ../../mobile && flutter build web --release --base-href /app/ --dart-define=API_BASE_URL=http://localhost:5081)
node servidor.mjs &                                    # panel + marco en :8099
node grabar.mjs                                        # ~8 min; deja los .mp4 en videos-ayuda/
```

`ETAPAS=1,3 node grabar.mjs` graba solo esos videos (`p` prepara la sección 2 para el video 5;
`l` solo inicia sesión). Si un toque cae fuera de lugar, las fotos de control quedan en
`$TMPDIR/profeapp-videos/fotos`.
