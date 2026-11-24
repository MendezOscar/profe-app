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
  { voz: 'Importas tus cuadros de SACE, y en un minuto tus alumnos están listos.', clip: ['1-importa-tus-cuadros.mp4', 38, 50] },
  { voz: 'Calificas desde el teléfono, y la nota del parcial se calcula sola.', clip: ['3-califica-una-actividad.mp4', 47, 59] },
  { voz: 'Pasas lista en segundos, y la app sabe qué clases tienes hoy.', clip: ['4-pasa-lista.mp4', 23, 33] },
  { voz: 'Y al cerrar el parcial, la nota total y las inasistencias ya están listas para subir a SACE.', clip: ['5-cierra-y-exporta.mp4', 43, 63] },
  { voz: 'Con el programa oficial de tu asignatura, la IA te arma la rúbrica, con sus actividades y sus puntos.', clip: ['ia-rubrica.mp4', 0, 17.3], min: 7.5 },
  { voz: '¿Y lo mejor? También califica con una foto, prepara tus exámenes y te arma el portafolio. Tú siempre decides.', min: 7 },
  { voz: 'Profe App. Descárgala hoy en App Store o Google Play.', min: 5.5 },
];

const duracion = (f) => Number(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', f]).toString());

// 1. Voz de cada escena; la escena dura lo que la voz más un respiro (las del teléfono, al menos 6.5 s).
let t = 0;
const linea = [];
// Si hay grabaciones propias en videos-ayuda/voz-promo/1 … 8 (.opus, .m4a, .wav o .mp3), se usan en lugar
// de la voz del Mac, pulidas: sin silencios al principio y al final (un clic suelto no cuenta), sin
// ruido de fondo ni retumbe, con más presencia, eses suaves, volumen parejo y sin picos.
const recorte = 'silenceremove=start_periods=1:start_duration=0.08:start_threshold=-42dB:start_silence=0.06';
const pulido = ['highpass=f=85', 'afftdn=nf=-50:tn=1', recorte, 'areverse', recorte, 'areverse',
  'equalizer=f=180:t=q:w=1:g=1.5', 'equalizer=f=400:t=q:w=1.2:g=-2', 'equalizer=f=3500:t=q:w=1.4:g=2.5',
  'deesser=i=0.4', 'acompressor=threshold=-22dB:ratio=3:attack=8:release=120:makeup=4', 'loudnorm=I=-18:TP=-2:LRA=7',
  'alimiter=limit=0.89', 'aresample=48000'].join(',');
escenas.forEach((e, i) => {
  const propia = ['opus', 'm4a', 'wav', 'mp3'].map((x) => join(videos, 'voz-promo', `${i + 1}.${x}`)).find(existsSync);
  e.audio = join(tmp, `voz${i}.wav`);
  if (propia) execFileSync('ffmpeg', ['-y', '-v', 'error', '-i', propia, '-af', pulido, '-ar', '48000', e.audio]);
  else execFileSync('say', ['-v', VOZ, '-r', '170', '--data-format=LEI16@48000', '-o', e.audio, e.voz]);
  const largo = Math.max(e.min ?? 6.5, duracion(e.audio) + 1.1);
  linea.push([t, t + largo]);
  e.inicio = t;
  t += largo;
});
const total = t;
console.log('Duración:', total.toFixed(1), 's');
if (total > 59) console.warn(`Ojo: dura ${total.toFixed(1)} s, más de un minuto con el respiro final. Graba las frases más ágiles.`);

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
