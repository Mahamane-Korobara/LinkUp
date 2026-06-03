/* Service worker du dashboard Linkup — PWA installable + cache app-shell.
 *
 * Stratégie : stale-while-revalidate pour les GET MÊME-ORIGINE non-API. On
 * IGNORE complètement `/api/*` (données dynamiques : /api/files polled, /api/
 * files/{id}/raw = médias lourds) — important car dans le bundle PC le dashboard
 * et l'API partagent la même origine (localhost:8000). Cross-origin (API en dev
 * sur :8000) : non intercepté non plus.
 */
const CACHE = 'linkup-dash-v1';
const SHELL = [
  '/devices',
  '/files',
  '/send',
  '/pair',
  '/clipboard',
  '/manifest.webmanifest',
  '/icons/icon-192.png',
  '/icons/icon-512.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE)
      .then((cache) => cache.addAll(SHELL))
      .catch(() => {}),
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))),
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  // Ne JAMAIS intercepter l'API (dynamique + médias), quelle que soit l'origine.
  if (url.pathname.startsWith('/api/')) return;
  // Ne gérer que la même origine (les assets/pages du dashboard).
  if (url.origin !== self.location.origin) return;

  event.respondWith(
    caches.match(request).then((cached) => {
      const network = fetch(request)
        .then((res) => {
          if (res && res.status === 200) {
            const copy = res.clone();
            caches.open(CACHE).then((cache) => cache.put(request, copy));
          }
          return res;
        })
        .catch(() => cached);
      return cached || network;
    }),
  );
});
