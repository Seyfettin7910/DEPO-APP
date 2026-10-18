// Web bildirimi (iPhone / bilgisayar tarayıcısı) yardımcıları. Dart tarafı
// bu global fonksiyonları çağırır.
(function () {
  var KAPSAM = './push/';

  function anahtarBaytlari(b64) {
    var p = '='.repeat((4 - (b64.length % 4)) % 4);
    var s = atob((b64 + p).replace(/-/g, '+').replace(/_/g, '/'));
    var a = new Uint8Array(s.length);
    for (var i = 0; i < s.length; i++) a[i] = s.charCodeAt(i);
    return a;
  }

  function aktifOlsun(kayit) {
    if (kayit.active) return Promise.resolve(kayit);
    return new Promise(function (bitti) {
      var sw = kayit.installing || kayit.waiting;
      if (!sw) return bitti(kayit);
      sw.addEventListener('statechange', function () {
        if (sw.state === 'activated') bitti(kayit);
      });
    });
  }

  window.depoPushDestek = function () {
    return 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
  };
  window.depoPushIos = function () {
    return /iphone|ipad|ipod/i.test(navigator.userAgent) ||
      (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  };
  window.depoPushAnaEkran = function () {
    return window.navigator.standalone === true ||
      window.matchMedia('(display-mode: standalone)').matches;
  };
  window.depoPushIzin = function () {
    return ('Notification' in window) ? Notification.permission : 'unsupported';
  };

  // İzin ister ve abone olur. Dönen: abonelik JSON metni, izin yoksa ''.
  // iPhone'da kullanıcının bir düğmeye basmasıyla çağrılmalıdır.
  window.depoPushAbone = function (genelAnahtar) {
    return Notification.requestPermission().then(function (izin) {
      if (izin !== 'granted') return '';
      return navigator.serviceWorker.register('push_sw.js', { scope: KAPSAM })
        .then(aktifOlsun)
        .then(function (kayit) {
          return kayit.pushManager.getSubscription().then(function (mevcut) {
            return mevcut || kayit.pushManager.subscribe({
              userVisibleOnly: true,
              applicationServerKey: anahtarBaytlari(genelAnahtar),
            });
          });
        })
        .then(function (abonelik) { return JSON.stringify(abonelik); });
    });
  };

  // Mevcut abonelik (yoksa '')
  window.depoPushMevcut = function () {
    if (!('serviceWorker' in navigator)) return Promise.resolve('');
    return navigator.serviceWorker.getRegistration(KAPSAM).then(function (kayit) {
      if (!kayit) return '';
      return kayit.pushManager.getSubscription().then(function (a) {
        return a ? JSON.stringify(a) : '';
      });
    }).catch(function () { return ''; });
  };

  // Aboneliği bitirir; bitirilen aboneliğin endpoint'ini döndürür
  window.depoPushIptal = function () {
    return navigator.serviceWorker.getRegistration(KAPSAM).then(function (kayit) {
      if (!kayit) return '';
      return kayit.pushManager.getSubscription().then(function (a) {
        if (!a) return '';
        var uc = a.endpoint;
        return a.unsubscribe().then(function () { return uc; });
      });
    }).catch(function () { return ''; });
  };
})();

// Bu cihazda bildirimin göründüğünü denemek için (sunucuya gitmez)
window.depoPushTest = function (baslik, govde) {
  return navigator.serviceWorker.getRegistration('./push/').then(function (kayit) {
    if (!kayit) return false;
    return kayit.showNotification(baslik, { body: govde, icon: 'icons/Icon-192.png' })
      .then(function () { return true; });
  }).catch(function () { return false; });
};
