import 'dart:js_interop';
import 'dart:typed_data';

// web/tarayici.js içindeki global fonksiyonlar
@JS('depoTarayiciAdi')
external JSString _ad();
@JS('depoIos')
external JSBoolean _ios();
@JS('depoAnaEkranda')
external JSBoolean _anaEkran();
@JS('depoKaliciSakla')
external JSPromise<JSBoolean> _kalici();
@JS('depoZoomAraligi')
external JSString _zoomAraligi();
@JS('depoZoomAyarla')
external JSPromise<JSBoolean> _zoomAyarla(JSNumber oran);
@JS('depoDosyaIndir')
external JSBoolean _dosyaIndir(JSUint8Array baytlar, JSString ad, JSString tur);

T _guvenli<T>(T Function() f, T varsayilan) {
  try {
    return f();
  } catch (_) {
    return varsayilan; // tarayici.js yüklenmemiş (eski önbellek) vb.
  }
}

/// "Safari", "Chrome", "Edge", "Firefox"…
String tarayiciAdi() => _guvenli(() => _ad().toDart, '');

/// iPhone / iPad tarayıcısı mı?
bool iosTarayici() => _guvenli(() => _ios().toDart, false);

/// Ana ekrana eklenmiş (uygulama gibi, tam ekran) açıldı mı?
bool anaEkranda() => _guvenli(() => _anaEkran().toDart, false);

/// Safari'nin kullanılmayan sitelerin verisini silmemesi için kalıcı saklama.
Future<bool> kaliciSaklamaIste() async {
  try {
    return (await _kalici().toDart).toDart;
  } catch (_) {
    return false;
  }
}

/// Kamera yakınlaştırması destekleniyorsa (min, max) oranı; değilse null.
(double, double)? webZoomAraligi() {
  final t = _guvenli(() => _zoomAraligi().toDart, '');
  final p = t.split(',');
  if (p.length != 2) return null;
  final min = double.tryParse(p[0]);
  final max = double.tryParse(p[1]);
  if (min == null || max == null || max <= min) return null;
  return (min, max);
}

/// Kamera yakınlaştırmasını [oran]a (1, 2, 3…) ayarlar.
Future<bool> webZoomAyarla(double oran) async {
  try {
    return (await _zoomAyarla(oran.toJS).toDart).toDart;
  } catch (_) {
    return false;
  }
}

/// 1.30.4: dosyayı tarayıcıda indirir (Excel raporu). Olmazsa false.
bool dosyaIndir(Uint8List baytlar, String ad, String tur) =>
    _guvenli(() => _dosyaIndir(baytlar.toJS, ad.toJS, tur.toJS).toDart, false);
