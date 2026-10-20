import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../database/app_database.dart';
import '../../database/models.dart';
import '../../providers/app_providers.dart';
import '../../services/adres_servisi.dart';
import '../../services/konum_izleyici.dart';
import '../../services/konum_servisi.dart';
import '../../services/ses_servisi.dart';
import '../../services/taslak_servisi.dart';
import '../../widgets/hedefli_tarayici.dart';
import '../../widgets/kod_yardimci.dart';
import '../../widgets/renkler.dart';
import 'cihaz_detay_screen.dart';

/// Montaj / Kullanıldı: bir noktaya birlikte takılan cihazlar (ör. 3 kamera,
/// 1 kayıt cihazı, 1 router) arka arkaya okutulur; yer, not, tutanak ve
/// kullanılan malzemeler bir kez girilir, hepsi AYNI koordinatla kaydolur.
/// Konum ekran açılınca ısınır, "Kaydet"e basıldığı andaki konum kaydedilir.
/// Kaydettikten sonra "Sonraki nokta" ile aynı yerde devam edilir.
class MontajScreen extends ConsumerStatefulWidget {
  const MontajScreen({
    super.key,
    this.onceSeriNolari = const [],
    this.taslaktan = false,
  });

  /// Listeye hazır gelecek cihazlar (cihaz kartından ya da Okut'tan).
  final List<String> onceSeriNolari;

  /// Yarım kalan montaja devam (soru sorulmaz).
  final bool taslaktan;

  @override
  ConsumerState<MontajScreen> createState() => _MontajScreenState();
}

class _MontajScreenState extends ConsumerState<MontajScreen>
    with YarimIsKorumasi<MontajScreen> {
  final _seriCtrl = TextEditingController();
  final _yerCtrl = TextEditingController();
  final _notCtrl = TextEditingController();
  final _ilCtrl = TextEditingController();
  final _ilceCtrl = TextEditingController();
  final _mahalleCtrl = TextEditingController();
  final _liste = <CihazBilgi>[];
  final _kullanilan = <String, int>{};
  final _konum = KonumIzleyici();

  String? _tutanak;
  bool _konumKaydet = true;
  String? _malzemeDepoId;
  List<MalzemeStok> _malzemeler = const [];

  bool _kameraAcik = false;
  bool _coklu = false;
  bool _mesgul = false;
  bool _kaydediliyor = false;
  int? _bekleSn; // "Konum bekleniyor… (8 sn)"
  MobileScannerController? _kamera;
  String? _sonKod;
  DateTime _sonZaman = DateTime.fromMillisecondsSinceEpoch(0);

  bool _adresIstendi = false;
  String? _adresDurumu;

  /// Kaydedilen son noktanın özeti (doluysa "Sonraki nokta" ekranı görünür).
  String? _kaydedildi;

  @override
  void initState() {
    super.initState();
    _konum.addListener(_konumDegisti);
    unawaited(_konum.baslat());
    if (widget.onceSeriNolari.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _cokluEkle(widget.onceSeriNolari, sessiz: true));
    } else if (!widget.taslaktan) {
      // Boş açıldıysa okutmaya hemen başlanabilsin.
      _kamera = tarayiciOlustur();
      _kameraAcik = true;
    }
    taslakKorumasiniBaslat(dinlenecekler: [
      _yerCtrl,
      _notCtrl,
      _ilCtrl,
      _ilceCtrl,
      _mahalleCtrl,
    ]);
  }

  @override
  void dispose() {
    taslakKorumasiniBitir(dinlenecekler: [
      _yerCtrl,
      _notCtrl,
      _ilCtrl,
      _ilceCtrl,
      _mahalleCtrl,
    ]);
    _konum.removeListener(_konumDegisti);
    _konum.dispose();
    for (final c in [
      _seriCtrl,
      _yerCtrl,
      _notCtrl,
      _ilCtrl,
      _ilceCtrl,
      _mahalleCtrl,
    ]) {
      c.dispose();
    }
    _kamera?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- taslak

  @override
  String get taslakTuru => 'montaj';

  @override
  bool get taslaktanAcildi => widget.taslaktan;

  @override
  Taslak? taslakOlustur() {
    if (_kaydedildi != null) return null;
    final bos = _liste.isEmpty &&
        _yerCtrl.text.trim().isEmpty &&
        _notCtrl.text.trim().isEmpty;
    if (bos) return null;
    return Taslak(
      tur: taslakTuru,
      baslik: 'Montaj / Kullanıldı'
          '${_yerCtrl.text.trim().isEmpty ? '' : ' · ${_yerCtrl.text.trim()}'}',
      ozet: '${_liste.length} cihaz',
      veri: {
        'seriler': [for (final b in _liste) b.cihaz.seriNo],
        'yer': _yerCtrl.text,
        'not': _notCtrl.text,
        'il': _ilCtrl.text,
        'ilce': _ilceCtrl.text,
        'mahalle': _mahalleCtrl.text,
        'tutanak': _tutanak,
        'konum': _konumKaydet,
        'malzemeDepoId': _malzemeDepoId,
        'malzemeler': Map.of(_kullanilan),
      },
    );
  }

  @override
  Future<void> taslagiYukle(Taslak t) async {
    final v = t.veri;
    _yerCtrl.text = v['yer'] as String? ?? '';
    _notCtrl.text = v['not'] as String? ?? '';
    _ilCtrl.text = v['il'] as String? ?? '';
    _ilceCtrl.text = v['ilce'] as String? ?? '';
    _mahalleCtrl.text = v['mahalle'] as String? ?? '';
    setState(() {
      _tutanak = v['tutanak'] as String?;
      _konumKaydet = v['konum'] as bool? ?? true;
      _kullanilan
        ..clear()
        ..addAll({
          for (final e in ((v['malzemeler'] as Map?) ?? const {}).entries)
            '${e.key}': (e.value as num?)?.toInt() ?? 0,
        });
    });
    await _cokluEkle([for (final s in (v['seriler'] as List? ?? [])) '$s'],
        sessiz: true);
    final d = v['malzemeDepoId'] as String?;
    if (d != null && _liste.any((b) => b.cihaz.depoId == d)) {
      await _malzemeDeposuSec(d, sifirla: false);
    }
  }

  // ----------------------------------------------------------------- konum

  void _konumDegisti() {
    if (!mounted) return;
    setState(() {});
    final p = _konum.gosterilen;
    // GPS'ten ilk iyi konum gelince il / ilçe / mahalle bir kez bulunur.
    if (!_adresIstendi && _konum.gpsVar && p != null && p.accuracy <= 50) {
      _adresIstendi = true;
      unawaited(_adresBul(p.latitude, p.longitude));
    }
  }

  Future<void> _adresBul(double enlem, double boylam) async {
    setState(() => _adresDurumu = 'Adres bulunuyor…');
    final a = await AdresServisi.konumdanAdres(enlem, boylam);
    if (!mounted) return;
    setState(() {
      if (a == null) {
        _adresDurumu = 'İnternet yok: bölge sonra otomatik bulunacak';
        return;
      }
      if (_ilCtrl.text.isEmpty) _ilCtrl.text = a.il ?? '';
      if (_ilceCtrl.text.isEmpty) _ilceCtrl.text = a.ilce ?? '';
      if (_mahalleCtrl.text.isEmpty) _mahalleCtrl.text = a.mahalle ?? '';
      _adresDurumu =
          a.bos ? 'Bu konum için bölge bulunamadı' : 'Konumdan bulundu';
    });
  }

  // ----------------------------------------------------------- cihaz listesi

  void _mesaj(String metin, {bool hata = false, int sn = 2}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(metin),
        backgroundColor: hata ? Colors.red.shade700 : null,
        duration: Duration(seconds: sn),
      ));
  }

  /// Seri no montaja eklenebilir mi? Eklenebilirse cihaz, değilse sebebi.
  Future<(CihazBilgi?, String?)> _kontrol(String seri) async {
    if (_liste.any((b) => b.cihaz.seriNo == seri)) {
      return (null, '$seri zaten listede');
    }
    final db = ref.read(appDatabaseProvider);
    final bilgi = await db.seriNoIleCihazBilgi(seri);
    if (bilgi == null) return (null, 'Kayıtlı cihaz yok: $seri');
    if (_liste.any((b) => b.cihaz.id == bilgi.cihaz.id)) {
      return (null, '${bilgi.cihaz.seriNo} zaten listede');
    }
    if (bilgi.cihaz.durum != CihazDurumu.depoda) {
      return (
        null,
        '${bilgi.cihaz.seriNo} şu an depoda / araçta değil '
            '(${cihazKonumMetni(bilgi)})'
      );
    }
    if (bilgi.cihaz.arizali) {
      return (
        null,
        '${bilgi.cihaz.seriNo} ${bilgi.cihaz.servisDurumu!.kisa.toLowerCase()}: '
            'montajda kullanılamaz'
      );
    }
    final engel = await db.etiketEngeli(bilgi.cihaz.id);
    if (engel != null) return (null, engel);
    return (bilgi, null);
  }

  Future<void> _ekle(String ham) async {
    final seriler = seriNolariAyir(ham);
    if (seriler.isEmpty) return;
    if (seriler.length > 1) {
      _seriCtrl.clear();
      await _cokluEkle(seriler);
      return;
    }
    final (bilgi, hata) = await _kontrol(seriler.first);
    if (!mounted) return;
    if (bilgi == null) {
      SesServisi.hata();
      _mesaj(hata!, hata: true);
      return;
    }
    SesServisi.basari();
    setState(() {
      _liste.add(bilgi);
      _seriCtrl.clear();
    });
    await _malzemeDeposunuBelirle();
  }

  /// Koli karekodu / Okut'tan gelen liste: eklenemeyenler atlanır, bildirilir.
  Future<void> _cokluEkle(List<String> seriler, {bool sessiz = false}) async {
    final eklenecek = <CihazBilgi>[];
    final atlanan = <String>[];
    for (final s in seriler) {
      final (bilgi, hata) = await _kontrol(s);
      if (bilgi != null && !eklenecek.any((b) => b.cihaz.id == bilgi.cihaz.id)) {
        eklenecek.add(bilgi);
        // _kontrol listede olanı görür; bu turda ekleneni de görsün.
        _liste.add(bilgi);
      } else if (hata != null) {
        atlanan.add(hata);
      }
    }
    if (!mounted) return;
    setState(() {});
    if (!sessiz) {
      eklenecek.isEmpty ? SesServisi.hata() : SesServisi.basari();
    }
    if (atlanan.isNotEmpty) {
      _mesaj(
          '${eklenecek.length} cihaz eklendi, ${atlanan.length} atlandı:\n'
          '${atlanan.take(4).join('\n')}${atlanan.length > 4 ? '\n…' : ''}',
          hata: eklenecek.isEmpty,
          sn: 6);
    } else if (!sessiz) {
      _mesaj('${eklenecek.length} cihaz eklendi');
    }
    await _malzemeDeposunuBelirle();
  }

  void _kameraDegistir() {
    if (_kameraAcik) {
      final eski = _kamera;
      setState(() {
        _kameraAcik = false;
        _kamera = null;
        _coklu = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => eski?.dispose());
    } else {
      setState(() {
        _kamera = tarayiciOlustur();
        _kameraAcik = true;
      });
    }
  }

  Future<void> _okundu(BarcodeCapture capture) async {
    if (_mesgul || _kaydedildi != null) return;
    final kodlar = okunanKodlar(capture);
    if (kodlar.isEmpty) return;
    if (kodlar.length > 1) {
      if (!_coklu && mounted) setState(() => _coklu = true);
      return;
    }
    if (_coklu && mounted) setState(() => _coklu = false);
    final kod = kodlar.first;
    final simdi = DateTime.now();
    if (kod == _sonKod &&
        simdi.difference(_sonZaman) < const Duration(seconds: 3)) {
      return;
    }
    _sonKod = kod;
    _sonZaman = simdi;
    _mesgul = true;
    try {
      await _ekle(kod);
    } finally {
      _mesgul = false;
    }
  }

  // ------------------------------------------------------------- malzemeler

  /// Malzemeler listedeki cihazların bulunduğu araçtan / depodan düşer.
  /// Birden çok yer varsa seçilir; yoksa araç olan önceliklidir.
  Future<void> _malzemeDeposunuBelirle() async {
    final yerler = {for (final b in _liste) b.cihaz.depoId}.whereType<String>();
    if (yerler.isEmpty) {
      setState(() {
        _malzemeDepoId = null;
        _malzemeler = const [];
        _kullanilan.clear();
      });
      return;
    }
    if (_malzemeDepoId != null && yerler.contains(_malzemeDepoId)) return;
    final depolar = ref.read(depolarStreamProvider).valueOrNull ?? <Depo>[];
    final arac = yerler
        .where((id) => depolar.any((d) => d.id == id && d.arac))
        .firstOrNull;
    await _malzemeDeposuSec(arac ?? yerler.first);
  }

  Future<void> _malzemeDeposuSec(String depoId, {bool sifirla = true}) async {
    final m = await ref.read(appDatabaseProvider).depoMalzemeleri(depoId);
    if (!mounted) return;
    setState(() {
      _malzemeDepoId = depoId;
      _malzemeler = m;
      if (sifirla) _kullanilan.clear();
      _kullanilan.removeWhere((id, _) => !m.any((x) => x.urun.id == id));
    });
  }

  Future<int?> _sayiSor(MalzemeStok m, int mevcut) async {
    final ctrl = TextEditingController(text: '$mevcut');
    final n = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(m.urun.ad),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Kullanılan (${m.urun.birim})',
            helperText: 'Burada: ${m.urun.miktarMetni(m.miktar)}',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v.trim())),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
              child: const Text('Tamam')),
        ],
      ),
    );
    ctrl.dispose();
    if (n == null) return null;
    return n.clamp(0, m.miktar);
  }

  // ------------------------------------------------------------------ kaydet

  Future<void> _kaydet() async {
    if (_liste.isEmpty) {
      _mesaj('Önce cihazları okutun', hata: true);
      return;
    }
    if (_yerCtrl.text.trim().isEmpty) {
      _mesaj('Nerede kullanıldığını yazın', hata: true);
      return;
    }
    if (_tutanak == null) {
      _mesaj('Tutanak durumunu seçin (Alındı / Alınacak / Kurum içi)',
          hata: true);
      return;
    }
    setState(() => _kaydediliyor = true);
    try {
      KonumSonucu? k;
      if (_konumKaydet) {
        k = await _konum.kaydetAnindakiKonum(kalanSaniye: (s) {
          if (mounted) setState(() => _bekleSn = s);
        });
        if (!mounted) return;
        setState(() => _bekleSn = null);
        if (!k.basarili) {
          final secim = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(Icons.location_off),
              title: const Text('Konum bulunamadı'),
              content: Text('${k!.hata}.\n\nKonumsuz kaydedilsin mi, yoksa '
                  'açık alanda tekrar denensin mi?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Vazgeç')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, 'tekrar'),
                    child: const Text('Tekrar dene')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, 'konumsuz'),
                    child: const Text('Konumsuz kaydet')),
              ],
            ),
          );
          if (!mounted) return;
          if (secim == 'tekrar') {
            setState(() => _kaydediliyor = false);
            await _kaydet();
            return;
          }
          if (secim != 'konumsuz') return;
          k = null;
        }
      }
      String? bosIseNull(TextEditingController c) =>
          c.text.trim().isEmpty ? null : c.text.trim();
      final db = ref.read(appDatabaseProvider);
      final adet = _liste.length;
      final malzemeli = _kullanilan.values.any((m) => m > 0);
      await db.cihazlariTopluHareketKaydet(
        cihazIdleri: [for (final b in _liste) b.cihaz.id],
        tip: HareketTipi.kullanim,
        kullaniciId: ref.read(aktifKullaniciIdProvider) ?? 'demo-kullanici',
        kullanimYeri: _yerCtrl.text.trim(),
        not_: bosIseNull(_notCtrl),
        enlem: k?.enlem,
        boylam: k?.boylam,
        konumHassasiyet: k?.hassasiyet,
        il: bosIseNull(_ilCtrl),
        ilce: bosIseNull(_ilceCtrl),
        mahalle: bosIseNull(_mahalleCtrl),
        tutanak: _tutanak,
        malzemeler: Map.of(_kullanilan),
        malzemeDepoId: _malzemeDepoId,
      );
      // İnternet varsa eksik bölge (il / ilçe / mahalle) hemen tamamlanır.
      unawaited(AdresTamamlayici.calistir(db));
      SesServisi.basari();
      await taslakTamamlandi();
      if (!mounted) return;
      final konumMetni = k == null
          ? 'Konumsuz'
          : 'Konum: ${KonumServisi.koordinat(k.enlem!, k.boylam!)}'
              '${k.hassasiyet == null ? '' : ' (±${k.hassasiyet!.round()} m)'}';
      if (_kameraAcik) _kameraDegistir();
      setState(() => _kaydedildi = '$adet cihaz montajı kaydedildi'
          '${malzemeli ? ' (malzemelerle)' : ''}\n'
          '${_yerCtrl.text.trim()} · ${tutanakAdi(_tutanak)}\n$konumMetni');
    } catch (e) {
      SesServisi.hata();
      _mesaj(e is StateError ? e.message : 'Kaydedilemedi: $e',
          hata: true, sn: 5);
    } finally {
      if (mounted) {
        setState(() {
          _kaydediliyor = false;
          _bekleSn = null;
        });
      }
    }
  }

  /// Aynı yerde bir sonraki noktaya geç: liste boşalır; yer ve tutanak kalır;
  /// konum yeni noktada (Kaydet anında) yeniden alınır.
  void _sonrakiNokta() {
    _notCtrl.clear();
    _ilCtrl.clear();
    _ilceCtrl.clear();
    _mahalleCtrl.clear();
    setState(() {
      _kaydedildi = null;
      _liste.clear();
      _kullanilan.clear();
      _malzemeDepoId = null;
      _malzemeler = const [];
      _adresIstendi = false;
      _adresDurumu = null;
    });
    taslakKorumasiniYenile();
    if (!_kameraAcik) _kameraDegistir();
  }

  // -------------------------------------------------------------------- ekran

  @override
  Widget build(BuildContext context) {
    final govde = _kaydedildi == null ? _form(context) : _bittiEkrani(context);
    return yarimIsKapsayici(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Montaj / Kullanıldı'),
          actions: [
            if (_kaydedildi == null)
              IconButton(
                icon: Icon(
                    _kameraAcik
                        ? Icons.no_photography_outlined
                        : Icons.qr_code_scanner,
                    color: _kameraAcik ? Renkler.cikis : Renkler.okut,
                    size: 26),
                tooltip: _kameraAcik ? 'Kamerayı kapat' : 'Kamerayla okut',
                onPressed: _kameraDegistir,
              ),
          ],
        ),
        body: govde,
      ),
    );
  }

  Widget _bittiEkrani(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Renkler.okutZemin,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 28,
                    backgroundColor: Renkler.okut,
                    child: Icon(Icons.check, color: Colors.white, size: 32),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _kaydedildi!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '"Sonraki nokta"da liste boşalır; yer ve tutanak aynen kalır, '
              'konum yeni noktada Kaydet\'e basınca alınır.',
            ),
            const Spacer(),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Renkler.montaj,
                minimumSize: const Size.fromHeight(56),
                textStyle:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
              ),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Sonraki nokta'),
              onPressed: _sonrakiNokta,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Bitti, çık'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _konumSeridi() {
    final p = _konum.gosterilen;
    final IconData ikon;
    final Color renk;
    final Color zemin;
    final String baslik;
    final String alt;
    if (_konum.hata != null) {
      ikon = Icons.location_off;
      renk = Renkler.cikis;
      zemin = Renkler.cikisZemin;
      baslik = 'Konum yok';
      alt = _konum.hata!;
    } else if (p == null) {
      ikon = Icons.location_searching;
      renk = Renkler.ayar;
      zemin = Renkler.ayarZemin;
      baslik = 'Konum aranıyor…';
      alt = 'Kaydet\'e basınca o andaki konum kaydedilir';
    } else if (!_konum.gpsVar || p.accuracy > KonumIzleyici.iyiHassasiyet) {
      ikon = Icons.gps_not_fixed;
      renk = Renkler.urun;
      zemin = Renkler.urunZemin;
      baslik = _konum.gpsVar
          ? 'Konum zayıf · ±${p.accuracy.round()} m'
          : 'Yaklaşık konum · ±${p.accuracy.round()} m';
      alt = _konum.gpsVar
          ? 'Açık alanda iyileşir'
          : 'GPS ısınıyor, birkaç saniye sürer';
    } else {
      ikon = Icons.gps_fixed;
      renk = Renkler.okut;
      zemin = Renkler.okutZemin;
      baslik = 'Konum hazır · ±${p.accuracy.round()} m';
      alt = 'Kaydet\'e basınca bu andaki konum kaydedilir';
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: _konumKaydet ? zemin : Renkler.ayarZemin,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(_konumKaydet ? ikon : Icons.location_disabled,
              color: _konumKaydet ? renk : Renkler.ayar),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_konumKaydet ? baslik : 'Konum kaydedilmeyecek',
                    style: TextStyle(
                        color: _konumKaydet ? renk : Renkler.ayar,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                if (_konumKaydet)
                  Text(alt, style: const TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
          Switch(
            value: _konumKaydet,
            onChanged: (v) => setState(() => _konumKaydet = v),
          ),
        ],
      ),
    );
  }

  Widget _baslik(String metin) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Text(metin,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.4,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  Widget _form(BuildContext context) {
    final depolar = ref.watch(depolarStreamProvider).valueOrNull ?? <Depo>[];
    final yerler = {for (final b in _liste) b.cihaz.depoId}
        .whereType<String>()
        .toList();
    final secilenMalzeme = _kullanilan.values.where((m) => m > 0).length;
    String depoAdi(String id) =>
        depolar.where((d) => d.id == id).firstOrNull?.ad ?? '-';

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              _konumSeridi(),
              if (_kameraAcik && _kamera != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: (MediaQuery.sizeOf(context).height * 0.28)
                          .clamp(180.0, 280.0),
                      child: Stack(
                        children: [
                          HedefliTarayici(
                              controller: _kamera!, onDetect: _okundu),
                          if (_coklu)
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                width: double.infinity,
                                color: Colors.black87,
                                padding: const EdgeInsets.all(6),
                                child: const Text(
                                  'Çerçevede birden çok kod var. Yalnızca seri '
                                  'no kodunu çerçeveye alın.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: Colors.amber, fontSize: 12),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextField(
                  controller: _seriCtrl,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Seri no (yazın veya okutun)',
                    prefixIcon:
                        const Icon(Icons.qr_code_scanner, color: Renkler.okut),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.add_circle, color: Renkler.okut),
                      tooltip: 'Listeye ekle',
                      onPressed: () => _ekle(_seriCtrl.text),
                    ),
                  ),
                  onSubmitted: _ekle,
                ),
              ),
              _baslik('BU NOKTADAKİ CİHAZLAR (${_liste.length})'),
              if (_liste.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Noktaya takılan cihazları sırayla okutun. '
                      'Koli karekodu okutulursa içindekilerin hepsi eklenir.'),
                ),
              for (var i = 0; i < _liste.length; i++)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.devices_other, color: Renkler.depo),
                  title: Text(_liste[i].urunAdi,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      'SN: ${_liste[i].cihaz.seriNo} · ${_liste[i].depoAdi ?? '-'}'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          CihazDetayScreen(cihazId: _liste[i].cihaz.id))),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Listeden çıkar',
                    onPressed: () async {
                      setState(() => _liste.removeAt(i));
                      await _malzemeDeposunuBelirle();
                    },
                  ),
                ),
              if (!_kameraAcik)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.qr_code_scanner, color: Renkler.okut),
                    label: const Text('+ Başka cihaz okut'),
                    onPressed: _kameraDegistir,
                  ),
                ),
              _baslik('MONTAJ BİLGİSİ · HEPSİNE UYGULANIR'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    TextField(
                      controller: _yerCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nerede kullanıldı?',
                        hintText: 'Örn: SUSURLUK KULAT',
                      ),
                    ),
                    TextField(
                      controller: _notCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Not (isteğe bağlı)',
                          hintText: 'Örn: Muhtarlık önü direği'),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Tutanak',
                          style: Theme.of(context).textTheme.labelLarge),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final (kod, ikon, ad) in const [
                            ('alindi', Icons.check_circle_outline, 'Alındı'),
                            ('alinacak', Icons.hourglass_empty, 'Alınacak'),
                            ('kurum_ici', Icons.apartment, 'Kurum içi kullanım'),
                          ])
                            ChoiceChip(
                              avatar: Icon(ikon, size: 18),
                              label: Text(ad),
                              selected: _tutanak == kod,
                              onSelected: (_) =>
                                  setState(() => _tutanak = kod),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_malzemeDepoId != null)
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    initiallyExpanded: secilenMalzeme > 0,
                    leading:
                        const Icon(Icons.cable_outlined, color: Renkler.urun),
                    title: Text(secilenMalzeme == 0
                        ? 'Kullanılan malzemeler'
                        : 'Kullanılan malzemeler ($secilenMalzeme)'),
                    subtitle: Text(
                        'İsteğe bağlı · ${depoAdi(_malzemeDepoId!)} stoğundan'),
                    children: [
                      if (yerler.length > 1)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: DropdownButtonFormField<String>(
                            value: _malzemeDepoId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                                labelText: 'Malzemeler nereden düşsün?'),
                            items: [
                              for (final id in yerler)
                                DropdownMenuItem(
                                    value: id, child: Text(depoAdi(id))),
                            ],
                            onChanged: (v) {
                              if (v != null) _malzemeDeposuSec(v);
                            },
                          ),
                        ),
                      if (_malzemeler.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Burada malzeme yok.'),
                        ),
                      for (final m in _malzemeler)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${m.urun.ad}\n'
                                  'Burada: ${m.urun.miktarMetni(m.miktar)}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: (_kullanilan[m.urun.id] ?? 0) > 0
                                    ? () => setState(() =>
                                        _kullanilan[m.urun.id] =
                                            (_kullanilan[m.urun.id] ?? 0) - 1)
                                    : null,
                              ),
                              InkWell(
                                onTap: () async {
                                  final n = await _sayiSor(
                                      m, _kullanilan[m.urun.id] ?? 0);
                                  if (n != null) {
                                    setState(() => _kullanilan[m.urun.id] = n);
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Text('${_kullanilan[m.urun.id] ?? 0}',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed:
                                    (_kullanilan[m.urun.id] ?? 0) < m.miktar
                                        ? () => setState(() =>
                                            _kullanilan[m.urun.id] =
                                                (_kullanilan[m.urun.id] ?? 0) +
                                                    1)
                                        : null,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              Theme(
                data:
                    Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: const Icon(Icons.map_outlined, color: Renkler.depo),
                  title: const Text('Bölge (il / ilçe / mahalle)'),
                  subtitle: Text([
                    _mahalleCtrl.text,
                    _ilceCtrl.text,
                    _ilCtrl.text,
                  ].where((e) => e.trim().isNotEmpty).join(', ').ifEmpty(
                      _adresDurumu ?? 'Konumdan bulunur, değiştirilebilir')),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          TextField(
                            controller: _mahalleCtrl,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                                labelText: 'Mahalle / köy'),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _ilceCtrl,
                                  textCapitalization: TextCapitalization.words,
                                  decoration:
                                      const InputDecoration(labelText: 'İlçe'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _ilCtrl,
                                  textCapitalization: TextCapitalization.words,
                                  decoration:
                                      const InputDecoration(labelText: 'İl'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Renkler.montaj,
                minimumSize: const Size.fromHeight(54),
                textStyle:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
              ),
              icon: Icon(_bekleSn != null ? Icons.gps_not_fixed : Icons.place),
              label: Text(_bekleSn != null
                  ? 'Konum bekleniyor… ($_bekleSn sn)'
                  : (_kaydediliyor
                      ? 'Kaydediliyor…'
                      : 'Montajı kaydet (${_liste.length} cihaz)')),
              onPressed: _kaydediliyor ? null : _kaydet,
            ),
          ),
        ),
      ],
    );
  }
}

extension on String {
  String ifEmpty(String yedek) => trim().isEmpty ? yedek : this;
}
