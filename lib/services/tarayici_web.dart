import 'dart:js_interop';

// web/tarayici.js içindeki global fonksiyonlar
@JS('depoTarayiciAdi')
external JSString _ad();
@JS('depoIos')
external JSBoolean _ios();
@JS('depoAnaEkranda')
external JSBoolean _anaEkran();
@JS('depoKaliciSakla')
external JSPromise<JSBoolean> _kalici();

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
