import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Yarım kalan iş (taslak): sayım, toplu transfer, depoya giriş, sahada
/// kullanım ve arıza / servis pencereleri her değişiklikte telefona yazılır.
/// Uygulama kapanır, çöker ya da güncellenirse açılışta "Devam et / Sil"
/// diye sorulur. Taslaklar 7 gün saklanır.
class Taslak {
  Taslak({
    required this.tur,
    this.cihazId,
    required this.baslik,
    required this.ozet,
    required this.veri,
    DateTime? zaman,
  }) : zaman = zaman ?? DateTime.now();

  /// sayim | toplu_transfer | toplu_kullanim | toplu_iade | giris |
  /// saha | ariza | servis_gonder | servis_sonuc | hurda | geri_al
  final String tur;

  /// Pencere taslaklarında (saha, arıza…) ilgili cihaz.
  final String? cihazId;
  final String baslik;
  final String ozet;
  final DateTime zaman;
  final Map<String, dynamic> veri;

  String get anahtar => cihazId == null ? tur : '$tur:$cihazId';

  /// Cihaz kartında açılan pencere taslağı mı (ekran taslağı değil)?
  bool get pencere => cihazId != null;

  Map<String, dynamic> toJson() => {
        'tur': tur,
        'cihazId': cihazId,
        'baslik': baslik,
        'ozet': ozet,
        'zaman': zaman.millisecondsSinceEpoch,
        'veri': veri,
      };

  static Taslak? fromJson(String metin) {
    try {
      final m = jsonDecode(metin) as Map<String, dynamic>;
      return Taslak(
        tur: m['tur'] as String,
        cihazId: m['cihazId'] as String?,
        baslik: m['baslik'] as String? ?? '',
        ozet: m['ozet'] as String? ?? '',
        zaman: DateTime.fromMillisecondsSinceEpoch(
            (m['zaman'] as num?)?.toInt() ?? 0),
        veri: (m['veri'] as Map?)?.cast<String, dynamic>() ?? {},
      );
    } catch (_) {
      return null;
    }
  }

  static final _saat = DateFormat('dd.MM HH:mm');
  String get zamanMetni => _saat.format(zaman);
}

class TaslakServisi {
  TaslakServisi._();

  static const _onEk = 'taslak|';
  static const saklamaSuresi = Duration(days: 7);

  /// Bir taslak yazılınca / silinince haber verir (cihaz kartındaki
  /// "yarım kalan işlem" kartı ve güncelleme penceresi dinler).
  static final degisti = ValueNotifier<int>(0);

  static bool _bildirimBekliyor = false;

  /// Dinleyenlere bir sonraki fırsatta haber verir (pencere çizilirken
  /// çağrılabildiği için hemen değil).
  static void _bildir() {
    if (_bildirimBekliyor) return;
    _bildirimBekliyor = true;
    scheduleMicrotask(() {
      _bildirimBekliyor = false;
      degisti.value++;
    });
  }

  static final _bekleyen = <String, Taslak?>{};
  static Timer? _zamanlayici;

  /// Her anahtarın değişiklik sayacı: yazma sürerken silinen taslak geri
  /// yazılmasın.
  static final _surum = <String, int>{};
  static int _artir(String anahtar) =>
      _surum[anahtar] = (_surum[anahtar] ?? 0) + 1;

  /// Şu an açık olan iş ekranları / pencereleri.
  static final _acik = <String>{};

  /// Açık ve içi dolu (taslağı olan) işler: güncelleme penceresi bunlar
  /// bitene kadar bekler.
  static final _dolu = <String>{};

  /// Açık olan pencereler (sahada kullanım, arıza…): açık oldukça iş sürüyor
  /// sayılır.
  static final _pencereler = <String>{};

  static bool get isVar =>
      _pencereler.isNotEmpty || _acik.any(_dolu.contains);

  static Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  static void acildi(String anahtar) => _acik.add(anahtar);

  static void kapandi(String anahtar) {
    _acik.remove(anahtar);
    _dolu.remove(anahtar);
    _pencereler.remove(anahtar);
    _bildir();
  }

  static void pencereAcildi(String anahtar) {
    _acik.add(anahtar);
    _pencereler.add(anahtar);
    _bildir();
  }

  /// Taslağı (kısa gecikmeyle, toplu) yazar; [taslak] null ise siler.
  static void yaz(String anahtar, Taslak? taslak) {
    _artir(anahtar);
    _bekleyen[anahtar] = taslak;
    final oncedenDolu = _dolu.contains(anahtar);
    if (taslak == null) {
      _dolu.remove(anahtar);
    } else {
      _dolu.add(anahtar);
    }
    if (oncedenDolu != (taslak != null)) _bildir();
    _zamanlayici?.cancel();
    _zamanlayici =
        Timer(const Duration(milliseconds: 400), () => bekleyenleriYaz());
  }

  /// Bekleyen yazmaları hemen diske yazar (ör. güncelleme kurulmadan önce).
  static Future<void> bekleyenleriYaz() async {
    _zamanlayici?.cancel();
    _zamanlayici = null;
    if (_bekleyen.isEmpty) return;
    final liste = Map.of(_bekleyen);
    final surumler = {for (final k in liste.keys) k: _surum[k]};
    _bekleyen.clear();
    final p = await _prefs();
    if (p == null) return;
    for (final e in liste.entries) {
      // Bu arada yeniden yazıldı ya da silindiyse eski hali yazılmaz.
      if (_surum[e.key] != surumler[e.key]) continue;
      try {
        if (e.value == null) {
          await p.remove('$_onEk${e.key}');
        } else {
          await p.setString('$_onEk${e.key}', jsonEncode(e.value!.toJson()));
        }
      } catch (_) {}
    }
  }

  static Future<void> sil(String anahtar) async {
    _artir(anahtar);
    _bekleyen.remove(anahtar);
    _dolu.remove(anahtar);
    try {
      await (await _prefs())?.remove('$_onEk$anahtar');
    } catch (_) {}
    _bildir();
  }

  static Future<Taslak?> oku(String anahtar) async {
    if (_bekleyen.containsKey(anahtar)) return _bekleyen[anahtar];
    final metin = (await _prefs())?.getString('$_onEk$anahtar');
    if (metin == null) return null;
    final t = Taslak.fromJson(metin);
    if (t == null || DateTime.now().difference(t.zaman) > saklamaSuresi) {
      await sil(anahtar);
      return null;
    }
    return t;
  }

  /// Saklanan bütün taslaklar (yeniden eskiye). 7 günden eskiler silinir.
  /// Şu an açık olan işler listeye girmez.
  static Future<List<Taslak>> hepsi() async {
    await bekleyenleriYaz();
    final p = await _prefs();
    if (p == null) return const [];
    final sonuc = <Taslak>[];
    for (final k in p.getKeys().where((k) => k.startsWith(_onEk)).toList()) {
      final anahtar = k.substring(_onEk.length);
      if (_acik.contains(anahtar)) continue;
      final t = Taslak.fromJson(p.getString(k) ?? '');
      if (t == null || DateTime.now().difference(t.zaman) > saklamaSuresi) {
        await p.remove(k);
        continue;
      }
      sonuc.add(t);
    }
    sonuc.sort((a, b) => b.zaman.compareTo(a.zaman));
    return sonuc;
  }

  /// Bir cihazın kartında açılan pencerelerin taslakları.
  static Future<List<Taslak>> cihazinTaslaklari(String cihazId) async =>
      [for (final t in await hepsi()) if (t.cihazId == cihazId) t];
}

/// İş ekranlarına (sayım, toplu transfer, depoya giriş) yarım iş koruması:
/// her setState'ten sonra taslak yazılır; açılışta taslak varsa geri
/// yüklenir; geri tuşunda "taslak olarak sakla / sil" sorulur.
mixin YarimIsKorumasi<T extends StatefulWidget> on State<T> {
  /// Taslağın anahtarı (ör. 'sayim', 'toplu_transfer').
  String get taslakTuru;

  /// Ekran taslaktan devam etmek için mi açıldı (soru sorulmadan yüklenir)?
  bool get taslaktanAcildi;

  /// Ekranın şu anki hali; içi boşsa null (taslak silinir).
  Taslak? taslakOlustur();

  /// Kaydedilmiş taslağı ekrana yükler.
  Future<void> taslagiYukle(Taslak t);

  bool _taslakHazir = false;
  bool _sakla = false;

  @protected
  void taslakKorumasiniBaslat({List<Listenable> dinlenecekler = const []}) {
    TaslakServisi.acildi(taslakTuru);
    for (final l in dinlenecekler) {
      l.addListener(_taslakDegisti);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _taslakKontrol());
  }

  Future<void> _taslakKontrol() async {
    final t = await TaslakServisi.oku(taslakTuru);
    if (!mounted) return;
    if (t != null) {
      var devam = taslaktanAcildi;
      if (!devam) {
        devam = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                icon: const Icon(Icons.restore_page_outlined),
                title: const Text('Yarım kalan iş var'),
                content: Text('${t.baslik}\n${t.ozet} · ${t.zamanMetni}\n\n'
                    'Kaldığınız yerden devam edilsin mi?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Sil, baştan başla')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Devam et')),
                ],
              ),
            ) ??
            false;
      }
      if (!mounted) return;
      if (devam) {
        await taslagiYukle(t);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Yarım kalan iş geri yüklendi (${t.ozet})')));
        }
      } else {
        await TaslakServisi.sil(taslakTuru);
      }
    }
    _taslakHazir = true;
    _taslakDegisti();
  }

  void _taslakDegisti() {
    if (!_taslakHazir || !mounted) return;
    TaslakServisi.yaz(taslakTuru, taslakOlustur());
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _taslakDegisti();
  }

  /// İş başarıyla kaydedildi: taslak silinir.
  @protected
  Future<void> taslakTamamlandi() async {
    _taslakHazir = false;
    await TaslakServisi.sil(taslakTuru);
  }

  /// Geri tuşu: içi doluysa sor. true dönerse ekran kapanabilir.
  Future<bool> _cikisOnayi() async {
    final t = _taslakHazir ? taslakOlustur() : null;
    if (t == null) return true;
    final secim = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.save_outlined),
        title: const Text('Yarım kalan iş'),
        content: Text('${t.baslik}\n${t.ozet}\n\n'
            'Çıkarsanız bu liste kaybolur. Taslak olarak saklarsanız sonra '
            'kaldığınız yerden devam edebilirsiniz (7 gün).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'sil'),
              child: const Text('Sil ve çık')),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Kal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'sakla'),
              child: const Text('Taslak olarak sakla')),
        ],
      ),
    );
    if (secim == 'sakla') {
      _sakla = true;
      TaslakServisi.yaz(taslakTuru, t);
      await TaslakServisi.bekleyenleriYaz();
      return true;
    }
    if (secim == 'sil') {
      await taslakTamamlandi();
      return true;
    }
    return false;
  }

  /// Ekranın Scaffold'unu sarar: geri tuşunda yarım iş sorulur.
  @protected
  Widget yarimIsKapsayici({required Widget child}) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await _cikisOnayi() && mounted) Navigator.of(context).pop();
        },
        child: child,
      );

  @protected
  void taslakKorumasiniBitir({List<Listenable> dinlenecekler = const []}) {
    for (final l in dinlenecekler) {
      l.removeListener(_taslakDegisti);
    }
    // Ekran normal yolla kapandı: "sakla" seçilmediyse taslak silinir.
    // (Uygulama kapanır / çöker / güncellenirse buraya gelinmez; taslak kalır.)
    if (!_sakla) {
      unawaited(TaslakServisi.sil(taslakTuru));
    } else {
      unawaited(TaslakServisi.bekleyenleriYaz());
    }
    TaslakServisi.kapandi(taslakTuru);
  }
}

/// Cihaz kartındaki pencerelerin (sahada kullanım, arıza, servis…) taslağı.
/// Pencere açılırken [ac] ile alınır; pencere kapanınca [kapat] çağrılır.
class PencereTaslagi {
  PencereTaslagi._(this.tur, this.cihazId, this.baslik, this.onceki);

  final String tur;
  final String cihazId;
  final String baslik;

  /// Önceden kalmış taslak verisi (yoksa null).
  final Map<String, dynamic>? onceki;

  String get anahtar => '$tur:$cihazId';
  bool get geriYuklendi => onceki != null;

  static Future<PencereTaslagi> ac(String tur, String cihazId,
      {required String baslik}) async {
    final t = await TaslakServisi.oku('$tur:$cihazId');
    final p = PencereTaslagi._(tur, cihazId, baslik, t?.veri);
    TaslakServisi.pencereAcildi(p.anahtar);
    return p;
  }

  T? deger<T>(String ad) {
    final v = onceki?[ad];
    return v is T ? v : null;
  }

  DateTime? tarih(String ad) {
    final v = onceki?[ad];
    return v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
  }

  /// [bos]: kullanıcı henüz bir şey girmediyse taslak saklanmaz.
  void yaz(Map<String, dynamic> veri, {String ozet = '', bool bos = false}) {
    TaslakServisi.yaz(
      anahtar,
      bos ? null : Taslak(
          tur: tur,
          cihazId: cihazId,
          baslik: baslik,
          ozet: ozet.isEmpty ? 'Pencere açıktı' : ozet,
          veri: veri),
    );
  }

  /// Pencere kapandı (kaydedildi ya da vazgeçildi): taslak silinir.
  Future<void> kapat() async {
    await TaslakServisi.sil(anahtar);
    TaslakServisi.kapandi(anahtar);
  }

  /// Pencere hiç açılamadı: taslağa dokunmadan bırakır.
  void birak() => TaslakServisi.kapandi(anahtar);
}

/// Taslak geri yüklenince pencerenin üstünde görünen küçük not.
class GeriYuklendiNotu extends StatelessWidget {
  const GeriYuklendiNotu({super.key});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tema.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.restore_page_outlined, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Yarım kalan bilgiler geri yüklendi',
                style: tema.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
