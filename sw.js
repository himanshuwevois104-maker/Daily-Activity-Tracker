/* Network-first so a redeploy lands immediately; cache is only a fallback. */
const CACHE = 'wevois-tracker-v2';
self.addEventListener('install', e => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(
  caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k))))
    .then(() => self.clients.claim())));
self.addEventListener('fetch', e => {
  const u = new URL(e.request.url);
  if (e.request.method !== 'GET' || u.origin !== location.origin) return;   // never cache Supabase
  e.respondWith(
    fetch(e.request).then(r => {
      const copy = r.clone();
      caches.open(CACHE).then(c => c.put(e.request, copy)).catch(() => {});
      return r;
    }).catch(() => caches.match(e.request))
  );
});

/* Clicking a desktop notification brings the tracker back to the front and
   opens the task it was about, instead of starting a second copy of the app. */
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const taskId = (e.notification.data && e.notification.data.taskId) || null;
  e.waitUntil((async () => {
    const all = await self.clients.matchAll({type:'window', includeUncontrolled:true});
    const mine = all.filter(c => c.url.startsWith(self.registration.scope));
    if (mine.length) {
      const c = mine[0];
      await c.focus();
      c.postMessage({type:'open-task', taskId});
      return;
    }
    if (self.clients.openWindow) {
      await self.clients.openWindow(taskId ? './index.html#task=' + taskId : './index.html');
    }
  })());
});
