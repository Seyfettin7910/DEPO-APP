import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/app_database.dart';
import '../../database/models.dart';
import '../../providers/app_providers.dart';
import '../../services/etiket/etiket_kodu.dart';
import '../../services/okut_listesi.dart';
import '../../services/ses_servisi.dart';
import '../malzeme/malzeme_islem_screen.dart';
import '../../widgets/silme_islemleri.dart';
import '../../widgets/kod_yardimci.dart';
import '../cihaz/cihaz_ara_screen.dart';
import '../cihaz/cihaz_detay_screen.dart';
import '../cihaz/montaj_screen.dart';
import '../cihaz/toplu_giris_screen.dart';
import '../cihaz/toplu_transfer_screen.dart';
import '../../widgets/hedefli_tarayici.dart';
import '../../widgets/kritik_stok_seridi.dart';
import '../../widgets/renkler.dart';
import '../../widgets/sync_durum_dugmesi.dart';
import '../../widgets/koli_karekodu.dart';
import '../../widgets/malzeme_kalemleri.dart';

/// Okut: seri numarası okutulunca cihazın kartı açılır.
///
/// Arka arkaya okutma (kuralları [OkutListesi]'nde):
/// - 2 kayıtsız seri no arka arkaya okutulunca liste kendiliğinden başlar;
///   bitince "Depoya ekle (N)" giriş ekranını hepsiyle açar.
/// - Hızlı işleme (Depoya giriş · Transfer · Araca Yükle · Montaj) dokununca
///   arka arkaya okutulur; düğme ilgili ekranı listeyle doğrudan açar.
/// - Koli karekodu listeye pencere açmadan eklenir; en fazla 100 kayıt
///   (kameranın üstünde "98/100").
class BarkodTaramaScreen extends ConsumerStatefulWidget {
  const BarkodTaramaScreen({super.key});

  @override
  ConsumerState<BarkodTaramaScreen> createState() => _BarkodTaramaScreenState();
}

/// Hızlı işlemlerin ekrandaki adı, rengi ve düğme yazısı.
extension OkutIslemiGorunum on OkutIslemi {
  String get ad => switch (this) {
        OkutIslemi.giris => 'Depoya giriş',
        OkutIslemi.transfer => 'Transfer',
        OkutIslemi.yukle => 'Araca Yükle',
        OkutIslemi.montaj => 'Montaj / Kullanıldı',
      };

  IconData get ikon => switch (this) {
        OkutIslemi.giris => Icons.add_box_outlined,
        OkutIslemi.transfer => Icons.swap_horiz,
        OkutIslemi.yukle => Icons.local_shipping_outlined,
        OkutIslemi.montaj => Icons.place_outlined,
      };

  Color get renk => switch (this) {
        OkutIslemi.giris => Renkler.okut,
        OkutIslemi.transfer => Renkler.depo,
        OkutIslemi.yukle => Renkler.urun,
        OkutIslemi.montaj => Renkler.montaj,
      };

  Color get zemin => switch (this) {
        OkutIslemi.giris => Renkler.okutZemin,
        OkutIslemi.transfer => Renkler.depoZemin,
        OkutIslemi.yukle => Renkler.urunZemin,
        OkutIslemi.montaj => Renkler.montajZemin,
      };

  String dugme(int n) => switch (this) {
        OkutIslemi.giris => 'Depoya ekle ($n)',
        OkutIslemi.transfer => 'Transfer et ($n)',
        OkutIslemi.yukle => 'Araca yükle ($n)',
        OkutIslemi.montaj => 'Montaj ($n)',
      };
}

class _BarkodTaramaScreenState extends ConsumerState<BarkodTaramaScreen> {
  static const _anahtar = 'okut_listesi';

  // Arka plana gidip dönüşte kamerayı HedefliTarayici yönetir.
  final _controller = tarayiciOlustur();
  final _liste = OkutListesi();

  /// Listedeki kayıtlı cihazların bilgisi (ekranda ürün adı / yer için).
  final _bilgiler = <String, CihazBilgi>{};
  final _yazCtrl = TextEditingController();

  bool _mesgul = false;
  bool _coklu = false;
  String? _sonKod;
  DateTime _sonZaman = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    unawaited(_yukle());
  }

  @override
  void dispose() {
    _controller.dispose();
    _yazCtrl.dispose();
    super.dispose();
  }

  Future<void> _durdur() async {
    try {
      await _controller.stop();
    } catch (_) {}
  }

  Future<void> _baslat() async {
    try {
      await _controller.start();
    } catch (_) {}
  }

  // --------------------------------------------- liste saklama (kaybolmasın)

  Future<void> _yukle() async {
    try {
      final p = await SharedPreferences.getInstance();
      final ham = p.getString(_anahtar);
      if (ham == null) return;
      _liste.fromJson(Map<String, Object?>.from(jsonDecode(ham) as Map));
      if (!mounted) return;
      setState(() {});
      final db = ref.read(appDatabaseProvider);
      for (final s in List.of(_liste.seriler)) {
        final b = await db.seriNoIleCihazBilgi(s);
        if (b != null) _bilgiler[s] = b;
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _sakla() {
    unawaited(SharedPreferences.getInstance().then((p) => _liste.aktif
        ? p.setString(_anahtar, jsonEncode(_liste.toJson()))
        : p.remove(_anahtar)).catchError((_) => false));
  }

  void _degisti() {
    if (mounted) setState(() {});
    _sakla();
  }

  // ----------------------------------------------------------------- ekranlar

  /// Başka bir sayfa açarken arkadaki kamera durur (yoksa açılan sayfada
  /// okutulan kodları bu ekran da yakalar); geri dönünce yeniden başlar.
  Future<T?> _ac<T>(Widget ekran) async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    await _durdur();
    if (!mounted) return null;
    final sonuc =
        await Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => ekran));
    if (!mounted) return sonuc;
    _sonZaman = DateTime.now(); // dönüşte aynı kodu hemen tekrar işlemesin
    // Açılan sayfanın kamerası tamamen kapansın, sonra bu ekranınki açılsın.
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) await _baslat();
    return sonuc;
  }

  /// Listeyi ilgili işlem ekranına götürür; orada kaydedilirse liste boşalır.
  Future<void> _isle() async {
    final i = _liste.islem;
    if (i == null || _liste.bos) return;
    final seriler = List.of(_liste.seriler);
    final malzemeler = Map.of(_liste.malzemeler);
    final Widget ekran = switch (i) {
      OkutIslemi.giris => TopluGirisScreen(
          onceSeriNolari: seriler, onceMalzemeler: malzemeler),
      OkutIslemi.transfer => TopluTransferScreen(
          onceSeriNolari: seriler, onceMalzemeler: malzemeler),
      OkutIslemi.yukle => TopluTransferScreen(
          tip: HareketTipi.kullanim,
          onceSeriNolari: seriler,
          onceMalzemeler: malzemeler),
      OkutIslemi.montaj => MontajScreen(
          onceSeriNolari: seriler, onceMalzemeler: malzemeler),
    };
    final kaydedildi = await _ac<bool>(ekran);
    if (kaydedildi == true && mounted) {
      _liste.temizle();
      _bilgiler.clear();
      _degisti();
    }
  }

  void _islemSec(OkutIslemi i) {
    _liste.islemSec(i);
    _bilgiler.removeWhere((s, _) => !_liste.seriler.contains(s));
    _degisti();
  }

  Future<void> _temizle() async {
    if (_liste.seriler.length > 1) {
      final onay = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Liste temizlensin mi?'),
          content: Text('${_liste.seriler.length} okutma silinecek.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Temizle')),
          ],
        ),
      );
      if (onay != true) return;
    }
    _liste.temizle();
    _bilgiler.clear();
    _degisti();
  }

  // ------------------------------------------------------------------ okutma

  void _bilgi(String metin, {Color? renk, int sn = 2, SnackBarAction? aksiyon}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(metin),
        backgroundColor: renk,
        duration: Duration(seconds: sn),
        action: aksiyon,
      ));
  }

  Future<void> _kodBulundu(String kod) async {
    if (_mesgul) return;
    // Üstte başka sayfa açıksa (ör. depoya giriş) okunan kod bu ekranın değil.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;

    // Aynı kod kamerada durduğu sürece sürekli alarm çalmasın.
    final simdi = DateTime.now();
    if (kod == _sonKod &&
        simdi.difference(_sonZaman) < const Duration(seconds: 3)) {
      return;
    }
    _sonKod = kod;
    _sonZaman = simdi;
    _mesgul = true;

    try {
      final db = ref.read(appDatabaseProvider);
      final seriler = seriNolariAyir(kod);
      if (seriler.isEmpty) return;

      // Koli karekodu: içinde kolideki bütün seri numaraları var.
      if (seriler.length > 1) {
        if (!_liste.aktif) {
          SesServisi.basari();
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          await koliKarekoduGoster(context, ref, seriler,
              ac: (w) async {
            await _ac<Object?>(w);
          });
          _sonZaman = DateTime.now(); // kapanınca aynı koliyi hemen açmasın
          return;
        }
        final kodlar = <(String, bool)>[];
        for (final s in seriler) {
          final b = await db.seriNoIleCihazBilgi(s);
          if (b != null) _bilgiler[b.cihaz.seriNo] = b;
          kodlar.add((b?.cihaz.seriNo ?? s, b != null));
        }
        final sonuc = _liste.koliOkut(kodlar);
        sonuc.eklendi > 0 ? SesServisi.basari() : SesServisi.hata();
        _degisti();
        _bilgi(sonuc.ozet(girisListesi: _liste.girisListesi),
            renk: sonuc.eklendi == 0 ? Colors.red.shade700 : null, sn: 4);
        return;
      }

      kod = seriler.first;
      final bilgi = await db.seriNoIleCihazBilgi(kod);
      if (!mounted) return;

      if (bilgi == null) {
        // Malzemenin (kablo, adaptör…) fabrika barkodu mu?
        final urun = await db.barkodIleUrunBul(kod);
        if (!mounted) return;
        if (urun != null && !urun.deleted && urun.miktarli) {
          if (_liste.aktif) {
            await _malzemeOkut(urun);
            return;
          }
          await _malzemeMenusu(urun);
          return;
        }
        _sonucuIsle(_liste.okut(kod, kayitli: false), kod, null);
        return;
      }

      // Eski (yenisi basılmış) kurum etiketi okutulduysa uyar.
      if (!_liste.aktif) {
        final okuma = EtiketKodu.coz(kod);
        if (okuma?.surum != null) {
          final e = await db.etiketBul(okuma!.kod);
          if (e != null && okuma.surum! < e.surum && mounted) {
            SesServisi.hata();
            await showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                icon: const Icon(Icons.warning_amber, color: Colors.orange),
                title: const Text('Eski etiket'),
                content: Text('Bu etiketin yenisi basıldı (sürüm ${e.surum}). '
                    'Okuttuğunuz etiket sürüm ${okuma.surum}; cihaz üzerindeki '
                    'eski etiketi yenisiyle değiştirin.\n\n${e.kod} · ${e.seriNo}'),
                actions: [
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Tamam')),
                ],
              ),
            );
            if (!mounted) return;
          }
        }
      }
      _sonucuIsle(
          _liste.okut(bilgi.cihaz.seriNo, kayitli: true), kod, bilgi);
    } finally {
      _mesgul = false;
    }
  }

  Future<void> _malzemeMenusu(Urun urun) async {
    SesServisi.basari();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final secim = await secenekMenusu(context,
        baslik: '${urun.ad} (malzeme, ${urun.birim})',
        secenekler: const [
          ('giris', Icons.add_circle_outline, 'Giriş'),
          ('yukle', Icons.local_shipping_outlined, 'Araca Yükle'),
          ('kullanim', Icons.task_alt, 'Montaj / Kullanıldı'),
          ('transfer', Icons.swap_horiz, 'Transfer'),
        ]);
    if (secim == null || !mounted) return;
    await _ac(MalzemeIslemScreen(
        islem: MalzemeIslemi.values.firstWhere((m) => m.name == secim),
        onceUrunId: urun.id));
  }

  /// Malzeme barkodu (hızlı işlem seçiliyken): kutu içeriği kadar eklenir;
  /// Montajda (kısmen kullanılır) metre / miktar sorulur.
  Future<void> _malzemeOkut(Urun urun) async {
    var miktar = urun.okutmaMiktari;
    if (_liste.islem == OkutIslemi.montaj &&
        (miktar > 1 || urun.birim != 'adet')) {
      SesServisi.basari();
      final n = await malzemeMiktariSor(context, urun,
          aciklama: 'Kaç ${urun.birim} kullanıldı?');
      if (n == null || n <= 0 || !mounted) return;
      miktar = n;
    } else {
      SesServisi.basari();
    }
    _liste.malzemeEkle(urun.id, miktar);
    _degisti();
    _bilgi('${urun.ad} · ${urun.kutuluMetin(_liste.malzemeler[urun.id] ?? 0)}');
  }

  /// "+ Malzeme": listeden seç ya da yeni tanımla, miktarı gir.
  Future<void> _malzemeEkle() async {
    final id = await malzemeSec(context, ref);
    if (id == null || !mounted) return;
    // Yeni tanımlanan ürünün listeye düşmesi için kısa bekleme.
    Urun? u;
    for (var i = 0; i < 10 && u == null; i++) {
      u = (ref.read(urunlerStreamProvider).valueOrNull ?? <Urun>[])
          .where((x) => x.id == id)
          .firstOrNull;
      if (u == null) await Future.delayed(const Duration(milliseconds: 150));
    }
    if (u == null || !mounted) return;
    final n = await malzemeMiktariSor(context, u,
        mevcut: _liste.islem == OkutIslemi.montaj ? null : u.okutmaMiktari);
    if (n == null || n <= 0 || !mounted) return;
    _liste.malzemeEkle(u.id, n);
    _degisti();
  }

  void _sonucuIsle(OkutSonucu sonuc, String kod, CihazBilgi? bilgi) {
    if (bilgi != null) _bilgiler[bilgi.cihaz.seriNo] = bilgi;
    final ad = bilgi == null ? kod : '${bilgi.urunAdi} · ${bilgi.cihaz.seriNo}';
    switch (sonuc) {
      case OkutSonucu.kartAc:
        SesServisi.basari();
        unawaited(_ac(CihazDetayScreen(cihazId: bilgi!.cihaz.id)));
      case OkutSonucu.ilkKayitsiz:
        SesServisi.hata();
        _bilgi(
          'Kayıtlı cihaz yok: $kod\n'
          'Bir kayıtsız daha okutursanız liste başlar.',
          renk: Colors.red.shade700,
          sn: 6,
          aksiyon: SnackBarAction(
            label: 'Depoya ekle',
            textColor: Colors.white,
            onPressed: () async {
              final ok = await _ac<bool>(TopluGirisScreen(onceSeriNolari: [kod]));
              if (ok == true) _liste.saymayiSifirla();
            },
          ),
        );
      case OkutSonucu.topluBasladi:
        SesServisi.hata();
        _degisti();
        _bilgi('Arka arkaya okutma başladı · ${_liste.seriler.length} kayıtsız',
            renk: Colors.red.shade700);
      case OkutSonucu.sor:
        SesServisi.basari();
        unawaited(_sor(bilgi!));
      case OkutSonucu.eklendi:
        SesServisi.basari();
        _degisti();
      case OkutSonucu.zatenListede:
        _bilgi('Zaten listede: $ad');
      case OkutSonucu.atlandiKayitli:
        SesServisi.hata();
        _bilgi('Kayıtlı · atlandı: $ad', renk: Colors.orange.shade800);
      case OkutSonucu.atlandiKayitsiz:
        SesServisi.hata();
        _bilgi('Kayıtsız · liste dışı: $kod', renk: Colors.orange.shade800);
      case OkutSonucu.dolu:
        SesServisi.hata();
        _bilgi(
            'Liste doldu (0/${_liste.sinir}). Önce bu listeyi işleyin, '
            'sonra yeni listeyle devam edin.',
            renk: Colors.red.shade700,
            sn: 5);
    }
  }

  /// 1. kayıtsızdan sonra kayıtlı cihaz okutuldu: Atla / Kartı aç.
  Future<void> _sor(CihazBilgi b) async {
    final kart = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.info_outline),
        title: const Text('Kayıtlı cihaz'),
        content: Text('${b.urunAdi}\nSN: ${b.cihaz.seriNo}\n'
            '${cihazKonumMetni(b)}\n\n'
            'Atlayıp okutmaya devam edilsin mi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kartı aç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Atla')),
        ],
      ),
    );
    if (!mounted) return;
    _sonZaman = DateTime.now();
    if (kart == true) {
      _liste.saymayiSifirla();
      await _ac(CihazDetayScreen(cihazId: b.cihaz.id));
    }
  }

  void _okundu(BarcodeCapture capture) {
    final kodlar = okunanKodlar(capture);
    if (kodlar.isEmpty) return;
    if (kodlar.length > 1) {
      // Etikette birden çok barkod: hangisinin seri no olduğu belli değil.
      if (!_coklu) setState(() => _coklu = true);
      return;
    }
    if (_coklu) setState(() => _coklu = false);
    _kodBulundu(kodlar.first);
  }

  /// Elle yazılan / USB barkod okuyucudan gelen kod (kamera gibi işlenir).
  Future<void> _yazilan(String v) async {
    final kod = v.trim();
    if (kod.isEmpty) return;
    _yazCtrl.clear();
    _sonKod = null; // aynı kod bilerek tekrar yazılabilsin
    await _kodBulundu(kod);
  }

  // -------------------------------------------------------------------- ekran

  @override
  Widget build(BuildContext context) {
    final aktif = _liste.aktif;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seri No Okut'),
        actions: ustDugmeler(),
      ),
      body: Column(
        children: [
          if (!aktif) const KritikStokSeridi(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _kamera(),
              ),
            ),
          ),
          if (aktif) _listePaneli() else _altBolum(),
        ],
      ),
    );
  }

  Widget? _sayac() {
    if (!_liste.aktif) return null;
    final kalan = _liste.kalan;
    final renk = kalan <= 0
        ? Colors.red.shade400
        : (kalan <= 10 ? Colors.orange.shade400 : Colors.white);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text('$kalan/${_liste.sinir}',
          style: TextStyle(
              color: renk, fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }

  Widget _kamera() {
    return Stack(
      children: [
        HedefliTarayici(
          controller: _controller,
          onDetect: _okundu,
          ustOrta: _sayac(),
          // Kayıtlı seri no / kurum etiketi / malzeme barkodu hızlı okunur,
          // bilinmeyen kod biraz daha uzun sabit tutulmalı.
          bilinenMi: (kod) async {
            final db = ref.read(appDatabaseProvider);
            if (await db.seriNoIleCihazBilgi(kod) != null) return true;
            final u = await db.barkodIleUrunBul(kod);
            return u != null && u.miktarli;
          },
        ),
        if (_coklu)
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black87,
              padding: const EdgeInsets.all(12),
              child: const Text(
                'Çerçevede birden çok kod var. Yaklaştırıp yalnızca seri no kodunu çerçeveye alın.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.amber),
              ),
            ),
          ),
      ],
    );
  }

  /// Bilgisayarda (USB barkod okuyucu) ve gerektiğinde elle yazma alanı.
  Widget _yazmaAlani({required String etiket}) => TextField(
        controller: _yazCtrl,
        textCapitalization: TextCapitalization.characters,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          isDense: true,
          labelText: etiket,
          prefixIcon: const Icon(Icons.keyboard_outlined, color: Renkler.depo),
          suffixIcon: IconButton(
            icon: const Icon(Icons.add_circle, color: Renkler.okut),
            tooltip: 'Ekle',
            onPressed: () => _yazilan(_yazCtrl.text),
          ),
        ),
        onSubmitted: _yazilan,
      );

  /// Arka arkaya okutma sürerken: okutulanlar ve işlemin düğmesi.
  Widget _listePaneli() {
    final i = _liste.islem!;
    final tema = Theme.of(context);
    final yukseklik = MediaQuery.sizeOf(context).height;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
              decoration: BoxDecoration(
                color: i.zemin,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(i.ikon, color: i.renk),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${i.ad} · ${_liste.girisListesi ? 'kayıtsız' : 'kayıtlı'} '
                      'cihazları okutun',
                      style: TextStyle(
                          color: i.renk, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Malzeme ekle (kablo, adaptör…)',
                    icon: const Icon(Icons.add_link, color: Renkler.urun),
                    onPressed: _malzemeEkle,
                  ),
                  IconButton(
                    tooltip: 'Fener',
                    icon: const Icon(Icons.flashlight_on_outlined,
                        color: Renkler.zil),
                    onPressed: () async {
                      try {
                        await _controller.toggleTorch();
                      } catch (_) {}
                    },
                  ),
                  TextButton(
                    onPressed: _temizle,
                    child: Text(_liste.bos ? 'Kapat' : 'Temizle'),
                  ),
                ],
              ),
            ),
            if (bilgisayarTarayicisi)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _yazmaAlani(etiket: 'Seri no (USB okuyucu / elle)'),
              ),
            if (_liste.malzemeler.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: yukseklik * 0.14),
                child: SingleChildScrollView(
                  child: MalzemeKalemleri(
                    miktarlar: _liste.malzemeler,
                    urunler: {
                      for (final u in ref.watch(urunlerStreamProvider)
                              .valueOrNull ??
                          <Urun>[])
                        u.id: u
                    },
                    onDegisti: (id, n) {
                      _liste.malzemeAyarla(id, n);
                      _degisti();
                    },
                  ),
                ),
              ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: yukseklik * 0.24),
              child: _liste.seriler.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        'Okuttukça burada alt alta listelenir. Koli karekodu '
                        'okutulursa içindekilerin hepsi eklenir. Kablo / '
                        'adaptör için barkodu okutun ya da 🔗+ ile ekleyin.',
                        textAlign: TextAlign.center,
                        style: tema.textTheme.bodySmall,
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      reverse: false,
                      itemCount: _liste.seriler.length,
                      itemBuilder: (context, n) {
                        // En son okutulan en üstte.
                        final s = _liste.seriler[_liste.seriler.length - 1 - n];
                        final b = _bilgiler[s];
                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          contentPadding: const EdgeInsets.only(left: 4),
                          leading: Icon(
                              b == null ? Icons.fiber_new : Icons.check_circle,
                              color: b == null ? Renkler.cikis : Renkler.okut),
                          title: Text(b == null ? s : b.urunAdi,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              b == null
                                  ? 'Kayıtsız'
                                  : 'SN: ${b.cihaz.seriNo} · ${cihazKonumMetni(b)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Listeden çıkar',
                            onPressed: () {
                              _liste.cikar(s);
                              _bilgiler.remove(s);
                              _degisti();
                            },
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 6),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: i.renk,
                minimumSize: const Size.fromHeight(52),
                textStyle:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
              ),
              icon: Icon(i.ikon),
              label: Text(i.dugme(_liste.kalemSayisi)),
              onPressed: _liste.bos ? null : _isle,
            ),
          ],
        ),
      ),
    );
  }

  /// Kameranın altı: "Elle yaz" / "Fener" ve hızlı işlemler (Depoya giriş,
  /// Transfer, Araca Yükle, Montaj / Kullanıldı).
  Widget _altBolum() {
    final tema = Theme.of(context);
    Widget ikincil(IconData ikon, Color renk, String ad, VoidCallback f) =>
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: tema.colorScheme.onSurface,
              side: BorderSide(color: tema.colorScheme.outline, width: 1.2),
              textStyle:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            icon: Icon(ikon, color: renk, size: 22),
            label: Text(ad),
            onPressed: f,
          ),
        );

    Widget kutu(OkutIslemi i) => Material(
          color: i.zemin,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _islemSec(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(children: [
                RenkliSimge(i.ikon,
                    renk: i.renk, zemin: i.zemin, boyut: 38, dolu: true),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(i.ad,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w500)),
                ),
              ]),
            ),
          ),
        );

    final kutular = [for (final i in OkutIslemi.values) kutu(i)];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (bilgisayarTarayicisi)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _yazmaAlani(etiket: 'Seri no (USB okuyucu / elle)'),
              ),
            Row(children: [
              ikincil(Icons.keyboard_outlined, Renkler.depo, 'Elle yaz',
                  () => _ac(const CihazAraScreen())),
              const SizedBox(width: 8),
              ikincil(Icons.flashlight_on_outlined, Renkler.zil, 'Fener',
                  () async {
                try {
                  await _controller.toggleTorch();
                } catch (_) {}
              }),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
              child: Text('HIZLI İŞLEMLER',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.4,
                      color: tema.colorScheme.onSurfaceVariant)),
            ),
            LayoutBuilder(builder: (context, c) {
              // Geniş ekranda (bilgisayar) dördü tek satırda.
              final sutun = c.maxWidth >= 640 ? 4 : 2;
              final satirlar = <Widget>[];
              for (var i = 0; i < kutular.length; i += sutun) {
                if (i > 0) satirlar.add(const SizedBox(height: 8));
                satirlar.add(Row(children: [
                  for (var j = i; j < i + sutun; j++) ...[
                    if (j > i) const SizedBox(width: 8),
                    Expanded(child: kutular[j]),
                  ],
                ]));
              }
              return Column(children: satirlar);
            }),
          ],
        ),
      ),
    );
  }
}
