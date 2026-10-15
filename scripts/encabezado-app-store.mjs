// Encabezado de la ficha (21:9) y tarjeta de resultados de búsqueda (3:2) de la App Store, en JPEG
// convertidos a PNG sin canal alfa (Apple rechaza el .jpg en el encabezado y no acepta transparencia). Una idea, centrada: Apple recorta los bordes según el equipo.
import { chromium } from 'playwright-core';
import { readFileSync, mkdirSync, rmSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
const repo = new URL('..', import.meta.url).pathname.replace(/\/$/, '');
const b64 = (ruta, tipo) => `data:${tipo};base64,${readFileSync(`${repo}/${ruta}`).toString('base64')}`;
const fuente = (f) => b64(`mobile/assets/fonts/${f}`, 'font/ttf');
const cap = (n) => b64(`docs/tiendas/capturas/iphone-6.9/${n}.png`, 'image/png');
const salida = `${repo}/docs/tiendas/app-store`;
mkdirSync(salida, { recursive: true });

const piezas = [
  { archivo: 'encabezado-3840x1646', w: 3840, h: 1646, titulo: 'Tus notas listas para subir a SACE', sub: 'Califica, pasa lista y cierra el parcial. Sin internet.', tel: 760, tam: 150 },
  { archivo: 'resultados-busqueda-3840x2560', w: 3840, h: 2560, titulo: 'Tus notas listas para subir a SACE', sub: 'Califica, pasa lista y cierra el parcial. Sin internet.', tel: 960, tam: 190 },
];
const b = await chromium.launch({ channel: 'chrome' });
for (const { archivo, w, h, titulo, sub, tel, tam } of piezas) {
  const p = await (await b.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: 1 })).newPage();
  const borde = Math.round(tel * 0.03);
  await p.setContent(`<style>
    @font-face{font-family:A;src:url(${fuente('Archivo-ExtraBold.ttf')});font-weight:800}
    @font-face{font-family:A;src:url(${fuente('Archivo-SemiBold.ttf')});font-weight:600}
    *{margin:0}body{width:${w}px;height:${h}px;overflow:hidden;background:#2B59C3;font-family:A;color:#fff;text-align:center}
    h1{font-weight:800;font-size:${tam}px;letter-spacing:-0.02em;padding-top:${h * 0.07}px}
    p{font-weight:600;font-size:${tam * 0.42}px;opacity:.92;margin-top:${tam * 0.2}px}
    .tels{display:flex;justify-content:center;align-items:flex-start;gap:${tel * 0.12}px;margin-top:${h * 0.05}px}
    img{width:${tel}px;border:${borde}px solid #14213D;box-shadow:0 ${tel * 0.04}px ${tel * 0.1}px rgba(0,0,0,.3)}
    img.c{margin-top:-${tel * 0.08}px}
  </style><h1>${titulo}</h1><p>${sub}</p>
  <div class="tels"><img src="${cap('5-estadisticas')}"><img class="c" src="${cap('1-inicio')}"><img src="${cap('2-calificar')}"></div>`);
  await p.evaluate(() => document.fonts.ready);
  const jpg = `${salida}/${archivo}.jpg`;
  await p.screenshot({ path: jpg, type: 'jpeg', quality: 95 });
  execFileSync('sips', ['-s', 'format', 'png', jpg, '--out', `${salida}/${archivo}.png`]);
  rmSync(jpg);
}
await b.close();
