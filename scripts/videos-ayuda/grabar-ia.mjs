// Graba la toma de «Sugerir el plan con IA» para el video promocional (videos-ayuda/ia-rubrica.mp4).
// Necesita la API local con Anthropic:ApiKey en sus user-secrets, el docente demo con plan Pro
// (tenants.con_ia) y la sección 2 de Ciencias Naturales con el Parcial I sin plan (tiene programa oficial
// de Básica: el diálogo muestra el recuadro «Programa oficial»). Gasta una sugerencia de IA (~L 1).
//   DEMO_PASSWORD=… node grabar-ia.mjs
import { chromium } from 'playwright-core';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const aqui = new URL('.', import.meta.url).pathname;
const clave = process.env.DEMO_PASSWORD;
if (!clave) throw new Error('Falta DEMO_PASSWORD (la contraseña del docente demo local).');
const salida = join(aqui, '../../videos-ayuda/ia-rubrica.mp4');
const OX = 55, OY = 124;

const b = await chromium.launch({ channel: 'chrome' });
const ctx = await b.newContext({ viewport: { width: 1080, height: 1920 }, deviceScaleFactor: 1,
  recordVideo: { dir: join(tmpdir(), 'profeapp-ia'), size: { width: 1080, height: 1920 } } });
const p = await ctx.newPage();
const t0 = Date.now();
const marca = () => (Date.now() - t0) / 1000;
const espera = (ms) => p.waitForTimeout(ms);
const toque = async (x, y, ms = 1200) => { await p.evaluate(([a, c]) => window.verToque(a, c), [OX + x, OY + y]); await p.mouse.click(2 * (OX + x), 2 * (OY + y)); await espera(ms); };
const rueda = async (dy) => { await p.mouse.move(2 * (OX + 215), 2 * (OY + 450)); await p.mouse.wheel(0, dy); };

await p.goto('http://localhost:8099/tutorial.html');
await p.evaluate(() => { window.quitarPortada(); document.getElementById('app').src = '/app/'; });
await espera(6000);
await toque(219, 290, 600); await p.keyboard.type('docente@demo.hn'); await toque(219, 350, 600); await p.keyboard.type(clave);
await p.keyboard.press('Enter'); await espera(5000);
await rueda(1400); await espera(1500); await toque(150, 450, 3000); // tarjeta de la sección 2
// El aviso de la IA sale la primera vez en este navegador: se acepta y se deja fuera de la toma.
await toque(219, 520, 2500); await toque(327, 606, 5000); await toque(215, 587, 1500); // «Acepto» y luego «Cancelar»

// Tramo 1: el plan vacío → «Sugerir el plan con IA» → el recuadro del programa oficial → «Sugerir».
const a1 = marca();
await espera(1200);
await toque(219, 520, 3500);
await espera(2500);
await toque(315, 587, 1500);
const z1 = marca();

// Tramo 2: la propuesta del asistente → recorrerla → agregarla al plan.
await espera(40000);
const a2 = marca();
await espera(1500);
for (let i = 0; i < 6; i++) { await rueda(120); await espera(450); }
await espera(800);
await toque(215, 764, 3500);
const z2 = marca();

const v = p.video(); await p.close(); await ctx.close(); await b.close();
const crudo = await v.path();
console.log('tramos', { a1, z1, a2, z2 });
execFileSync('ffmpeg', ['-y', '-v', 'error', '-i', crudo, '-filter_complex',
  `[0:v]trim=${a1}:${z1},setpts=PTS-STARTPTS[x];[0:v]trim=${a2}:${z2},setpts=PTS-STARTPTS[y];[x][y]concat=n=2:v=1:a=0,fps=30[v]`,
  '-map', '[v]', '-c:v', 'libx264', '-crf', '18', '-pix_fmt', 'yuv420p', salida]);
console.log('Listo:', salida);
