// Tarayıcı bilgisi (Flutter tarafı: lib/services/tarayici_web.dart)
function depoTarayiciAdi() {
  var ua = navigator.userAgent || '';
  var ios = /iPad|iPhone|iPod/.test(ua) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  if (ios) {
    if (/CriOS/.test(ua)) return 'Chrome';
    if (/FxiOS/.test(ua)) return 'Firefox';
    if (/EdgiOS/.test(ua)) return 'Edge';
    if (/OPiOS|OPT\//.test(ua)) return 'Opera';
    if (/GSA\//.test(ua)) return 'Google uygulaması';
    if (/YaBrowser/.test(ua)) return 'Yandex';
    if (/Instagram|FBAN|FBAV|WhatsApp/.test(ua)) return 'Uygulama içi tarayıcı';
    return 'Safari';
  }
  if (/Edg\//.test(ua)) return 'Edge';
  if (/OPR\//.test(ua)) return 'Opera';
  if (/YaBrowser/.test(ua)) return 'Yandex';
  if (/Firefox\//.test(ua)) return 'Firefox';
  if (/SamsungBrowser/.test(ua)) return 'Samsung Internet';
  if (/Chrome\//.test(ua)) return 'Chrome';
  if (/Safari\//.test(ua)) return 'Safari';
  return 'Tarayıcı';
}

function depoIos() {
  var ua = navigator.userAgent || '';
  return /iPad|iPhone|iPod/.test(ua) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
}

// Ana ekrana eklenmiş (uygulama gibi) açıldı mı?
function depoAnaEkranda() {
  try {
    return window.navigator.standalone === true ||
      window.matchMedia('(display-mode: standalone)').matches;
  } catch (e) { return false; }
}

// Safari kullanılmayan sitelerin verisini silebilir: kalıcı saklama iste.
function depoKaliciSakla() {
  try {
    if (navigator.storage && navigator.storage.persist) {
      return navigator.storage.persist().then(function (v) { return !!v; })
        .catch(function () { return false; });
    }
  } catch (e) {}
  return Promise.resolve(false);
}
