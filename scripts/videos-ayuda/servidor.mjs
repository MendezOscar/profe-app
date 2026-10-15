// Sirve el panel (mobile/build/web, compilado con --base-href /app/ contra la API local) y la página que enmarca los videos.
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join } from 'node:path';
const aqui = new URL('.', import.meta.url).pathname;
const web = join(aqui, '../../mobile/build/web');
const fuentes = join(aqui, '../../mobile/assets/fonts');
const tipos = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png', '.svg': 'image/svg+xml', '.ttf': 'font/ttf', '.otf': 'font/otf', '.css': 'text/css', '.ico': 'image/x-icon' };
http.createServer(async (q, r) => {
  const ruta = decodeURIComponent(new URL(q.url, 'http://x').pathname);
  const archivo = ruta === '/tutorial.html' ? join(aqui, 'tutorial.html')
    : ruta.endsWith('.ttf') && !ruta.startsWith('/app/') ? join(fuentes, ruta)
    : ruta.startsWith('/app') ? join(web, extname(ruta) ? ruta.slice(4) : '/index.html') : null;
  try { r.writeHead(200, { 'content-type': tipos[extname(archivo)] ?? 'application/octet-stream' }); r.end(await readFile(archivo)); }
  catch { r.writeHead(404); r.end(); }
}).listen(8099, () => console.log('http://localhost:8099/tutorial.html'));
