// Graba los videos de ayuda sobre el panel local (cuenta demo). Cada video es una página del mismo contexto.
// Pasos en docs/videos-ayuda.md. Las coordenadas son de la app a 430 × 800 (tamaño de teléfono).
import { chromium } from 'playwright-core';
import { mkdirSync, renameSync, rmSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
const aqui = new URL('.', import.meta.url).pathname;
const OX = 55, OY = 124;
const salida = process.env.SALIDA ?? `${aqui}../../videos-ayuda`;
const fotos = `${tmpdir()}/profeapp-videos/fotos`;
mkdirSync(salida, { recursive: true }); mkdirSync(fotos, { recursive: true });
const cuadros = [`${aqui}cuadros/CIENCIAS_NATURALES_SECCION_1.xlsx`, `${aqui}cuadros/CIENCIAS_NATURALES_SECCION_2.xlsx`];
const b = await chromium.launch({ channel: 'chrome' });
const ctx = await b.newContext({ viewport: { width: 1080, height: 1920 }, deviceScaleFactor: 1, acceptDownloads: true,
  recordVideo: { dir: `${tmpdir()}/profeapp-videos/crudo`, size: { width: 1080, height: 1920 } } });

let p;
const espera = (ms) => p.waitForTimeout(ms);
const foto = (n) => p.screenshot({ path: `${fotos}/${n}.png` });
const toque = async (x, y, ms = 1200) => { await p.evaluate(([a, b]) => window.verToque(a, b), [OX + x, OY + y]); await p.mouse.click(2 * (OX + x), 2 * (OY + y)); await espera(ms); };
const escribe = async (t) => { await p.keyboard.type(t, { delay: 85 }); await espera(400); };
const paso = async (n, t, ms = 2600) => { await p.evaluate(([a, b]) => window.verPaso(a, b), [n, t]); await espera(Math.max(ms, await narrar(t))); };

// Narración: una frase por paso con la voz del Mac; se espera a que termine antes del siguiente toque.
// Al cerrar cada video, ffmpeg la mezcla con la música (más baja mientras se habla) y saca un .mp4.
const tmp = `${tmpdir()}/profeapp-videos/voz`; mkdirSync(tmp, { recursive: true });
const musica = `${salida}/musica.mp3`;
let voz, inicio, frases;
const hablado = (t) => t.replace(/ProfeApp/g, 'Profe App').replace(/→/g, ',').replace(/[«»]/g, '').replace(/NOTA TOTAL/g, 'nota total').replace(/INASISTENCIAS/g, 'inasistencias');
const duracion = (f) => Number(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', f]).toString());
async function narrar(t) {
  if (!voz) return 0;
  const f = `${tmp}/${Date.now()}-${frases.length}.aiff`;
  execFileSync('say', ['-v', voz, '-r', '172', '-o', f, hablado(t)]);
  frases.push({ f, ms: Date.now() - inicio });
  return duracion(f) * 1000 + 500;
}
function mezclar(webm, mp4) {
  const total = duracion(webm);
  const entradas = ['-i', webm];
  if (existsSync(musica)) entradas.push('-i', musica);
  frases.forEach((x) => entradas.push('-i', x.f));
  const base = existsSync(musica) ? 2 : 1;
  const voces = frases.map((x, i) => `[${base + i}:a]adelay=${x.ms}|${x.ms},aresample=48000[v${i}]`);
  const mezclaVoz = `${frases.map((_, i) => `[v${i}]`).join('')}amix=inputs=${frases.length}:normalize=0,apad[voz]`;
  const grafo = existsSync(musica)
    ? [...voces, mezclaVoz, '[voz]asplit[va][vb]',
       `[1:a]atrim=0:${total},asetpts=N/SR/TB,volume=0.2,afade=t=in:d=1.5,afade=t=out:st=${Math.max(0, total - 3)}:d=3,aresample=48000[m]`,
       '[m][vb]sidechaincompress=threshold=0.02:ratio=8:attack=30:release=600[md]',
       `[md][va]amix=inputs=2:normalize=0,atrim=0:${total},loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000[a]`]
    : [...voces, mezclaVoz.replace('[voz]', `,atrim=0:${total}[a]`)];
  execFileSync('ffmpeg', ['-y', '-v', 'error', ...entradas, '-filter_complex', grafo.join(';'), '-map', '0:v', '-map', '[a]',
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '20', '-pix_fmt', 'yuv420p', '-r', '30', '-c:a', 'aac', '-b:a', '160k', '-movflags', '+faststart', mp4]);
}
const rueda = async (dy) => { await p.mouse.move(2 * (OX + 215), 2 * (OY + 450)); await p.mouse.wheel(0, dy); await espera(1200); };

async function video(nombre, k, titulo, sub, cuerpo) {
  voz = nombre ? 'Paulina' : null;
  frases = [];
  p = await ctx.newPage();
  inicio = Date.now();
  p.on('pageerror', (e) => console.log(nombre, 'ERROR', e.message.slice(0, 150)));
  await p.goto('http://localhost:8099/tutorial.html');
  await p.evaluate(([a, b, c]) => window.verPortada(a, b, c), [k, titulo, sub]);
  await p.evaluate(() => { document.getElementById('app').src = '/app/'; });
  const portada = Date.now();
  const habla = await narrar(`${titulo}. ${sub}`);
  await espera(Math.max(9000, habla) - (Date.now() - portada));
  await p.evaluate(() => window.quitarPortada()); await espera(800);
  await cuerpo();
  await espera(2500);
  const v = p.video(); await p.close();
  if (nombre) {
    const crudo = await v.path();
    mezclar(crudo, `${salida}/${nombre}.mp4`); rmSync(crudo, { force: true });
    console.log('ok', `${salida}/${nombre}.mp4`);
  }
  else rmSync(await v.path(), { force: true });
}

const etapas = (process.env.ETAPAS ?? '1,2,3,4,p,5').split(',');

if (etapas.includes('1')) await video('1-importa-tus-cuadros', 'Video 1 de 5', 'Importa tus cuadros de SACE', 'Tus asignaturas y alumnos en la app, en un minuto.', async () => {
  await paso('Paso 1', 'Entra con el correo y la contraseña que te dio ProfeApp o tu centro educativo.', 1500);
  await toque(219, 351, 600); await escribe('docente@demo.hn');
  await toque(219, 411, 600); await escribe('Demo1234!');
  await p.keyboard.press('Enter'); await espera(5000); await foto('1a');
  await paso('Paso 2', 'En SACE, ve a Notas → Descargar Archivos Notas y baja el cuadro de cada asignatura.', 4500);
  await paso('Paso 3', 'Toca «Importar cuadros de SACE» y elige todos tus archivos a la vez.', 2200);
  const fc = p.waitForEvent('filechooser');
  await toque(215, 510, 300); await (await fc).setFiles(cuadros); await espera(3500); await foto('1b');
  await paso('Paso 4', 'Elige una rúbrica para empezar. Después la ajustas en cada asignatura.', 3500);
  await toque(200, 450, 3500); await foto('1c');
  await paso('Listo', 'Tus asignaturas y alumnos ya están en la app. Funciona aunque no tengas internet.', 2500);
  await rueda(380); await espera(2500); await foto('1d');
});

if (etapas.includes('2')) await video('2-arma-tu-rubrica', 'Video 2 de 5', 'Arma la rúbrica del parcial', 'Rubros y puntos que suman 100, a tu manera.', async () => {
  await paso('Paso 1', 'En Inicio, toca la asignatura que quieres preparar.', 2200);
  await toque(150, 525, 2500); await foto('2a');
  await paso('Paso 2', 'En «Plan» ves la rúbrica del parcial: cada rubro con sus puntos.', 3500);
  await paso('Paso 3', 'Toca un rubro para cambiar su nombre o sus puntos.', 2000);
  await toque(200, 260, 1500);
  await toque(190, 414, 600); await p.keyboard.press('Meta+A'); await escribe('25');
  await toque(300, 502, 2000); await foto('2b');
  await paso('Paso 4', 'Si la rúbrica no llega a 100, la app te dice cuántos puntos faltan.', 3500);
  await paso('Paso 5', 'Con «Agregar rubro» sumas lo que necesites, como participación.', 2000);
  await toque(215, 640, 1500); await escribe('Participación');
  await toque(290, 502, 2500); await foto('2c');
  await paso('Listo', 'La rúbrica suma 100. Cada parcial y cada sección pueden tener la suya.', 3500);
});

if (etapas.includes('3')) await video('3-califica-una-actividad', 'Video 3 de 5', 'Crea una actividad y califica', 'Tareas, trabajos y exámenes, alumno por alumno.', async () => {
  await paso('Paso 1', 'Entra a la asignatura y abre la pestaña «Actividades».', 1800);
  await toque(150, 525, 2500); await toque(113, 143, 2000);
  await paso('Paso 2', 'Toca «Nueva actividad»: ponle nombre, elige el rubro y cuántos puntos vale.', 1800);
  await toque(215, 592, 1500); await escribe('Tarea 1: La célula');
  await toque(110, 414, 600); await p.keyboard.press('Meta+A'); await escribe('10'); await foto('3a');
  await toque(324, 566, 2500); await foto('3b');
  await paso('Paso 3', 'Toca la actividad para calificarla.', 1800);
  await toque(150, 250, 2500);
  await paso('Paso 4', 'Escribe la nota y pasa al siguiente alumno. No hace falta guardar.', 1500);
  await toque(361, 177, 500);
  for (const n of ['9', '8.5', '10', '7', '9.5', '8', '10']) { await p.keyboard.type(n, { delay: 120 }); await espera(250); await p.keyboard.press('Enter'); await espera(450); }
  await foto('3c');
  await paso('Listo', 'Arriba ves cuántos llevas y el promedio. Lo que falte queda pendiente.', 3500);
});

if (etapas.includes('4')) await video('4-pasa-lista', 'Video 4 de 5', 'Pasa lista en segundos', 'Marcas solo a los que faltan.', async () => {
  await paso('Paso 1', 'Toca «Asistencia» abajo y elige la sección.', 1800);
  await toque(161, 760, 1800); await toque(200, 111, 2500); await foto('4a');
  await paso('Paso 2', 'Todos empiezan presentes. Toca a un alumno para marcarlo ausente.', 2000);
  await toque(353, 417, 1800);
  await paso('Paso 3', 'Toca otra vez para «Tarde», y otra más para «Justificada».', 1500);
  await toque(353, 470, 900); await toque(353, 470, 1500);
  await toque(353, 587, 700); await toque(353, 587, 700); await toque(353, 587, 1500); await foto('4b');
  await paso('Paso 4', 'Arriba ves el conteo del día. Las ausencias pasan solas a INASISTENCIAS.', 3800);
  await paso('Listo', 'Con el reloj de arriba revisas o corriges días anteriores.', 3000);
});

const entrarSiHaceFalta = async () => {
  const f = p.frames().find((x) => x.url().includes('/app/'));
  if (!f.url().includes('/login')) return;
  await toque(219, 351, 600); await escribe('docente@demo.hn'); await toque(219, 411, 600); await escribe('Demo1234!');
  await p.keyboard.press('Enter'); await espera(5000);
};
const nota = () => String(Math.round((6 + Math.random() * 4) * 2) / 2);
if (etapas.includes('l')) await video(null, '', 'Entrando', '', entrarSiHaceFalta);
if (etapas.includes('p')) await video(null, '', 'Preparando', '', async () => {
  await entrarSiHaceFalta();
  await rueda(900); await toque(150, 440, 2500); await toque(113, 143, 2000);
  await toque(215, 592, 1500); await p.keyboard.type('Tarea 1'); await toque(324, 566, 2000);
  for (const [y, t] of [[397, 'Trabajo en clase 1'], [445, 'Proyecto: maqueta de la célula'], [493, 'Examen del parcial']]) {
    await toque(330, 756, 1500); await toque(215, 350, 1000); await toque(150, y, 800); await toque(215, 286, 300);
    await p.keyboard.type(t); await toque(324, 566, 2000);
  }
  for (const [y, max] of [[306, 30], [430, 20], [554, 20], [678, 30]]) {
    await toque(150, y, 2000); await toque(361, 177, 400);
    for (let i = 0; i < 22; i++) { await p.keyboard.type(String(Math.round(max * (0.55 + Math.random() * 0.45) * 2) / 2)); await p.keyboard.press('Enter'); await espera(120); }
    await espera(800); await toque(28, 28, 1500);
  }
  await foto('p1');
  await toque(330, 28, 1000); await toque(330, 28, 2500);
  await toque(345, 230, 1500); await toque(353, 355, 800); await toque(353, 589, 800); await foto('p2');
  await toque(28, 28, 2000); await toque(54, 760, 2000);
});

if (etapas.includes('5')) await video('5-cierra-y-exporta', 'Video 5 de 5', 'Cierra el parcial y exporta para SACE', 'NOTA TOTAL e INASISTENCIAS, listas para subir.', async () => {
  await paso('Paso 1', 'En Inicio, entra a la asignatura del parcial que vas a cerrar.', 1500);
  await rueda(900); await toque(150, 440, 2500);
  await paso('Paso 2', 'En «Notas» ves la nota de cada alumno: la suma de sus puntos.', 1500);
  await toque(201, 143, 3000); await foto('5a');
  await paso('Paso 3', 'Toca a un alumno para ver de dónde sale su nota.', 1500);
  await toque(200, 330, 3500); await foto('5b');
  await toque(215, 120, 1500);
  await paso('Paso 4', 'Cuando termines, toca «Cerrar parcial». La app revisa que no falte nada.', 1800);
  await toque(86, 264, 3000); await foto('5c');
  await toque(308, 486, 2500); await foto('5d');
  await paso('Paso 5', 'La nota y las faltas de cada alumno pasan solas al cuadro de SACE. Toca «Exportar».', 3000);
  await toque(76, 320, 3000); await foto('5e');
  await paso('Paso 6', 'Revisa el cuadro: NOTA TOTAL e INASISTENCIAS ya están llenas.', 1500);
  await toque(360, 84, 3500); await foto('5f');
  await paso('Paso 7', 'Toca el botón de exportar y guarda el archivo.', 1500);
  const d = p.waitForEvent('download', { timeout: 15000 }).catch(() => null);
  await toque(369, 28, 3000); console.log('descarga', (await d)?.suggestedFilename()); await foto('5g');
  await paso('Listo', 'Súbelo en SACE: Notas → Cargar Archivos Notas.', 4000);
});
await b.close();
