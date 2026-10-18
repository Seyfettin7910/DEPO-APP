import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_service.dart';

/// Hareketsizlikte oturumu kapatır ve giriş ekranını gösterir.
///
/// - Uygulama açıkken [sure] boyunca dokunma/tuş yoksa oturum kapanır.
/// - Uygulama arka planda/kapalıyken [sure] geçtiyse, dönüşte giriş istenir.
/// - İnternet yokken de çalışır: ekran hemen kilitlenir, sunucudan çıkış
///   bağlantı gelince denenir. (Tekrar giriş için internet gerekir.)
class OturumKilidi extends ChangeNotifier with WidgetsBindingObserver {
  OturumKilidi._();
  static final OturumKilidi instance = OturumKilidi._();

  /// Hareketsizlik süresi.
  static const sure = Duration(minutes: 5);

  static const _kilitAnahtari = 'oturum_kilitli';
  static const _etkinlikAnahtari = 'son_etkinlik_ms';

  bool _kilitli = false;
  bool get kilitli => _kilitli;

  /// Son kilitlenmenin nedeni (giriş ekranında bilgi olarak gösterilir).
  String? sonSebep;

  DateTime _sonEtkinlik = DateTime.now();
  DateTime _sonKayit = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _zamanlayici;
  bool _basladi = false;

  bool get _girisVar =>
      SupabaseService.client.auth.currentSession != null && !_kilitli;

  /// Açılışta bir kez çağrılır (Supabase hazırlandıktan sonra).
  Future<void> baslat() async {
    if (_basladi) return;
    _basladi = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _kilitli = prefs.getBool(_kilitAnahtari) ?? false;
      final ms = prefs.getInt(_etkinlikAnahtari);
      if (ms != null) _sonEtkinlik = DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {}

    // Uygulama kapalıyken süre dolduysa doğrudan giriş iste.
    if (_girisVar && DateTime.now().difference(_sonEtkinlik) > sure) {
      await kilitle(sebep: _zamanAsimiMesaji);
    } else {
      etkinlik();
    }

    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_tusBasildi);
    _zamanlayici =
        Timer.periodic(const Duration(seconds: 15), (_) => _denetle());
  }

  static const _zamanAsimiMesaji =
      '5 dakika işlem yapılmadığı için oturum kapandı. Tekrar giriş yapın.';

  /// Kullanıcı ekrana dokunduğunda / tuşa bastığında çağrılır.
  void etkinlik() {
    if (_kilitli) return;
    _sonEtkinlik = DateTime.now();
    // Diske en fazla 20 sn'de bir yaz.
    if (_sonEtkinlik.difference(_sonKayit) > const Duration(seconds: 20)) {
      _sonKayit = _sonEtkinlik;
      _kaydet();
    }
  }

  bool _tusBasildi(KeyEvent e) {
    etkinlik(); // USB barkod okuyucu da klavye gibi yazar
    return false;
  }

  void _denetle() {
    if (_girisVar && DateTime.now().difference(_sonEtkinlik) > sure) {
      kilitle(sebep: _zamanAsimiMesaji);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _denetle();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _sonKayit = _sonEtkinlik;
      _kaydet();
    }
  }

  /// Oturumu kapatır ve giriş ekranına döner. İnternet yoksa bile ekran
  /// kilitlenir; sunucudaki oturum kapatma denemesi arka planda yapılır.
  Future<void> kilitle({String? sebep}) async {
    sonSebep = sebep;
    _kilitli = true;
    notifyListeners();
    await _kaydet();
    try {
      await SupabaseService.cikisYap().timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Sunucudan çıkış yapılamadı (kilit yine de aktif): $e');
    }
  }

  /// Başarılı girişten sonra çağrılır.
  Future<void> kilidiAc() async {
    _kilitli = false;
    sonSebep = null;
    _sonEtkinlik = DateTime.now();
    _sonKayit = _sonEtkinlik;
    notifyListeners();
    await _kaydet();
  }

  Future<void> _kaydet() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kilitAnahtari, _kilitli);
      await prefs.setInt(
          _etkinlikAnahtari, _sonEtkinlik.millisecondsSinceEpoch);
    } catch (_) {}
  }
}
