// 改了任何檔案後，把版本號 +1（v3、v4…），手機才會抓到新版
const CACHE = 'lunaria-v3';
const ASSETS = ['./', './index.html', './manifest.webmanifest', './icons/icon-192.png', './icons/icon-512.png', './icons/apple-touch-icon.png'];
const CDN = ['cdn.jsdelivr.net', 'fonts.googleapis.com', 'fonts.gstatic.com'];
self.addEventListener('install', e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS))); self.skipWaiting(); });
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))));
  self.clients.claim();
});
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  const url = new URL(e.request.url);
  const mine = url.origin === location.origin && url.pathname.startsWith(new URL('./', location).pathname);
  if (!mine && !CDN.includes(url.hostname)) return; // Supabase 等 API 一律不快取
  e.respondWith(
    fetch(e.request).then(r => {
      if (r.ok || r.type === 'opaque') { const cp = r.clone(); caches.open(CACHE).then(c => c.put(e.request, cp)); }
      return r;
    }).catch(() => caches.match(e.request).then(m => m || (mine ? caches.match('./index.html') : Response.error())))
  );
});
