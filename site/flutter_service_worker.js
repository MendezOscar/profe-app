// Interruptor de apagado (igual que en stock-ruta).
//
// Cuando el panel vivía en la raíz, Flutter pudo registrar aquí su service worker con
// alcance sobre todo el sitio. Ahora la app vive en /app: ese worker viejo serviría un
// index cuyos assets ya no existen y la pantalla se quedaría en el splash. Los
// navegadores vuelven a pedir este archivo; basta con que se desregistre y limpie.
self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(names.map((name) => caches.delete(name)));
    await self.registration.unregister();

    const clients = await self.clients.matchAll({ type: 'window' });
    for (const client of clients) client.navigate(client.url);
  })());
});
