import 'dart:async';
import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'giris_kaydi_servisi.dart';
import 'guncelleme_servisi.dart';
import 'supabase_service.dart';

/// Kodun nereden okunduğu (okuma kaynağı göstergesi ve sayılar).
enum OkumaKaynagi {
  barkod('Barkod'),
  karekod('Karekod'),
  yazi('Yazı (S/N)');

  const OkumaKaynagi(this.ad);
  final String ad;
}

/// Bir günün okuma sayıları (telefon başına).
class GunlukSayac {
  int barkod = 0;
  int karekod = 0;
  int yazi = 0;
  int evet = 0; // yazıdan okunan "Doğru mu?" → Evet
  int hayir = 0; // → Hayır
  int kameraDurdu = 0; // 30 sn kod yok, kamera durdu
  int sureToplamMs = 0; // kamera açılışı / önceki okumadan kabule
  int sureAdet = 0;
  final Map<String, int> yokSayilan = {}; // sebep → adet
  final Map<String, int> yakinlik = {}; // "2x" → kabul edilen okuma

  int get okuma => barkod + karekod + yazi;
  int get yokToplam => yokSayilan.values.fold(0, (t, n) => t + n);

  bool get bos =>
      okuma == 0 &&
      evet == 0 &&
      hayir == 0 &&
      kameraDurdu == 0 &&
      yokSayilan.isEmpty;

  void ekle(GunlukSayac o) {
    barkod += o.barkod;
    karekod += o.karekod;
    yazi += o.yazi;
    evet += o.evet;
    hayir += o.hayir;
    kameraDurdu += o.kameraDurdu;
    sureToplamMs += o.sureToplamMs;
    sureAdet += o.sureAdet;
    o.yokSayilan.forEach((k, v) => yokSayilan[k] = (yokSayilan[k] ?? 0) + v);
    o.yakinlik.forEach((k, v) => yakinlik[k] = (yakinlik[k] ?? 0) + v);
  }

  Map<String, dynamic> toJson() => {
        'barkod': barkod,
        'karekod': karekod,
        'yazi': yazi,
        'evet': evet,
        'hayir': hayir,
        'kamera_durdu': kameraDurdu,
        'sure_toplam_ms': sureToplamMs,
        'sure_adet': sureAdet,
        'yok_sayilan': yokSayilan,
        'yakinlik': yakinlik,
      };

  static GunlukSayac fromJson(Map<String, dynamic> m) {
    int i(String k) => (m[k] as num?)?.toInt() ?? 0;
    Map<String, int> harita(String k) => {
          for (final e in ((m[k] as Map?) ?? const {}).entries)
            '${e.key}': (e.value as num?)?.toInt() ?? 0,
        };
    return GunlukSayac()
      ..barkod = i('barkod')
      ..karekod = i('karekod')
      ..yazi = i('yazi')
      ..evet = i('evet')
      ..hayir = i('hayir')
      ..kameraDurdu = i('kamera_durdu')
      ..sureToplamMs = i('sure_toplam_ms')
      ..sureAdet = i('sure_adet')
      ..yokSayilan.addAll(harita('yok_sayilan'))
      ..yakinlik.addAll(harita('yakinlik'));
  }
}

/// 1.31.0: okuma sayıları ("kapının ölçüsü"). Amaç: hangi telefon modelinde
/// okuma zayıf, hangi etiketler barkoddan okunamıyor.
///
/// - Sayılar gün boyu telefonda birikir (SharedPreferences; kişisel veri yok,
///   kullanıcıya bağlanmaz; telefon başına sabit bir kurulum kimliği).
/// - Anlık senkrona GİRMEZ: günde bir kez akşam 17:00-17:30 arası o günün
///   sayıları sunucuya (okuma_istatistikleri) gönderilir. Geçmiş günler
///   (o saatte gönderilemeyenler dahil) ilk fırsatta son haliyle gönderilir
///   ve sunucu "aldım" deyince telefondan silinir. Aynı gün tekrar
///   gönderilirse sunucudaki satırın üzerine yazılır (toplam, ekleme değil).
/// - Telefonlara geri çekilmez; Raporlar → "Okuma istatistikleri" sunucudan
///   okur.
class OkumaIstatistigi {
  static const _anahtar = 'okuma_istatistigi';
  static const _gonderilenAnahtari = 'okuma_istatistigi_gonderilen_gun';
  static const _kurulumAnahtari = 'kurulum_kimligi';
  static const tablo = 'okuma_istatistikleri';

  /// Bugünün sayıları değişince (Ayarlar'daki gösterge için).
  static final degisti = ValueNotifier<int>(0);

  // Henüz diske yazılmamış eklemeler (gün → sayaç).
  static final _bekleyen = <String, GunlukSayac>{};
  static Timer? _yazZamanlayici;
  static Future<void> _kuyruk = Future.value();
  static Timer? _gonderZamanlayici;

  static String gunAnahtari(DateTime t) => DateFormat('yyyy-MM-dd').format(t);

  /// Gönderim penceresi: 17:00 - 17:30 (yerel saat).
  static bool gonderimSaati(DateTime t) =>
      t.hour == 17 && t.minute < 30;

  /// Gönderilecek günler: bugünden önceki bütün günler; bugün ise yalnız
  /// 17:00-17:30 arasında ve bugün henüz gönderilmediyse.
  static List<String> gonderilecekGunler(
      Iterable<String> gunler, DateTime simdi, String? bugunGonderilen) {
    final bugun = gunAnahtari(simdi);
    return [
      for (final g in gunler)
        if (g.compareTo(bugun) < 0 ||
            (g == bugun && gonderimSaati(simdi) && bugunGonderilen != bugun))
          g,
    ]..sort();
  }

  // ---------------------------------------------------------- sayma

  static void _degistir(void Function(GunlukSayac s) f) {
    final gun = gunAnahtari(DateTime.now());
    f(_bekleyen.putIfAbsent(gun, GunlukSayac.new));
    degisti.value++;
    _yazZamanlayici ??= Timer(const Duration(seconds: 3), () {
      _yazZamanlayici = null;
      unawaited(_sirayla(_diskeYaz));
    });
  }

  /// Kod kabul edildi. [sure]: kamera açılışından ya da önceki okumadan bu
  /// yana (2 dakikadan uzunsa sayılmaz: telefon bırakılmış). [yakinlik]:
  /// 1, 2, 3 (x).
  static void kabul(OkumaKaynagi k, {Duration? sure, int? yakinlik}) {
    _degistir((s) {
      switch (k) {
        case OkumaKaynagi.barkod:
          s.barkod++;
        case OkumaKaynagi.karekod:
          s.karekod++;
        case OkumaKaynagi.yazi:
          s.yazi++;
      }
      if (sure != null && sure <= const Duration(minutes: 2)) {
        s.sureToplamMs += sure.inMilliseconds;
        s.sureAdet++;
      }
      if (yakinlik != null) {
        final a = '${yakinlik}x';
        s.yakinlik[a] = (s.yakinlik[a] ?? 0) + 1;
      }
    });
  }

  /// Kod yok sayıldı ([sebep]: "MAC adresi", "fabrika barkodu"…).
  static void yokSayildi(String sebep) =>
      _degistir((s) => s.yokSayilan[sebep] = (s.yokSayilan[sebep] ?? 0) + 1);

  /// Yazıdan okunan "Doğru mu?" cevabı.
  static void dogruMu(bool evet) =>
      _degistir((s) => evet ? s.evet++ : s.hayir++);

  static void kameraDurdu() => _degistir((s) => s.kameraDurdu++);

  // ---------------------------------------------------------- saklama

  static Future<T> _sirayla<T>(Future<T> Function() gorev) {
    final c = Completer<T>();
    _kuyruk = _kuyruk.then((_) async {
      try {
        c.complete(await gorev());
      } catch (e, st) {
        c.completeError(e, st);
      }
    });
    return c.future;
  }

  static Future<Map<String, GunlukSayac>> _oku(SharedPreferences p) async {
    try {
      await p.reload(); // arka plan görevi de yazmış olabilir
    } catch (_) {}
    final ham = p.getString(_anahtar);
    if (ham == null || ham.isEmpty) return {};
    try {
      final m = jsonDecode(ham) as Map<String, dynamic>;
      return {
        for (final e in m.entries)
          e.key: GunlukSayac.fromJson((e.value as Map).cast<String, dynamic>()),
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> _yaz(
      SharedPreferences p, Map<String, GunlukSayac> gunler) async {
    await p.setString(
        _anahtar,
        jsonEncode({
          for (final e in gunler.entries)
            if (!e.value.bos) e.key: e.value.toJson(),
        }));
  }

  /// Bekleyen eklemeleri diskteki sayılarla birleştirir.
  static Future<void> _diskeYaz() async {
    if (_bekleyen.isEmpty) return;
    final eklenecek = Map.of(_bekleyen);
    _bekleyen.clear();
    try {
      final p = await SharedPreferences.getInstance();
      final gunler = await _oku(p);
      eklenecek.forEach(
          (g, s) => gunler.putIfAbsent(g, GunlukSayac.new).ekle(s));
      await _yaz(p, gunler);
    } catch (e) {
      // Yazılamadıysa kaybolmasın: geri koy.
      eklenecek.forEach(
          (g, s) => _bekleyen.putIfAbsent(g, GunlukSayac.new).ekle(s));
      debugPrint('Okuma sayıları yazılamadı: $e');
    }
  }

  /// Bekleyen sayıları hemen diske yazar (uygulama arka plana giderken).
  static Future<void> kaydet() => _sirayla(_diskeYaz);

  /// Telefondaki (henüz gönderilmemiş / silinmemiş) bütün günler.
  static Future<Map<String, GunlukSayac>> hepsi() => _sirayla(() async {
        await _diskeYaz();
        return _oku(await SharedPreferences.getInstance());
      });

  /// Bugünün sayıları (Ayarlar).
  static Future<GunlukSayac> bugun() async =>
      (await hepsi())[gunAnahtari(DateTime.now())] ?? GunlukSayac();

  // ---------------------------------------------------------- gönderme

  /// Uygulama açıkken: hemen bir kez, sonra 5 dakikada bir gönderim
  /// zamanı gelmiş gün var mı bakılır.
  static void baslat() {
    unawaited(gonder());
    _gonderZamanlayici ??=
        Timer.periodic(const Duration(minutes: 5), (_) => unawaited(gonder()));
  }

  /// Zamanı gelmiş günleri sunucuya gönderir; geçmiş günleri gönderince
  /// telefondan siler. İnternet / oturum yoksa ya da sunucuda tablo yoksa
  /// (SQL çalıştırılmamış) hiçbir şey silinmez, sonra yeniden denenir.
  /// [zorla]: bugünü de saatini beklemeden gönder (Ayarlar → "Şimdi
  /// gönder").
  static Future<void> gonder({bool zorla = false}) => _sirayla(() async {
        if (!SupabaseService.girisYapildi) return;
        await _diskeYaz();
        final p = await SharedPreferences.getInstance();
        final gunler = await _oku(p);
        final simdi = DateTime.now();
        final bugunAnahtari = gunAnahtari(simdi);
        final secilen = gonderilecekGunler(
            gunler.keys, simdi, p.getString(_gonderilenAnahtari));
        if (zorla &&
            gunler.containsKey(bugunAnahtari) &&
            !secilen.contains(bugunAnahtari)) {
          secilen.add(bugunAnahtari);
        }
        if (secilen.isEmpty) return;

        final kurulum = await _kurulumKimligi(p);
        final cihaz = await _cihazBilgisi();
        final zaman = DateTime.now().toUtc().toIso8601String();
        final satirlar = [
          for (final g in secilen)
            {
              'id': '${kurulum}_$g',
              'kurulum_id': kurulum,
              'gun': g,
              ...cihaz,
              ...gunler[g]!.toJson(),
              'guncellendi': zaman,
            },
        ];
        try {
          await SupabaseService.client
              .from(tablo)
              .upsert(satirlar, onConflict: 'id')
              .timeout(const Duration(seconds: 30));
        } catch (e) {
          debugPrint('Okuma sayıları gönderilemedi: $e');
          if (zorla) rethrow;
          return;
        }
        // Sunucu aldı: geçmiş günler silinir; bugün işaretlenir (akşam
        // 17:30'dan sonraki okumalar yarın son haliyle yeniden gönderilir).
        final guncel = await _oku(p);
        for (final g in secilen) {
          if (g != bugunAnahtari) guncel.remove(g);
        }
        await _yaz(p, guncel);
        if (secilen.contains(bugunAnahtari)) {
          await p.setString(_gonderilenAnahtari, bugunAnahtari);
        }
        degisti.value++;
      });

  /// Rapor için sunucudaki satırlar (internet gerekir).
  static Future<List<Map<String, dynamic>>> sunucudanOku(
      {DateTime? baslangic, DateTime? bitis}) async {
    var sorgu = SupabaseService.client.from(tablo).select();
    if (baslangic != null) sorgu = sorgu.gte('gun', gunAnahtari(baslangic));
    if (bitis != null) sorgu = sorgu.lte('gun', gunAnahtari(bitis));
    final r = await sorgu.order('gun', ascending: false).limit(10000);
    return List<Map<String, dynamic>>.from(r);
  }

  static Future<String> _kurulumKimligi(SharedPreferences p) async {
    var k = p.getString(_kurulumAnahtari);
    if (k == null || k.isEmpty) {
      k = const Uuid().v4();
      await p.setString(_kurulumAnahtari, k);
    }
    return k;
  }

  static Map<String, String?>? _cihazOnbellek;

  /// Telefon modeli ve işletim sistemi (kişisel veri değil).
  static Future<Map<String, String?>> _cihazBilgisi() async {
    final o = _cihazOnbellek;
    if (o != null) return o;
    String? marka, model, sistem;
    try {
      final d = DeviceInfoPlugin();
      if (kIsWeb) {
        final w = await d.webBrowserInfo;
        model = w.platform;
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        final a = await d.androidInfo;
        marka = a.manufacturer;
        model = a.model;
        sistem = 'Android ${a.version.release}';
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final i = await d.iosInfo;
        marka = 'Apple';
        model = i.utsname.machine;
        sistem = 'iOS ${i.systemVersion}';
      }
    } catch (_) {}
    return _cihazOnbellek = {
      'platform': GirisKaydiServisi.platform,
      'marka': marka,
      'model': model,
      'isletim_sistemi': sistem,
      'uygulama_surumu': GuncellemeServisi.mevcutSurum.isEmpty
          ? null
          : GuncellemeServisi.mevcutSurum,
    };
  }

  @visibleForTesting
  static void testIcinSifirla() {
    _bekleyen.clear();
    _yazZamanlayici?.cancel();
    _yazZamanlayici = null;
    _kuyruk = Future.value();
  }
}
