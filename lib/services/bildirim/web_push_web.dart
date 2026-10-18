import 'dart:js_interop';

// web/push.js içindeki global fonksiyonlar
@JS('depoPushDestek')
external JSBoolean _destek();
@JS('depoPushIos')
external JSBoolean _ios();
@JS('depoPushAnaEkran')
external JSBoolean _anaEkran();
@JS('depoPushIzin')
external JSString _izin();
@JS('depoPushAbone')
external JSPromise<JSString> _abone(JSString genelAnahtar);
@JS('depoPushMevcut')
external JSPromise<JSString> _mevcut();
@JS('depoPushIptal')
external JSPromise<JSString> _iptal();
@JS('depoPushTest')
external JSPromise<JSBoolean> _test(JSString baslik, JSString govde);

T _guvenli<T>(T Function() f, T varsayilan) {
  try {
    return f();
  } catch (_) {
    return varsayilan; // push.js yüklenmemiş (eski önbellek) vb.
  }
}

bool webPushDestek() => _guvenli(() => _destek().toDart, false);
bool webPushIos() => _guvenli(() => _ios().toDart, false);
bool webPushAnaEkran() => _guvenli(() => _anaEkran().toDart, false);
String webPushIzin() => _guvenli(() => _izin().toDart, 'unsupported');

/// İzin ister ve abone olur (düğmeye basılınca, araya bekleme koymadan
/// çağrılmalı; iPhone bunu şart koşar). İzin verilmezse ''.
Future<String> webPushAbone(String genelAnahtar) async =>
    (await _abone(genelAnahtar.toJS).toDart).toDart;

Future<String> webPushMevcut() async {
  try {
    return (await _mevcut().toDart).toDart;
  } catch (_) {
    return '';
  }
}

Future<String> webPushIptal() async {
  try {
    return (await _iptal().toDart).toDart;
  } catch (_) {
    return '';
  }
}

Future<bool> webPushTest(String baslik, String govde) async {
  try {
    return (await _test(baslik.toJS, govde.toJS).toDart).toDart;
  } catch (_) {
    return false;
  }
}
