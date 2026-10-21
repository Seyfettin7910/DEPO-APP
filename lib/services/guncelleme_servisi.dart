import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'guncelleme/apk_kurucu.dart' as apk;
import 'taslak_servisi.dart';

/// Uygulama güncellemeleri.
///
/// - Yeni sürüm çıkınca **güncelleme penceresi** açılır (telefon ve web).
///   - Normal sürümde "Şimdi güncelle" ve "Ertele" vardır. Ertele: ilk sefer
///     10 dakika, sonra 30 dakikada bir tekrar sorar. Bir işin ortasındaysan
///     (sayım, toplu transfer, giriş, sahada kullanım / arıza penceresi)
///     pencere o iş bitince gelir.
///   - Zorunlu sürümde pencere kapanmaz; yarım kalan iş taslak olarak
///     kaydedilir, güncellemeden sonra kaldığı yerden sürdürülür.
/// - **Android:** yeni sürüm Wi-Fi'deyken arka planda indirilir. "Şimdi
///   güncelle" deyince (gerekirse indirilir ve) kendiliğinden kurulur; Android
///   12+ telefonlarda çoğunlukla onay sormaz. Uygulama kapalıyken indirme
///   biterse "Güncelleme indi · kurmak için dokun" bildirimi gelir.
/// - **Web:** "Şimdi güncelle" sayfayı yeni sürümle yeniler.
///
/// Sürüm numarası derlemede gömülür (--dart-define=APP_SURUM); gömülmemişse
/// (ör. FlutLab derlemesi) kontrol yapılmaz.
class GuncellemeServisi {
  static const mevcutSurum = String.fromEnvironment('APP_SURUM');
  static const _repo = 'Seyfettin7910/DEPO-APP';
  static const apkLinki =
      'https://github.com/$_repo/releases/latest/download/Depo-Otomasyon-Sistemi.apk';
  static const _surumDosyasi =
      'https://seyfettin7910.github.io/DEPO-APP/version.json';

  /// MaterialApp'in gezgini: güncelleme penceresi hangi ekranda olunursa
  /// olsun en üstte açılır.
  static final navigatorKey = GlobalKey<NavigatorState>();

  static const _sorguAraligi = Duration(minutes: 30);
  static const _ilkErteleme = Duration(minutes: 10);
  static const _sonrakiErteleme = Duration(minutes: 30);

  static DateTime? _sonSorgu;
  static bool _sorguluyor = false;
  static bool _pencereAcik = false;
  static ({String hedef, bool zorunlu})? _bekleyen;
  static int? _apkBoyutu; // GitHub'daki son APK'nın boyutu (bayt)
  static Timer? _periyodik;
  static Timer? _hatirlatici;
  static bool _isBekleniyor = false;
  static Future<String?>? _arkaIndirme;

  /// İndirme ilerlemesi (inen, toplam).
  static final ilerleme = ValueNotifier<(int, int?)>((0, null));

  /// 40321123 -> "38,5 MB"
  static String boyutMetni(int bayt) {
    final mb = bayt / (1024 * 1024);
    return '${mb.toStringAsFixed(1).replaceAll('.', ',')} MB';
  }

  static String ilerlemeMetni(int alinan, int? toplam) {
    if (toplam == null) return '${boyutMetni(alinan)} indirildi';
    final yuzde = (alinan * 100 / toplam).floor();
    return '${boyutMetni(alinan)} / ${boyutMetni(toplam)}  ·  %$yuzde';
  }

  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static BuildContext? get _baglam =>
      navigatorKey.currentState?.overlay?.context;

  // ------------------------------------------------------------------
  // Sürüm bilgisi
  // ------------------------------------------------------------------

  static Future<Map<String, dynamic>?> _json(Uri uri,
      {Map<String, String>? basliklar}) async {
    try {
      final r = await http
          .get(uri, headers: basliklar)
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      final v = jsonDecode(r.body);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// (en son yayınlanan sürüm, desteklenen en düşük sürüm)
  static Future<(String?, String?)> _surumler() async {
    final t = DateTime.now().millisecondsSinceEpoch;
    if (kIsWeb) {
      final v = await _json(Uri.base.resolve('version.json?t=$t'));
      return (v?['surum'] as String?, v?['min'] as String?);
    }
    final dosya = await _json(Uri.parse('$_surumDosyasi?t=$t'));
    final yayin = await _json(
      Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
      basliklar: {'Accept': 'application/vnd.github+json'},
    );
    final tag =
        (yayin?['tag_name'] as String?)?.replaceFirst(RegExp(r'^v'), '');
    final dosyalar = yayin?['assets'];
    if (dosyalar is List) {
      for (final d in dosyalar) {
        if (d is Map &&
            d['name'] == 'Depo-Otomasyon-Sistemi.apk' &&
            d['size'] is num) {
          _apkBoyutu = (d['size'] as num).toInt();
        }
      }
    }
    return (tag ?? dosya?['surum'] as String?, dosya?['min'] as String?);
  }

  /// Sunucudaki sürümlere göre bekleyen güncelleme (yoksa null).
  static ({String hedef, bool zorunlu})? _degerlendir(
      String? enSon, String? enDusuk) {
    // Telefonda, gereken sürümün APK'sı henüz yayınlanmadıysa zorlamayı
    // beklet (yoksa eski APK'yı tekrar tekrar kurmaya çalışır).
    final zorunlu = enDusuk != null &&
        dahaYeni(enDusuk, mevcutSurum) &&
        (kIsWeb || enSon == null || !dahaYeni(enDusuk, enSon));
    final yeni = enSon != null && dahaYeni(enSon, mevcutSurum);
    if (!yeni && !zorunlu) return null;
    return (hedef: (yeni ? enSon : enDusuk)!, zorunlu: zorunlu);
  }

  /// "1.10.0" > "1.9.2" gibi parça parça karşılaştırma.
  static bool dahaYeni(String a, String b) {
    List<int> parca(String s) => s
        .split('+')
        .first
        .split('.')
        .map((p) => int.tryParse(p.trim()) ?? 0)
        .toList();
    final x = parca(a), y = parca(b);
    for (var i = 0; i < 3; i++) {
      final xi = i < x.length ? x[i] : 0;
      final yi = i < y.length ? y[i] : 0;
      if (xi != yi) return xi > yi;
    }
    return false;
  }

  // ------------------------------------------------------------------
  // Başlatma ve kontrol
  // ------------------------------------------------------------------

  /// Ana ekran açılınca: uygulama açık kaldıkça 30 dakikada bir sorulur.
  static void baslat() {
    _periyodik?.cancel();
    _periyodik = Timer.periodic(_sorguAraligi, (_) => kontrolEt());
  }

  /// Oturum kapanınca (ana ekran kapanınca) zamanlayıcılar durur.
  static void durdur() {
    _periyodik?.cancel();
    _periyodik = null;
    _hatirlatici?.cancel();
    _hatirlatici = null;
  }

  /// Açılışta ([acilis] = true), uygulamaya dönüşte ve 30 dakikada bir
  /// çağrılır. Sunucuya en fazla 30 dakikada bir sorulur.
  static Future<void> kontrolEt({bool acilis = false}) async {
    if (mevcutSurum.isEmpty) return;
    final bildirimden = _android && await apk.bildirimdenKurulum();

    final simdi = DateTime.now();
    final sorulsun = acilis ||
        bildirimden ||
        _sonSorgu == null ||
        simdi.difference(_sonSorgu!) >= _sorguAraligi;
    if (sorulsun && !_sorguluyor) {
      _sorguluyor = true;
      try {
        final (enSon, enDusuk) = await _surumler();
        _sonSorgu = DateTime.now();
        if (enSon != null || enDusuk != null) {
          _bekleyen = _degerlendir(enSon, enDusuk);
        }
      } finally {
        _sorguluyor = false;
      }
    }
    final b = _bekleyen;
    if (b == null) return;

    if (_android) unawaited(_arkaPlandaIndir(b.hedef));

    // Web: sayfa yeni açıldıysa ve yarım iş yoksa sessizce yenile (aynı
    // sürüm için bir kez; tarayıcı önbelleği döngüye sokmasın).
    if (kIsWeb && acilis && !b.zorunlu && !TaslakServisi.isVar) {
      if (await _webOtomatikYenile(b.hedef)) return;
    }
    await _pencereyiGoster(hemenKur: bildirimden);
  }

  /// Menüden "Güncellemeleri denetle": ertelemeyi kaldırır, hemen sorar.
  static Future<void> elleDenetle(BuildContext context) async {
    if (mevcutSurum.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bu derlemede sürüm bilgisi yok, denetlenemiyor')));
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
        content: Text('Güncelleme denetleniyor...'),
        duration: Duration(seconds: 2)));
    final (enSon, enDusuk) = await _surumler();
    _sonSorgu = DateTime.now();
    if (enSon == null && enDusuk == null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('Sunucuya ulaşılamadı, internet bağlantısını '
                'kontrol edin')));
      return;
    }
    _bekleyen = _degerlendir(enSon, enDusuk);
    messenger.hideCurrentSnackBar();
    if (_bekleyen == null) {
      messenger.showSnackBar(
          SnackBar(content: Text('Uygulama güncel (sürüm $mevcutSurum)')));
      return;
    }
    await _erteleyiKaldir();
    await _pencereyiGoster(elle: true);
  }

  // ------------------------------------------------------------------
  // Ertele
  // ------------------------------------------------------------------

  static const _eSurum = 'guncelleme_ertele_surum';
  static const _eBitis = 'guncelleme_ertele_bitis';
  static const _eSayi = 'guncelleme_ertele_sayi';

  static Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  /// Erteleme sürüyorsa kalan süre.
  static Future<Duration?> _erteleKalan(String hedef) async {
    final p = await _prefs();
    if (p == null || p.getString(_eSurum) != hedef) return null;
    final bitis = p.getInt(_eBitis) ?? 0;
    final kalan = bitis - DateTime.now().millisecondsSinceEpoch;
    return kalan > 0 ? Duration(milliseconds: kalan) : null;
  }

  static Future<void> _ertele(String hedef) async {
    final p = await _prefs();
    final sayi =
        (p?.getString(_eSurum) == hedef ? (p?.getInt(_eSayi) ?? 0) : 0) + 1;
    final sure = sayi == 1 ? _ilkErteleme : _sonrakiErteleme;
    await p?.setString(_eSurum, hedef);
    await p?.setInt(_eSayi, sayi);
    await p?.setInt(
        _eBitis, DateTime.now().add(sure).millisecondsSinceEpoch);
    _hatirlat(sure);
  }

  static Future<void> _erteleyiKaldir() async {
    final p = await _prefs();
    await p?.remove(_eBitis);
  }

  static void _hatirlat(Duration sure) {
    _hatirlatici?.cancel();
    _hatirlatici = Timer(sure + const Duration(seconds: 1), () {
      _hatirlatici = null;
      _pencereyiGoster();
    });
  }

  /// Yarım iş bitince (ekrandan çıkılınca / pencere kapanınca) pencereyi aç.
  static void _isBitinceGoster() {
    if (_isBekleniyor) return;
    _isBekleniyor = true;
    void dinle() {
      if (TaslakServisi.isVar) return;
      TaslakServisi.degisti.removeListener(dinle);
      _isBekleniyor = false;
      // Ekran kapanma animasyonu bitsin.
      Future.delayed(const Duration(milliseconds: 800), _pencereyiGoster);
    }

    TaslakServisi.degisti.addListener(dinle);
  }

  // ------------------------------------------------------------------
  // Pencere
  // ------------------------------------------------------------------

  static Future<void> _pencereyiGoster(
      {bool hemenKur = false, bool elle = false}) async {
    final b = _bekleyen;
    if (b == null || _pencereAcik) return;
    if (!b.zorunlu && !hemenKur && !elle) {
      final kalan = await _erteleKalan(b.hedef);
      if (kalan != null) {
        _hatirlat(kalan);
        return;
      }
      if (TaslakServisi.isVar) {
        _isBitinceGoster();
        return;
      }
    }
    final baglam = _baglam;
    if (baglam == null || !baglam.mounted) return;
    // Zorunlu güncellemede iş anında taslağa yazılır (kaybolmasın).
    await TaslakServisi.bekleyenleriYaz();
    if (!baglam.mounted) return;

    var indirildi = false;
    var wifi = true;
    if (_android) {
      indirildi = await apk.indirilmisApk(b.hedef) != null;
      final baglanti = await Connectivity().checkConnectivity();
      wifi = baglanti.contains(ConnectivityResult.wifi) ||
          baglanti.contains(ConnectivityResult.ethernet);
    }
    if (!baglam.mounted || _pencereAcik) return;

    _pencereAcik = true;
    try {
      final ertelendi = await showDialog<bool>(
        context: baglam,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (_) => _GuncellemePenceresi(
          hedef: b.hedef,
          zorunlu: b.zorunlu,
          hemenKur: hemenKur,
          indirildi: indirildi,
          wifi: wifi,
          boyut: _apkBoyutu,
        ),
      );
      if (ertelendi == true) await _ertele(b.hedef);
    } finally {
      _pencereAcik = false;
    }
  }

  // ------------------------------------------------------------------
  // Web
  // ------------------------------------------------------------------

  static Future<bool> _webOtomatikYenile(String hedef) async {
    const anahtar = 'oto_yenileme_denenen';
    final p = await _prefs();
    if (p?.getString(anahtar) == hedef) return false;
    await p?.setString(anahtar, hedef);
    final baglam = _baglam;
    if (baglam != null && baglam.mounted) {
      ScaffoldMessenger.maybeOf(baglam)?.showSnackBar(SnackBar(
        content: Text('Yeni sürüm ($hedef) yükleniyor...'),
        duration: const Duration(seconds: 3),
      ));
    }
    await Future.delayed(const Duration(milliseconds: 1500));
    await sayfayiYenile(hedef);
    return true;
  }

  static Future<void> sayfayiYenile(String hedef) => launchUrl(
        Uri.base.removeFragment().replace(queryParameters: {'v': hedef}),
        webOnlyWindowName: '_self',
      );

  // ------------------------------------------------------------------
  // Android
  // ------------------------------------------------------------------

  /// Wi-Fi'deyken yeni sürümü sessizce indirir (Android indirme yöneticisi;
  /// uygulama kapansa da sürer). Bitince pencere hazır olarak açılır.
  static Future<void> _arkaPlandaIndir(String hedef) async {
    if (_arkaIndirme != null) return;
    if (await apk.indirilmisApk(hedef) != null) return;
    final baglanti = await Connectivity().checkConnectivity();
    final wifi = baglanti.contains(ConnectivityResult.wifi) ||
        baglanti.contains(ConnectivityResult.ethernet);
    final suruyor = await apk.indiriliyorMu(hedef);
    if (!wifi && !suruyor) return;
    final f = apk.apkIndir(apkLinki, hedef,
        (a, t) => ilerleme.value = (a, t ?? _apkBoyutu),
        sadeceWifi: !suruyor);
    _arkaIndirme = f;
    try {
      await f;
      // İndirme bitti: pencere (ertelenmemişse, iş yoksa) açılır.
      unawaited(_pencereyiGoster());
    } catch (e) {
      debugPrint('Güncelleme arka planda indirilemedi: $e');
    } finally {
      _arkaIndirme = null;
    }
  }

  /// Pencereden "Şimdi güncelle": indirilmemişse hemen (mobil veride de)
  /// indirir; yolu döndürür.
  static Future<String> _simdiIndir(String hedef) async {
    final hazir = await apk.indirilmisApk(hedef);
    if (hazir != null) return hazir;
    // Wi-Fi bekleyen indirme varsa iptal edip her ağda yeniden başlat.
    await apk.duraklamisIseIptal(hedef);
    return apk.apkIndir(
        apkLinki, hedef, (a, t) => ilerleme.value = (a, t ?? _apkBoyutu));
  }

  // ------------------------------------------------------------------
  // Arka plan (uygulama kapalıyken) yeni sürüm bildirimi
  // ------------------------------------------------------------------

  static const _arkaSorguAnahtari = 'arka_surum_kontrol_ms';
  static const _bildirilenAnahtari = 'surum_bildirildi';

  /// Arka plan görevinden çağrılır (görev ~15 dakikada bir çalışır; en fazla
  /// 10 dakikada bir sorar). Yalnızca kendi sürüm dosyamıza bakar, GitHub'a
  /// sormaz (aynı internet çıkışındaki çok telefon sorgu sınırına takılmasın).
  /// Bu sürüm için daha önce bildirim gösterilmediyse (hedef, zorunlu) döner.
  static Future<({String hedef, bool zorunlu})?> arkaPlandaDenetle() async {
    if (mevcutSurum.isEmpty) return null;
    final p = await _prefs();
    if (p == null) return null;
    final simdi = DateTime.now().millisecondsSinceEpoch;
    final son = p.getInt(_arkaSorguAnahtari) ?? 0;
    if (simdi - son < const Duration(minutes: 10).inMilliseconds) return null;
    await p.setInt(_arkaSorguAnahtari, simdi);
    final dosya = await _json(Uri.parse('$_surumDosyasi?t=$simdi'));
    final enSon = dosya?['surum'] as String?;
    final enDusuk = dosya?['min'] as String?;
    final b = _degerlendir(enSon, enDusuk);
    if (b == null) return null;
    final isaret = '${b.hedef}${b.zorunlu ? '+z' : ''}';
    if (p.getString(_bildirilenAnahtari) == isaret) return null;
    await p.setString(_bildirilenAnahtari, isaret);
    return b;
  }
}

enum _Asama { soru, indiriliyor, izin, kuruluyor, hata }

class _GuncellemePenceresi extends StatefulWidget {
  const _GuncellemePenceresi({
    required this.hedef,
    required this.zorunlu,
    required this.hemenKur,
    required this.indirildi,
    required this.wifi,
    required this.boyut,
  });

  final String hedef;
  final bool zorunlu;
  final bool hemenKur;
  final bool indirildi;
  final bool wifi;
  final int? boyut;

  @override
  State<_GuncellemePenceresi> createState() => _GuncellemePenceresiState();
}

class _GuncellemePenceresiState extends State<_GuncellemePenceresi>
    with WidgetsBindingObserver {
  var _asama = _Asama.soru;
  String? _hata;
  String? _yol;
  bool _uzunSurdu = false;
  Timer? _kurulumZamanlayici;

  // Kurulum onayı (sistem ekranı) takibi
  StreamSubscription<Map<String, dynamic>>? _olayAboneligi;
  bool _onayBekliyor = false;
  bool _onayAcildi = false; // onay ekranı açıldı (uygulama arka plana geçti)
  bool _onayAcilmadi = false; // açılamadı: düğmeler gösterilir
  Timer? _onayZamanlayici;

  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_android) {
      _olayAboneligi = apk.kurulumOlaylari.listen(_kurulumOlayi);
    }
    if (widget.hemenKur) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _guncelle());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _kurulumZamanlayici?.cancel();
    _onayZamanlayici?.cancel();
    _olayAboneligi?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Onay ekranı öne geldi
      if (_onayBekliyor) _onayAcildi = true;
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    // Yükleyici açılmıştı ve uygulamaya geri dönüldü: kurulum yapılmadı
    // (vazgeçildi ya da yükleyici izin istedi). Kurulsaydı uygulama kapanırdı.
    if (_asama == _Asama.kuruluyor && _onayBekliyor && _onayAcildi) {
      _onayZamanlayici?.cancel();
      setState(() {
        _onayBekliyor = false;
        _uzunSurdu = true;
      });
      return;
    }
    // Kurulum izni ekranından dönüldü: izin verildiyse hemen kur.
    if (_asama == _Asama.izin) {
      apk.kurulumIzniVar().then((izinVar) {
        if (izinVar && mounted) _kur();
      });
    }
  }

  void _kurulumOlayi(Map<String, dynamic> olay) {
    if (!mounted || _asama != _Asama.kuruluyor) return;
    final durum = olay['durum'] as String?;
    final mesaj = (olay['mesaj'] as String?)?.trim();
    _kurulumZamanlayici?.cancel();
    switch (durum) {
      case 'onay_bekleniyor':
        setState(() {
          _onayBekliyor = true;
          _onayAcildi = false;
          _onayAcilmadi = false;
        });
        // 3 sn içinde onay ekranı öne gelmediyse açılamamıştır.
        _onayZamanlayici?.cancel();
        _onayZamanlayici = Timer(const Duration(seconds: 3), () {
          if (mounted && _onayBekliyor && !_onayAcildi) {
            setState(() => _onayAcilmadi = true);
          }
        });
      case 'basarili':
        setState(() => _onayBekliyor = false);
      default:
        final metin = switch (durum) {
          'iptal' => 'Kurulum onaylanmadı (iptal edildi).',
          'yer_yok' => 'Telefonda yeterli boş yer yok. Biraz yer açıp '
              'tekrar deneyin.',
          'bozuk' => 'İndirilen dosya bozuk; tekrar denerseniz yeniden '
              'indirilir.',
          'uyumsuz' => 'Bu sürüm bu telefona kurulamıyor (uyumsuz).',
          'cakisma' => 'Kurulum, telefondaki sürümle çakıştı.',
          'engellendi' => 'Kurulum telefon tarafından engellendi.',
          _ => 'Kurulum tamamlanamadı.',
        };
        if (durum == 'bozuk' && _yol != null) {
          apk.apkSil(_yol!);
          _yol = null;
        }
        setState(() {
          _asama = _Asama.hata;
          _onayBekliyor = false;
          _hata = mesaj == null || mesaj.isEmpty ? metin : '$metin\n($mesaj)';
        });
    }
  }

  Future<void> _guncelle() async {
    await TaslakServisi.bekleyenleriYaz();
    if (kIsWeb) {
      await GuncellemeServisi.sayfayiYenile(widget.hedef);
      return;
    }
    if (!_android) {
      await launchUrl(Uri.parse(GuncellemeServisi.apkLinki),
          mode: LaunchMode.externalApplication);
      if (mounted && !widget.zorunlu) Navigator.pop(context, false);
      return;
    }
    setState(() {
      _asama = _Asama.indiriliyor;
      _hata = null;
    });
    try {
      _yol = await GuncellemeServisi._simdiIndir(widget.hedef);
    } catch (e) {
      if (mounted) {
        setState(() {
          _asama = _Asama.hata;
          _hata = 'İndirilemedi: $e';
        });
      }
      return;
    }
    if (mounted) await _kur();
  }

  Future<void> _kur() async {
    final yol = _yol;
    if (yol == null) {
      await _guncelle();
      return;
    }
    try {
      // Telefonun kendi yükleyicisi açılır; "bilinmeyen kaynak" izni
      // gerekirse onu yükleyici kendisi sorar.
      await TaslakServisi.bekleyenleriYaz();
      if (!mounted) return;
      setState(() {
        _asama = _Asama.kuruluyor;
        _uzunSurdu = false;
        _onayBekliyor = false;
        _onayAcildi = false;
        _onayAcilmadi = false;
      });
      await apk.apkKur(yol);
      // Hiç sonuç gelmezse (beklenmedik) tekrar denenebilsin.
      _kurulumZamanlayici?.cancel();
      _kurulumZamanlayici = Timer(const Duration(seconds: 15), () {
        if (mounted && _asama == _Asama.kuruluyor && !_onayBekliyor) {
          setState(() => _uzunSurdu = true);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _asama = _Asama.hata;
          _hata = 'Kurulum başlatılamadı: $e';
        });
      }
    }
  }

  String get _boyutMetni => widget.boyut == null
      ? ''
      : GuncellemeServisi.boyutMetni(widget.boyut!);

  /// Kurulum sürerken kullanıcının bir şey yapması gerekiyor mu?
  bool get _takildi =>
      _asama == _Asama.kuruluyor && (_onayAcilmadi || _uzunSurdu);

  Widget _icerik(BuildContext context) {
    final mevcut = GuncellemeServisi.mevcutSurum;
    final kucuk = Theme.of(context).textTheme.bodySmall;
    switch (_asama) {
      case _Asama.soru:
        final satirlar = <String>[
          if (widget.zorunlu)
            'Bu sürüm ($mevcut) artık kullanılamıyor. Devam etmek için '
                '${widget.hedef} sürümüne güncelleyin.'
          else
            'Sürüm ${widget.hedef} hazır (şu an: $mevcut).',
          'Güncelleme birkaç saniye sürer; veriler ve gönderilmemiş '
              'kayıtlar silinmez.',
          if (TaslakServisi.isVar || widget.zorunlu)
            'Yarım kalan işiniz kaydedildi; güncellemeden sonra kaldığınız '
                'yerden devam edebilirsiniz.',
          if (_android && !widget.indirildi && !widget.wifi)
            'Wi-Fi yok: ${_boyutMetni.isEmpty ? 'güncelleme' : _boyutMetni} '
                'mobil veriyle inecek.',
        ];
        return Text(satirlar.join('\n\n'));
      case _Asama.indiriliyor:
        return ValueListenableBuilder<(int, int?)>(
          valueListenable: GuncellemeServisi.ilerleme,
          builder: (_, d, __) {
            final toplam = d.$2 ?? widget.boyut;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(
                    value: toplam == null || toplam == 0
                        ? null
                        : (d.$1 / toplam).clamp(0.0, 1.0),
                    minHeight: 8),
                const SizedBox(height: 10),
                Text(
                  d.$1 == 0
                      ? 'İndirme başlıyor...'
                      : GuncellemeServisi.ilerlemeMetni(d.$1, toplam),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text('İndirme bitince kurulum kendiliğinden başlar.',
                    textAlign: TextAlign.center, style: kucuk),
              ],
            );
          },
        );
      case _Asama.izin:
        return const Text(
            'Uygulamanın kendini güncelleyebilmesi için bir kez izin '
            'gerekiyor.\n\nAçılacak ekranda "Bu kaynaktan izin ver"i açıp '
            'geri dönün; kurulum kendiliğinden başlar.');
      case _Asama.kuruluyor:
        if (_onayAcilmadi) {
          return const Text(
            'Yükleme ekranı açılamadı. "Tekrar dene"ye dokunun.',
            textAlign: TextAlign.center,
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              _uzunSurdu
                  ? 'Kurulum tamamlanmadı. "Tekrar dene" ile yükleme ekranı '
                      'yeniden açılır; orada "Güncelle"ye dokunun. İzin '
                      'sorulursa "Bu kaynaktan izin ver"i açıp geri dönün.'
                  : _onayBekliyor
                      ? 'Açılan ekranda "Güncelle"ye dokunun.'
                      : 'Kuruluyor... Uygulama birazdan kapanır. Yeni sürümü '
                          'açmak için gelen bildirime ya da uygulama '
                          'simgesine dokunun.',
              textAlign: TextAlign.center,
            ),
          ],
        );
      case _Asama.hata:
        return Text(_hata ?? 'Bir sorun oluştu',
            style: TextStyle(color: Theme.of(context).colorScheme.error));
    }
  }

  List<Widget> _dugmeler() {
    final erteleGorunur = !widget.zorunlu &&
        (_asama != _Asama.kuruluyor || _takildi);
    final ertele = erteleGorunur
        ? TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_asama == _Asama.indiriliyor
                ? 'Arka planda insin'
                : 'Ertele'),
          )
        : null;
    final List<Widget> ana = switch (_asama) {
      _Asama.soru => [
          FilledButton.icon(
            onPressed: _guncelle,
            icon: const Icon(Icons.system_update),
            label: Text(widget.zorunlu ? 'Güncelle' : 'Şimdi güncelle'),
          ),
        ],
      _Asama.indiriliyor => const [],
      _Asama.izin => [
          FilledButton(
            onPressed: apk.kurulumIzniIste,
            child: const Text('İzin ver'),
          ),
        ],
      _Asama.kuruluyor => _onayAcilmadi || _uzunSurdu
              ? [
                  FilledButton(
                      onPressed: _kur, child: const Text('Tekrar dene')),
                ]
              : const [],
      _Asama.hata => [
          FilledButton(onPressed: _kur, child: const Text('Tekrar dene')),
        ],
    };
    return [if (ertele != null) ertele, ...ana];
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      // Geri tuşu: normal sürümde "Ertele" sayılır; zorunluda kapanmaz.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop &&
            !widget.zorunlu &&
            (_asama != _Asama.kuruluyor || _takildi)) {
          Navigator.pop(context, true);
        }
      },
      child: AlertDialog(
        icon: Icon(
            widget.zorunlu ? Icons.warning_amber : Icons.system_update,
            size: 36),
        title: Text(widget.zorunlu ? 'Güncelleme gerekli' : 'Yeni sürüm var'),
        content: SizedBox(width: 420, child: _icerik(context)),
        actions: _dugmeler(),
      ),
    );
  }
}
