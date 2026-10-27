// Bildirim service worker'ı (yalnızca bildirimler için; sayfaları önbelleğe almaz).
// Kapsamı "./push/" olduğu için Flutter'ın kendi service worker'ıyla çakışmaz.

self.addEventListener('install', function () { self.skipWaiting(); });
self.addEventListener('activate', function (e) { e.waitUntil(self.clients.claim()); });

self.addEventListener('push', function (event) {
  var veri = {};
  try { veri = event.data ? event.data.json() : {}; } catch (_) {
    veri = { baslik: 'DEPO YÖNETİM SİSTEMİ', govde: event.data ? event.data.text() : '' };
  }
  var baslik = veri.baslik || 'DEPO YÖNETİM SİSTEMİ';
  event.waitUntil(self.registration.showNotification(baslik, {
    body: veri.govde || '',
    icon: 'icons/Icon-192.png',
    badge: 'icons/Icon-maskable-192.png',
    tag: (veri.tur || 'depo') + ':' + baslik,
    data: { url: veri.url || '../' },
  }));
});

self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  var hedef = new URL((event.notification.data && event.notification.data.url) || '../', self.registration.scope).href;
  event.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (pencereler) {
    for (var i = 0; i < pencereler.length; i++) {
      var p = pencereler[i];
      if (p.url.indexOf(new URL('../', self.registration.scope).href) === 0 && 'focus' in p) return p.focus();
    }
    return self.clients.openWindow(hedef);
  }));
});
