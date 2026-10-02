// Enrutado del sitio: landing y páginas legales en la raíz, panel Flutter bajo /app.
//
// Un worker y no _redirects: una regla `/app/* -> index` también se come los assets
// (flutter_bootstrap.js volvía como HTML y la app no arrancaba). Igual que en stock-ruta.
// Fuentes e imágenes casi no cambian: el navegador las guarda una semana sin volver a
// preguntar. El resto (index, main.dart.js, wasm, canvaskit) no lleva hash en el nombre
// y debe revalidarse, o un despliegue nuevo quedaría mezclado con archivos viejos.
const CACHE_LARGA = /\.(ttf|otf|woff2?|png|jpe?g|svg|ico|webp)$/i;

// Política de seguridad (CSP). El sitio no tiene scripts; el panel Flutter necesita
// WebAssembly (base local y CanvasKit, que Flutter baja de gstatic) y hablar con la API.
const SITIO = 'https://profeapphn.com';
const API = 'https://api.profeapphn.com';
const COMUNES = "base-uri 'self'; object-src 'none'; frame-ancestors 'none'; form-action 'self'";
const CSP_SITIO = `default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; ${COMUNES}`;
const CSP_PANEL = [
  "default-src 'self'",
  "script-src 'self' 'wasm-unsafe-eval' https://www.gstatic.com",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob:",
  "font-src 'self' data: https://fonts.gstatic.com",
  `connect-src 'self' ${API} https://www.gstatic.com https://fonts.gstatic.com`,
  "worker-src 'self' blob:",
  COMUNES,
].join('; ');

function conSeguridad(respuesta, pathname) {
  const headers = new Headers(respuesta.headers);
  headers.set('content-security-policy', pathname.startsWith('/app/') ? CSP_PANEL : CSP_SITIO);
  headers.set('x-content-type-options', 'nosniff');
  headers.set('referrer-policy', 'strict-origin-when-cross-origin');
  headers.set('strict-transport-security', 'max-age=31536000');
  headers.set('permissions-policy', 'camera=(), microphone=(), geolocation=()');
  if (respuesta.ok && CACHE_LARGA.test(pathname)) {
    headers.set('cache-control', 'public, max-age=604800, stale-while-revalidate=86400');
  }
  return new Response(respuesta.body, { status: respuesta.status, statusText: respuesta.statusText, headers });
}

async function servir(request, env) {
  return conSeguridad(await env.ASSETS.fetch(request), new URL(request.url).pathname);
}

const RUTAS_DEL_PANEL = ['/login', '/inicio', '/asistencia', '/plantillas', '/cuenta', '/bienvenida', '/splash', '/centro', '/plataforma', '/cambiar-clave'];

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // Un solo dominio: el de pages.dev y el www llevan a profeapphn.com. Las vistas previas
    // de cada rama (<hash>.profe-app.pages.dev) no se tocan.
    if (url.hostname === 'profe-app.pages.dev' || url.hostname === 'www.profeapphn.com') {
      return Response.redirect(`${SITIO}${url.pathname}${url.search}`, 301);
    }

    // Antes el panel vivía en la raíz: los enlaces y marcadores viejos siguen entrando.
    if (RUTAS_DEL_PANEL.some((r) => url.pathname === r || url.pathname.startsWith(`${r}/`))) {
      return Response.redirect(`${url.origin}/app${url.pathname}${url.search}`, 301);
    }

    // El base href del panel es /app/: sin la barra final los assets se piden en la raíz.
    if (url.pathname === '/app') return Response.redirect(`${url.origin}/app/${url.search}`, 301);

    if (url.pathname.startsWith('/app/')) {
      // Con extensión es un archivo del bundle; sin ella, una ruta que resuelve go_router.
      // No se puede preguntar por el 404: cuando falta el archivo, Pages responde la
      // landing con 200 y recargar el panel mostraría la página de inicio.
      if (/\.[a-z0-9]+$/i.test(url.pathname)) return servir(request, env);

      const index = await env.ASSETS.fetch(new URL('/app/index.html', url.origin));
      const html = new Response(index.body, {
        status: 200,
        headers: { ...Object.fromEntries(index.headers), 'content-type': 'text/html; charset=utf-8' },
      });
      return conSeguridad(html, url.pathname);
    }

    return servir(request, env);
  },
};
