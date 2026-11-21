// Video promocional del modo docente (vertical 1080 × 1920, ~50 s): textos animados de promo.html,
// tomas reales de los videos de ayuda dentro de un teléfono, voz Paulina y la música de los videos.
// Necesita los videos de ayuda ya grabados en videos-ayuda/ (ver docs/videos-ayuda.md) y ffmpeg.
//   cd scripts/videos-ayuda && node promo.mjs     → videos-ayuda/promo-docente.mp4
import { chromium } from 'playwright-core';
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { mkdirSync, existsSync } from 'node:fs';
import { execFileSync, spawn } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const aqui = new URL('.', import.meta.url).pathname;
const videos = join(aqui, '../../videos-ayuda');
const salida = join(videos, process.env.SALIDA ?? 'promo-docente.mp4');
const tmp = join(tmpdir(), 'profeapp-promo'); mkdirSync(tmp, { recursive: true });
const FPS = 30;
// Voz del Mac (say -v '?') y pista de fondo; se cambian sin tocar el código.
const VOZ = process.env.VOZ ?? 'Paulina';
const MUSICA = process.env.MUSICA ?? 'musica-promo.mp3';

// Escenas: lo que dice la voz y, en las del teléfono, qué tramo de qué video de ayuda se ve.
const escenas = [
  { voz: '¿Todavía pasas las notas a mano al cuadro de SACE? Conoce Profe App.', min: 4.5 },
  { voz: 'Importa tus cuadros de SACE, y tus alumnos quedan listos en un minuto.', clip: ['1-importa-tus-cuadros.mp4', 38, 50] },
  { voz: 'Califica desde el teléfono. La nota del parcial se calcula sola.', clip: ['3-califica-una-actividad.mp4', 47, 59] },
  { voz: 'Pasa lista en segundos: marcas solo a los que faltan.', clip: ['4-pasa-lista.mp4', 23, 33] },
  { voz: 'Al cerrar el parcial, la nota total y las inasistencias quedan listas para subir a SACE.', clip: ['5-cierra-y-exporta.mp4', 43, 63] },
  { voz: 'Y con el plan Pro, un asistente con inteligencia artificial califica trabajos desde una foto y prepara tus exámenes. Tú siempre decides.', min: 8 },
  { voz: 'Funciona sin internet, en tu teléfono y en tu computadora.', min: 5 },
  { voz: 'Profe App. Descárgala hoy en App Store o Google Play.', min: 6 },
];

const duracion = (f) => Number(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', f]).toString());

// 1. Voz de cada escena; la escena dura lo que la voz más un respiro (las del teléfono, al menos 6.5 s).
let t = 0;
const linea = [];
escenas.forEach((e, i) => {
  e.audio = join(tmp, `voz${i}.aiff`);
  execFileSync('say', ['-v', VOZ, '-r', '170', '-o', e.audio, e.voz]);
  const largo = Math.max(e.min ?? 6.5, duracion(e.audio) + 1.1);
  linea.push([t, t + largo]);
  e.inicio = t;
  t += largo;
});
const total = t;
console.log('Duración:', total.toFixed(1), 's');

// 2. Fondo animado: un cuadro por vez desde promo.html (determinista, sin depender del reloj).
const tipos = { '.html': 'text/html', '.ttf': 'font/ttf', '.png': 'image/png' };
const servidor = http.createServer(async (q, r) => {
  const ruta = new URL(q.url, 'http://x').pathname;
  const archivo = ruta === '/promo.html' ? join(aqui, 'promo.html')
    : ruta === '/icono.png' ? join(aqui, '../../mobile/web/icons/Icon-512.png')
    : ruta.startsWith('/fuentes/') ? join(aqui, '../../mobile/assets/fonts', ruta.slice(9)) : null;
  try { r.writeHead(200, { 'content-type': tipos[archivo.slice(archivo.lastIndexOf('.'))] }); r.end(await readFile(archivo)); }
  catch { r.writeHead(404); r.end(); }
}).listen(8098);

const fondo = join(tmp, 'fondo.mp4');
// REUSAR_FONDO=1: solo cambia la voz o la música, se usa el fondo ya pintado.
if (!process.env.REUSAR_FONDO) {
const b = await chromium.launch({ channel: 'chrome' });
const p = await b.newPage({ viewport: { width: 1080, height: 1920 }, deviceScaleFactor: 1 });
await p.goto('http://localhost:8098/promo.html');
await p.evaluate(async (l) => { window.linea = l; await document.fonts.ready; }, linea);
await p.waitForLoadState('networkidle');
const ff = spawn('ffmpeg', ['-y', '-v', 'error', '-f', 'image2pipe', '-c:v', 'mjpeg', '-framerate', String(FPS), '-i', '-',
  '-c:v', 'libx264', '-preset', 'medium', '-crf', '16', '-pix_fmt', 'yuv420p', fondo], { stdio: ['pipe', 'inherit', 'inherit'] });
const cuadros = Math.ceil(total * FPS);
for (let f = 0; f < cuadros; f++) {
  await p.evaluate((x) => window.pintar(x), f / FPS);
  const img = await p.screenshot({ type: 'jpeg', quality: 92 });
  if (!ff.stdin.write(img)) await new Promise((ok) => ff.stdin.once('drain', ok));
  if (f % 150 === 0) console.log(`cuadro ${f}/${cuadros}`);
}
ff.stdin.end();
await new Promise((ok) => ff.on('close', ok));
await b.close();
}
servidor.close();

// 3. Tomas de la app dentro del teléfono, voces y música (más baja mientras se habla).
const entradas = ['-i', fondo];
const grafo = [];
let base = '[0:v]', n = 1;
for (const [i, e] of escenas.entries()) {
  if (!e.clip) continue;
  const [archivo, desde, hasta] = e.clip;
  const [a, z] = linea[i];
  const inicio = a + 0.7, largo = z - 0.05 - inicio, fuente = hasta - desde;
  entradas.push('-ss', String(desde), '-t', String(fuente), '-i', join(videos, archivo));
  grafo.push(`[${n}:v]crop=876:1616:102:240,scale=720:1328,setpts=${(largo / fuente).toFixed(4)}*(PTS-STARTPTS),fps=${FPS},format=yuva420p,` +
    `fade=t=in:st=0:d=0.3:alpha=1,fade=t=out:st=${(largo - 0.35).toFixed(2)}:d=0.35:alpha=1,setpts=PTS+${inicio.toFixed(3)}/TB[c${n}]`);
  grafo.push(`${base}[c${n}]overlay=180:460:eof_action=pass[v${n}]`);
  base = `[v${n}]`; n++;
}
const musica = [join(videos, MUSICA), join(videos, 'musica.mp3')].find(existsSync) ?? '';
const conMusica = existsSync(musica);
if (conMusica) entradas.push('-i', musica);
const iMusica = n; if (conMusica) n++;
escenas.forEach((e) => entradas.push('-i', e.audio));
escenas.forEach((e, i) => {
  const ms = Math.round((e.inicio + 0.35) * 1000);
  grafo.push(`[${n + i}:a]adelay=${ms}|${ms},aresample=48000[a${i}]`);
});
grafo.push(`${escenas.map((_, i) => `[a${i}]`).join('')}amix=inputs=${escenas.length}:normalize=0,apad[voz]`);
if (conMusica) {
  grafo.push('[voz]asplit[va][vb]',
    `[${iMusica}:a]atrim=0:${total},asetpts=N/SR/TB,volume=0.25,afade=t=in:d=1,afade=t=out:st=${Math.max(0, total - 3)}:d=3,aresample=48000[m]`,
    '[m][vb]sidechaincompress=threshold=0.02:ratio=6:attack=30:release=600[md]',
    `[md][va]amix=inputs=2:normalize=0,atrim=0:${total},loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000[audio]`);
} else grafo.push(`[voz]atrim=0:${total}[audio]`);

execFileSync('ffmpeg', ['-y', '-v', 'error', ...entradas, '-filter_complex', grafo.join(';'), '-map', base, '-map', '[audio]',
  '-c:v', 'libx264', '-preset', 'slow', '-crf', '20', '-pix_fmt', 'yuv420p', '-r', String(FPS), '-t', String(total),
  '-c:a', 'aac', '-b:a', '160k', '-movflags', '+faststart', salida]);
console.log('Listo:', salida);
