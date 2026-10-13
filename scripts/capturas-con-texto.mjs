// Capturas de tienda con leyenda: fondo azul de marca, título y subtítulo en Archivo y la captura debajo.
import { chromium } from 'playwright-core';
import { readFileSync, mkdirSync } from 'node:fs';
const repo = new URL('..', import.meta.url).pathname.replace(/\/$/, '');
const fuente = (f) => `data:font/ttf;base64,${readFileSync(`${repo}/mobile/assets/fonts/${f}`).toString('base64')}`;
const textos = {
  '1-inicio': ['Todo tu periodo de un vistazo', 'Y funciona sin internet'],
  '2-calificar': ['Califica en segundos', 'Alumno por alumno, con el teclado numérico'],
  '3-plan': ['Arma tu rúbrica por puntos', 'Tareas, trabajos y exámenes hasta sumar 100'],
  '4-pasar-lista': ['Pasa lista con un toque', 'Las faltas llegan solas al cuadro'],
  '5-estadisticas': ['Detecta a tiempo quién va en riesgo', 'Promedio, notas y asistencia del grupo'],
  '6-libro-de-notas': ['Tu libro de notas, siempre a mano', 'Todas las notas del parcial en una tabla'],
  '7-cuadro-sace': ['Exporta el cuadro listo para SACE', 'NOTA TOTAL e INASISTENCIAS, ya llenas'],
};
const equipos = { 'iphone-6.9': [1320, 2868], 'ipad-13': [2064, 2752], 'android-telefono': [1080, 2400] };
const b = await chromium.launch({ channel: 'chrome' });
for (const [equipo, [w, h]] of Object.entries(equipos)) {
  const p = await (await b.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: 1 })).newPage();
  const salida = `${repo}/docs/tiendas/capturas-con-texto/${equipo}`;
  mkdirSync(salida, { recursive: true });
  const ancho = Math.round(w * (equipo === 'ipad-13' ? 0.86 : 0.84)); const k = equipo === 'ipad-13' ? 0.72 : 1;
  for (const [nombre, [titulo, sub]] of Object.entries(textos)) {
    const img = `data:image/png;base64,${readFileSync(`${repo}/docs/tiendas/capturas/${equipo}/${nombre}.png`).toString('base64')}`;
    await p.setContent(`<style>
      @font-face{font-family:A;src:url(${fuente('Archivo-ExtraBold.ttf')});font-weight:800}
      @font-face{font-family:A;src:url(${fuente('Archivo-SemiBold.ttf')});font-weight:600}
      *{margin:0}body{width:${w}px;height:${h}px;overflow:hidden;background:#2B59C3;font-family:A;color:#fff;text-align:center}
      h1{font-weight:800;font-size:${w * 0.072 * k}px;line-height:1.08;letter-spacing:-0.02em;padding:${h * 0.055}px ${w * 0.07}px 0}
      p{font-weight:600;font-size:${w * 0.038 * k}px;line-height:1.3;opacity:.92;margin-top:${h * 0.016}px;padding:0 ${w * 0.08}px}
      img{display:block;width:${ancho}px;margin:${h * 0.04}px auto 0;border:${Math.round(w * 0.012)}px solid #14213D;box-shadow:0 ${w * 0.02}px ${w * 0.06}px rgba(0,0,0,.25)}
    </style><h1>${titulo}</h1><p>${sub}</p><img src="${img}">`);
    await p.evaluate(() => document.fonts.ready);
    await p.screenshot({ path: `${salida}/${nombre}.png` });
  }
}
await b.close();
