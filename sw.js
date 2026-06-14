// ═══ 老花之友 — Service Worker v0.1 ═══
const CACHE = 'laohuazhiyou-v1';
const FILES = [
  '/',
  '/index.html',
  '/css/style.css',
  '/js/app.js',
  '/manifest.json',
  '/icons/icon-192.png',
  '/icons/icon-512.png',
];

// 安装: 缓存核心文件
self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(c => c.addAll(FILES))
  );
  self.skipWaiting();
});

// 激活: 清理旧缓存
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

// 拦截: 缓存优先，网络回退
self.addEventListener('fetch', e => {
  e.respondWith(
    caches.match(e.request).then(cached =>
      cached || fetch(e.request).catch(() => cached)
    )
  );
});
