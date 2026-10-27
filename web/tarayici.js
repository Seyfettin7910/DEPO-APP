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

// Kamera yakınlaştırma (web): tarayıcı destekliyorsa video izinin "zoom"u.
function depoVideoIzi() {
  var videolar = Array.prototype.slice.call(document.querySelectorAll('video'));
  // Flutter platform görünümleri gölge DOM içinde olabilir.
  document.querySelectorAll('*').forEach(function (e) {
    if (e.shadowRoot) {
      videolar = videolar.concat(Array.prototype.slice.call(
        e.shadowRoot.querySelectorAll('video')));
    }
  });
  for (var i = videolar.length - 1; i >= 0; i--) {
    var s = videolar[i].srcObject;
    if (s && s.getVideoTracks) {
      var izler = s.getVideoTracks();
      if (izler.length && izler[0].readyState === 'live') return izler[0];
    }
  }
  return null;
}

// Destekleniyorsa "min,max" (ör. "1,10"), değilse "".
function depoZoomAraligi() {
  try {
    var iz = depoVideoIzi();
    if (!iz || !iz.getCapabilities) return '';
    var k = iz.getCapabilities();
    if (!k || !k.zoom) return '';
    return k.zoom.min + ',' + k.zoom.max;
  } catch (e) { return ''; }
}

function depoZoomAyarla(oran) {
  try {
    var iz = depoVideoIzi();
    if (!iz) return Promise.resolve(false);
    return iz.applyConstraints({ advanced: [{ zoom: oran }] })
      .then(function () { return true; })
      .catch(function () { return false; });
  } catch (e) { return Promise.resolve(false); }
}

// 1.30.4: bilgisayar tarayıcısında dosyayı indirir (Excel raporu).
function depoDosyaIndir(baytlar, ad, tur) {
  try {
    var blob = new Blob([baytlar], { type: tur });
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url;
    a.download = ad;
    a.style.display = 'none';
    document.body.appendChild(a);
    a.click();
    setTimeout(function () {
      URL.revokeObjectURL(url);
      a.remove();
    }, 2000);
    return true;
  } catch (e) { return false; }
}
