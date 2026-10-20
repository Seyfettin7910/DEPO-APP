import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'konum_servisi.dart';

/// Montaj ekranı açıkken GPS'i ısıtır ve konumu sürekli yeniler; kaydedilen
/// konum, "Kaydet"e basıldığı ANDAKİ konumdur (ekranın açıldığı yerin değil).
/// Yalnızca ekran açıkken çalışır; arka planda konum alınmaz.
class KonumIzleyici extends ChangeNotifier {
  /// Bu kadar yeni ve bu kadar hassas okuma "hazır" sayılır.
  static const tazelik = Duration(seconds: 5);
  static const iyiHassasiyet = 20.0; // metre
  static const enFazlaBekleme = Duration(seconds: 20);

  StreamSubscription<Position>? _akis;
  Position? _son; // GPS akışından gelen son okuma
  Position? _hazirKonum; // telefonun bildiği son konum (yaklaşık, anında)
  String? hata;
  bool _kapandi = false;

  /// Göstergede kullanılan en son okuma (yoksa telefonun bildiği son konum).
  Position? get gosterilen => _son ?? _hazirKonum;

  /// Akıştan taze okuma var mı (yaklaşık "son konum" değil).
  bool get gpsVar => _son != null;

  Future<void> baslat() async {
    final h = await KonumServisi.izinHatasi();
    if (_kapandi) return;
    if (h != null) {
      hata = h;
      notifyListeners();
      return;
    }
    // Telefonun hazır tuttuğu son konum: gösterge hemen dolsun (web'de yok).
    if (!kIsWeb) {
      try {
        _hazirKonum = await Geolocator.getLastKnownPosition();
        if (!_kapandi) notifyListeners();
      } catch (_) {}
    }
    try {
      _akis = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        ),
      ).listen((p) {
        _son = p;
        hata = null;
        if (!_kapandi) notifyListeners();
      }, onError: (Object e) {
        hata = 'Konum alınamadı';
        if (!_kapandi) notifyListeners();
      });
    } catch (_) {
      hata = 'Konum alınamadı';
      notifyListeners();
    }
  }

  bool _taze(Position p) =>
      DateTime.now().difference(p.timestamp).abs() <= tazelik;

  /// "Kaydet" anındaki konum: taze ve hassas okuma varsa hemen döner; yoksa
  /// en fazla [enFazlaBekleme] bekler, en iyi okumayı döner. Hiç okuma
  /// gelmezse hatalı sonuç döner (çağıran "Konumsuz kaydet" diye sorar).
  /// [kalanSaniye] her saniye bildirilir ("Konum bekleniyor… (8 sn)").
  Future<KonumSonucu> kaydetAnindakiKonum(
      {void Function(int kalanSaniye)? kalanSaniye}) async {
    final s0 = _son;
    if (s0 != null && _taze(s0) && s0.accuracy <= iyiHassasiyet) {
      return KonumSonucu.basarili(s0.latitude, s0.longitude, s0.accuracy);
    }
    final bitis = DateTime.now().add(enFazlaBekleme);
    Position? enIyi = (s0 != null && _taze(s0)) ? s0 : null;
    while (DateTime.now().isBefore(bitis) && !_kapandi) {
      kalanSaniye?.call(bitis.difference(DateTime.now()).inSeconds + 1);
      await Future.delayed(const Duration(milliseconds: 500));
      final p = _son;
      if (p == null || !_taze(p)) continue;
      if (enIyi == null || p.accuracy < enIyi.accuracy) enIyi = p;
      if (p.accuracy <= iyiHassasiyet) break;
    }
    final e = enIyi;
    if (e == null) {
      return KonumSonucu.hatali(hata ?? 'Konum bulunamadı');
    }
    return KonumSonucu.basarili(e.latitude, e.longitude, e.accuracy);
  }

  @override
  void dispose() {
    _kapandi = true;
    _akis?.cancel();
    super.dispose();
  }
}
