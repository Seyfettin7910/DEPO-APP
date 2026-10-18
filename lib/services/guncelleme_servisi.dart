import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'guncelleme/apk_kurucu.dart' as apk;

/// Uygulama güncellemeleri.
///
/// - **Telefon (Android):** yeni sürüm Wi-Fi'deyken arka planda indirilir,
///   sonra "Şimdi kur" ile kurulur (veriler korunur). Mobil veride indirmeden
///   önce sorulur.
/// - **Web:** açılışta yeni sürüm varsa sayfa kendiliğinden yenilenir.
/// - **Zorunlu güncelleme:** sunucudaki en düşük sürümün (min_surum.txt)
///   altındaki uygulamalar güncellenmeden kullanılamaz.
///
/// Sürüm numarası derlemede gömülür (--dart-define=APP_SURUM); gömülmemişse
/// (ör. FlutLab derlemesi) kontrol yapılmaz.
class GuncellemeServisi {
  static const mevcutSurum = String.fromEnvironment('APP_SURUM');
  static const _repo = 'Seyfettin7910/DEPO-APP';
  static const apkLinki =
      'https://github.com/$_repo/releases/latest/download/depo-takip.apk';
  static const _surumDosyasi =
      'https://seyfettin7910.github.io/DEPO-APP/version.json';

  static DateTime? _sonKontrol;
  static bool _calisiyor = false;
  static final _ertelenen = <String>{};
  static String? _hazirSurum; // indirilip kurulmayı bekleyen sürüm
  static String? _hazirYol;

  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

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
    final tag = (yayin?['tag_name'] as String?)?.replaceFirst(RegExp(r'^v'), '');
    return (tag ?? dosya?['surum'] as String?, dosya?['min'] as String?);
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
  // Ana kontrol
  // ------------------------------------------------------------------

  /// Açılışta ([acilis] = true) ve uygulamaya dönüşte çağrılır.
  /// Dönüşlerde sunucuya en fazla 6 saatte bir sorulur.
  static Future<void> kontrolEt(BuildContext context,
      {bool acilis = false}) async {
    if (mevcutSurum.isEmpty || _calisiyor) return;

    // İndirilmiş ama kurulmamış güncelleme varsa (ör. kurulum izni
    // ayarından dönüldü) tekrar sor.
    if (_android && _hazirYol != null && !_ertelenen.contains(_hazirSurum)) {
      _calisiyor = true;
      try {
        await _kurmayiSor(context, _hazirSurum!, _hazirYol!);
      } finally {
        _calisiyor = false;
      }
      return;
    }

    final simdi = DateTime.now();
    if (!acilis &&
        _sonKontrol != null &&
        simdi.difference(_sonKontrol!) < const Duration(hours: 6)) {
      return;
    }
    _sonKontrol = simdi;
    _calisiyor = true;
    try {
      final (enSon, enDusuk) = await _surumler();
      final zorunlu = enDusuk != null && dahaYeni(enDusuk, mevcutSurum);
      final yeni = enSon != null && dahaYeni(enSon, mevcutSurum);
      if ((!yeni && !zorunlu) || !context.mounted) return;
      final hedef = (yeni ? enSon : enDusuk)!;

      if (kIsWeb) {
        await _webGuncelle(context, hedef, otomatik: acilis || zorunlu);
      } else if (zorunlu) {
        await _zorunlu(context, hedef);
      } else if (_android) {
        if (!_ertelenen.contains(hedef)) await _androidGuncelle(context, hedef);
      } else {
        await _linkiAc(context, hedef);
      }
    } finally {
      _calisiyor = false;
    }
  }

  // ------------------------------------------------------------------
  // Web
  // ------------------------------------------------------------------

  static Future<void> _webGuncelle(BuildContext context, String hedef,
      {required bool otomatik}) async {
    const anahtar = 'oto_yenileme_denenen';
    String? denenen;
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      denenen = prefs.getString(anahtar);
    } catch (_) {}

    // Aynı sürüm için yalnızca bir kez kendiliğinden yenile (tarayıcı
    // önbelleği yüzünden döngüye girmesin).
    if (otomatik && denenen != hedef) {
      try {
        await prefs?.setString(anahtar, hedef);
      } catch (_) {}
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Yeni sürüm ($hedef) yükleniyor...'),
          duration: const Duration(seconds: 3),
        ));
      }
      await Future.delayed(const Duration(milliseconds: 1500));
      await _sayfayiYenile(hedef);
      return;
    }

    if (_ertelenen.contains(hedef) || !context.mounted) return;
    final yenile = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.system_update),
        title: const Text('Yeni sürüm var'),
        content: Text('Depo Takip $hedef yayınlandı (şu an: $mevcutSurum).\n'
            'Sayfa güncellenmezse klavyede Ctrl + F5 yapın.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Sonra')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.refresh),
            label: const Text('Yenile'),
          ),
        ],
      ),
    );
    if (yenile == true) {
      await _sayfayiYenile(hedef);
    } else {
      _ertelenen.add(hedef);
    }
  }

  static Future<void> _sayfayiYenile(String hedef) => launchUrl(
        Uri.base.removeFragment().replace(queryParameters: {'v': hedef}),
        webOnlyWindowName: '_self',
      );

  // ------------------------------------------------------------------
  // Android
  // ------------------------------------------------------------------

  static Future<void> _androidGuncelle(BuildContext context, String hedef) async {
    var yol = await apk.indirilmisApk(hedef);
    if (yol == null) {
      final baglanti = await Connectivity().checkConnectivity();
      final wifi = baglanti.contains(ConnectivityResult.wifi) ||
          baglanti.contains(ConnectivityResult.ethernet);
      if (wifi) {
        // Wi-Fi'de sessizce arka planda indir
        try {
          yol = await apk.apkIndir(apkLinki, hedef, (_) {});
        } catch (e) {
          debugPrint('Güncelleme indirilemedi: $e');
          return;
        }
      } else {
        if (!context.mounted) return;
        final indir = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.system_update),
            title: const Text('Yeni sürüm var'),
            content: Text('Depo Takip $hedef hazır (telefondaki: $mevcutSurum).\n\n'
                'Wi-Fi\'ye bağlanınca kendiliğinden indirilir. Şimdi mobil '
                'veriyle indirmek ister misiniz?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Wi-Fi\'yi bekle')),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.download),
                label: const Text('Şimdi indir'),
              ),
            ],
          ),
        );
        if (indir != true || !context.mounted) {
          _sonKontrol = null; // Wi-Fi gelince tekrar denensin
          return;
        }
        yol = await _ilerlemeyleIndir(context, hedef);
        if (yol == null) return;
      }
    }
    _hazirSurum = hedef;
    _hazirYol = yol;
    if (context.mounted) await _kurmayiSor(context, hedef, yol);
  }

  static Future<void> _kurmayiSor(
      BuildContext context, String hedef, String yol) async {
    if (!context.mounted) return;
    final kur = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.system_update),
        title: const Text('Güncelleme hazır'),
        content: Text('Depo Takip $hedef indirildi (telefondaki: $mevcutSurum).\n\n'
            'Kurulum birkaç saniye sürer; verileriniz silinmez. '
            'Gönderilmemiş işlemler varsa önce internet bağlantısını bekleyin.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Sonra')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.install_mobile),
            label: const Text('Şimdi kur'),
          ),
        ],
      ),
    );
    if (kur != true) {
      _ertelenen.add(hedef); // bu oturumda bir daha sorma
      return;
    }
    if (context.mounted) await _kur(context, yol);
  }

  /// Kurulumu başlatır. İzin yoksa önce izin ekranına yönlendirir.
  /// true: kurulum başlatıldı.
  static Future<bool> _kur(BuildContext context, String yol) async {
    try {
      if (!await apk.kurulumIzniVar()) {
        if (!context.mounted) return false;
        final ac = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Kurulum izni gerekli'),
            content: const Text(
                'Uygulamanın kendini güncelleyebilmesi için bir kez izin vermeniz '
                'gerekiyor.\n\nAçılacak ekranda "Bu kaynaktan izin ver" '
                'seçeneğini açıp geri dönün; güncelleme tekrar sorulacak.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('İptal')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Ayarları aç')),
            ],
          ),
        );
        if (ac == true) await apk.kurulumIzniIste();
        return false;
      }
      await apk.apkKur(yol);
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Kurulum başlatılamadı: $e'),
          backgroundColor: Colors.red.shade700,
        ));
      }
      return false;
    }
  }

  static Future<String?> _ilerlemeyleIndir(
      BuildContext context, String hedef) async {
    final oran = ValueNotifier<double?>(null);
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text('Depo Takip $hedef indiriliyor'),
          content: ValueListenableBuilder<double?>(
            valueListenable: oran,
            builder: (_, v, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: v),
                const SizedBox(height: 8),
                Text(v == null ? 'Başlıyor...' : '%${(v * 100).round()}'),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      return await apk.apkIndir(apkLinki, hedef, (v) => oran.value = v);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('İndirilemedi: $e'),
        backgroundColor: Colors.red.shade700,
      ));
      return null;
    } finally {
      navigator.pop();
    }
  }

  // ------------------------------------------------------------------
  // Zorunlu güncelleme
  // ------------------------------------------------------------------

  static Future<void> _zorunlu(BuildContext context, String hedef) async {
    while (context.mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            icon: const Icon(Icons.warning_amber, size: 36),
            title: const Text('Güncelleme gerekli'),
            content: Text(
                'Bu sürüm ($mevcutSurum) artık kullanılamıyor. Verilerin doğru '
                'kaydedilmesi için Depo Takip $hedef sürümüne güncelleyin.'),
            actions: [
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.system_update),
                label: const Text('Güncelle'),
              ),
            ],
          ),
        ),
      );
      if (!context.mounted) return;
      if (_android) {
        final yol = await apk.indirilmisApk(hedef) ??
            await _ilerlemeyleIndir(context, hedef);
        if (yol != null && context.mounted) {
          _hazirSurum = hedef;
          _hazirYol = yol;
          if (await _kur(context, yol)) return;
        }
      } else {
        await _linkiAc(context, hedef);
        return;
      }
    }
  }

  static Future<void> _linkiAc(BuildContext context, String hedef) async {
    if (_ertelenen.contains(hedef)) return;
    _ertelenen.add(hedef);
    await launchUrl(Uri.parse(apkLinki), mode: LaunchMode.externalApplication);
  }
}
