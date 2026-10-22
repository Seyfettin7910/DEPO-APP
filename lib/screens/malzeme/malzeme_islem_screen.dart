import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart';
import '../../database/models.dart';
import '../../providers/app_providers.dart';
import '../../services/ses_servisi.dart';
import '../../services/taslak_servisi.dart';
import '../../widgets/barkod_okuyucu_sayfasi.dart';
import '../../widgets/depo_secici.dart';
import '../../widgets/kod_yardimci.dart';
import '../../widgets/buyuk_harf.dart';
import '../../services/bolge_adi.dart';
import '../../services/adres_servisi.dart';
import '../../services/konum_izleyici.dart';
import '../../services/konum_servisi.dart';
import '../../services/kurum_barkodu.dart';
import '../../widgets/konum_seridi.dart';
import '../../widgets/malzeme_etiketi.dart';

/// Seri numarası olmayan, miktarla takip edilen malzemeler (kablo, adaptör…)
/// için giriş, Araca Yükle, transfer, iade ve Montaj / Kullanıldı.
///
/// Malzeme listeden seçilir ya da stok kodu (266…) etiketi okutulur; miktar
/// +/- ile ya da sayıya dokunup yazarak girilir.
///
/// 1.30.3: Montaj / Kullanıldı'da konum, Montaj ekranındaki gibi Kaydet
/// anında alınır (yalnız ekran açıkken; arka planda konum yok). Konum varsa
/// "Nerede kullanıldı?" boş bırakılabilir; yakında eski montaj adı ya da
/// konumdan bulunan "İLÇE MAHALLE" kendiliğinden yazılır.
class MalzemeIslemScreen extends ConsumerStatefulWidget {
  const MalzemeIslemScreen({
    super.key,
    required this.islem,
    this.onceKaynakId,
    this.onceHedefId,
    this.onceUrunId,
    this.taslaktan = false,
  });

  final MalzemeIslemi islem;
  final String? onceKaynakId;
  final String? onceHedefId;
  final String? onceUrunId;
  final bool taslaktan;

  @override
  ConsumerState<MalzemeIslemScreen> createState() => _MalzemeIslemScreenState();
}

class _MalzemeIslemScreenState extends ConsumerState<MalzemeIslemScreen>
    with YarimIsKorumasi<MalzemeIslemScreen> {
  final _notCtrl = TextEditingController();
  final _yerCtrl = TextEditingController();
  final _barkodCtrl = TextEditingController();

  /// urunId -> miktar (ekleme sırası korunur).
  final _satirlar = <String, int>{};
  String? _kaynakId;
  String? _hedefId;
  bool _kaydediliyor = false;

  // 1.30.3: Montaj / Kullanıldı konumu
  KonumIzleyici? _konum;
  bool _konumKaydet = true;
  int? _bekleSn; // "Konum bekleniyor… (8 sn)"
  bool _adresIstendi = false;
  bool _yakinBakildi = false;
  bool _yakinBulundu = false;
  String? _il, _ilce, _mahalle;
  String? _yerOtomatik; // en son kendiliğinden yazılan yer
  String? _yerKaynagi; // alanın altındaki açıklama

  MalzemeIslemi get _islem => widget.islem;

  @override
  void initState() {
    super.initState();
    _kaynakId = widget.onceKaynakId;
    _hedefId = widget.onceHedefId;
    if (widget.onceUrunId != null) _satirlar[widget.onceUrunId!] = 0;
    taslakKorumasiniBaslat(dinlenecekler: [_notCtrl, _yerCtrl]);
    if (_islem == MalzemeIslemi.kullanim) {
      _konum = KonumIzleyici()..addListener(_konumDegisti);
      unawaited(_konum!.baslat());
    }
  }

  @override
  void dispose() {
    taslakKorumasiniBitir(dinlenecekler: [_notCtrl, _yerCtrl]);
    _konum?.removeListener(_konumDegisti);
    _konum?.dispose();
    _notCtrl.dispose();
    _yerCtrl.dispose();
    _barkodCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------
  // Yarım iş (taslak)
  // ---------------------------------------------------------------

  @override
  String get taslakTuru => 'malzeme_${_islem.name}';

  @override
  bool get taslaktanAcildi => widget.taslaktan;

  @override
  Taslak? taslakOlustur() {
    final dolu = _satirlar.values.where((m) => m > 0).length;
    if (dolu == 0) return null;
    return Taslak(
      tur: taslakTuru,
      baslik: _islem.baslik,
      ozet: '$dolu kalem malzeme',
      veri: {
        'kaynak': _kaynakId,
        'hedef': _hedefId,
        'satirlar': Map.of(_satirlar),
        'yer': _yerCtrl.text,
        'not': _notCtrl.text,
      },
    );
  }

  @override
  Future<void> taslagiYukle(Taslak t) async {
    final v = t.veri;
    setState(() {
      _kaynakId = v['kaynak'] as String? ?? _kaynakId;
      _hedefId = v['hedef'] as String? ?? _hedefId;
      _satirlar.clear();
      final m = (v['satirlar'] as Map?) ?? const {};
      for (final e in m.entries) {
        final n = (e.value as num?)?.toInt() ?? 0;
        if (n > 0) _satirlar['${e.key}'] = n;
      }
    });
    _yerCtrl.text = trBuyuk(v['yer'] as String? ?? '');
    _notCtrl.text = trBuyuk(v['not'] as String? ?? '');
  }

  // --------------------------------------------------------------- konum

  void _konumDegisti() {
    if (!mounted) return;
    setState(() {});
    final k = _konum!;
    final p = k.gosterilen;
    if (!k.gpsVar || p == null) return;
    // Konum ±15 m'den iyiyse: 15 m içinde daha önce yazılmış yer adı var mı?
    if (!_yakinBakildi && p.accuracy <= 15) {
      _yakinBakildi = true;
      unawaited(_yakinAdlariBul(p.latitude, p.longitude));
    }
    // İlk iyi konumda il / ilçe / mahalle bir kez bulunur.
    if (!_adresIstendi && p.accuracy <= 50) {
      _adresIstendi = true;
      unawaited(_adresBul(p.latitude, p.longitude));
    }
  }

  void _yerYaz(String yer, String kaynak) {
    final mevcut = _yerCtrl.text.trim();
    // Boşsa ya da önceki kendiliğinden yazılansa değiştirilir.
    if (mevcut.isNotEmpty && mevcut != _yerOtomatik) return;
    final t = trBuyuk(yer);
    _yerCtrl.text = t;
    _yerOtomatik = t;
    _yerKaynagi = kaynak;
  }

  Future<void> _yakinAdlariBul(double enlem, double boylam) async {
    final adlar = await ref
        .read(appDatabaseProvider)
        .yakindakiKullanimYerleri(enlem, boylam);
    if (!mounted || adlar.isEmpty) return;
    setState(() {
      _yakinBulundu = true;
      _yerYaz(adlar.first, 'Yakındaki eski montajdan (15 m içinde)');
    });
  }

  Future<void> _adresBul(double enlem, double boylam) async {
    final a = await AdresServisi.konumdanAdres(enlem, boylam);
    if (!mounted || a == null) return; // internet yok: sonra tamamlanır
    setState(() {
      _il = a.il;
      _ilce = a.ilce;
      _mahalle = a.mahalle;
      final yer = yerMetni(a.ilce, a.mahalle);
      if (yer.isNotEmpty && !_yakinBulundu) {
        _yerYaz(yer, 'Konumdan bulundu, gerekirse düzeltin');
      }
    });
  }

  /// Kaydet anındaki konum: (devam, konum). Konum alınamazsa "Konumsuz
  /// kaydet / Tekrar dene / Vazgeç" sorulur; vazgeçilirse devam = false.
  Future<(bool, KonumSonucu?)> _kaydetKonumu() async {
    final izleyici = _konum;
    if (izleyici == null || !_konumKaydet) return (true, null);
    while (true) {
      final k = await izleyici.kaydetAnindakiKonum(kalanSaniye: (s) {
        if (mounted) setState(() => _bekleSn = s);
      });
      if (!mounted) return (false, null);
      setState(() => _bekleSn = null);
      if (k.basarili) return (true, k);
      final secim = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.location_off),
          title: const Text('Konum bulunamadı'),
          content: Text('${k.hata}.\n\nKonumsuz kaydedilsin mi, yoksa '
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
      if (!mounted) return (false, null);
      if (secim == 'konumsuz') return (true, null);
      if (secim != 'tekrar') return (false, null);
    }
  }

  // ---------------------------------------------------------------

  void _mesaj(String metin, {bool hata = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(metin),
        backgroundColor: hata ? Colors.red.shade700 : null,
        duration: const Duration(seconds: 3),
      ));
  }

  /// Kaynaktaki miktar (girişte sınır yok).
  int? _mevcut(Map<String, Map<String, int>> stok, String urunId) =>
      _islem.kaynakli
          ? (_kaynakId == null ? 0 : (stok[urunId]?[_kaynakId] ?? 0))
          : null;

  void _ekle(Urun u, {int adet = 1}) {
    final stok = ref.read(malzemeStoklariProvider).valueOrNull ?? const {};
    final mevcut = _mevcut(stok, u.id);
    final yeni = (_satirlar[u.id] ?? 0) + adet;
    if (mevcut != null && yeni > mevcut) {
      SesServisi.hata();
      _mesaj('${u.ad}: burada ${u.miktarMetni(mevcut)} var', hata: true);
      if (!_satirlar.containsKey(u.id)) setState(() => _satirlar[u.id] = 0);
      return;
    }
    SesServisi.basari();
    setState(() => _satirlar[u.id] = yeni);
  }

  Future<void> _malzemeSec(List<Urun> malzemeler,
      Map<String, Map<String, int>> stok) async {
    if (_islem.kaynakli && _kaynakId == null) {
      _mesaj('Önce nereden alınacağını seçin', hata: true);
      return;
    }
    final secenekler = [
      for (final u in malzemeler)
        if (!_islem.kaynakli || (_mevcut(stok, u.id) ?? 0) > 0) u
    ];
    if (secenekler.isEmpty) {
      _mesaj(
          malzemeler.isEmpty
              ? 'Tanımlı malzeme yok. Ürünler sekmesinde takip türü '
                  '"Miktar" olan ürün ekleyin.'
              : 'Burada malzeme yok',
          hata: true);
      return;
    }
    final secilen = await showDialog<Urun>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Malzeme seç'),
        children: [
          for (final u in secenekler)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, u),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cable_outlined),
                title: Text(u.ad),
                subtitle: Text([
                  if (u.kategori != null) u.kategori!,
                  if (_islem.kaynakli)
                    'Burada: ${u.miktarMetni(_mevcut(stok, u.id) ?? 0)}'
                  else
                    'Birim: ${u.birim}',
                ].join(' · ')),
              ),
            ),
        ],
      ),
    );
    if (secilen == null || !mounted) return;
    if (_satirlar.containsKey(secilen.id)) {
      _ekle(secilen);
    } else {
      setState(() => _satirlar[secilen.id] = 0);
      _ekle(secilen);
    }
  }

  /// Stok kodu (ya da henüz stok kodu verilmemiş malzemenin fabrika
  /// barkodu): tanımlı malzemeyse eklenir. 1.30.3: tanımsız fabrika barkodu
  /// artık malzemeye yazılmaz (malzemenin tek kimliği stok kodu).
  Future<void> _barkodIsle(String ham, List<Urun> malzemeler) async {
    final kod = ham.trim();
    if (kod.isEmpty) return;
    _barkodCtrl.clear();
    final db = ref.read(appDatabaseProvider);
    final urun = await db.barkodIleUrunBul(kod);
    if (!mounted) return;
    if (urun != null && !urun.deleted) {
      if (!urun.miktarli) {
        SesServisi.hata();
        _mesaj('${urun.ad} seri numarasıyla takip ediliyor; bu ekranda '
            'kullanılamaz', hata: true);
        return;
      }
      // Barkod bir kutu / top: içeriği kadar eklenir (montajda 1, düzeltilir).
      _ekle(urun,
          adet: _islem == MalzemeIslemi.kullanim ? 1 : urun.okutmaMiktari);
      return;
    }
    SesServisi.hata();
    _mesaj(
        kurumBarkoduMu(kod)
            ? 'Stok kodu $kod hiçbir malzemeye tanımlı değil'
            : 'Fabrika barkodu ($kod): kutudaki stok kodu etiketini okutun '
                'ya da "Malzeme seç" ile seçin',
        hata: true);
  }

  Future<void> _kameraIleOkut(List<Urun> malzemeler) async {
    final kod = await Navigator.of(context).push<String>(
        MaterialPageRoute(
            builder: (_) => const BarkodOkuyucuSayfasi(urunBarkodu: true)));
    if (kod != null && mounted) await _barkodIsle(kod, malzemeler);
  }

  Future<void> _miktarYaz(Urun u, int? mevcut) async {
    final ctrl = TextEditingController(text: '${_satirlar[u.id] ?? 0}');
    final yeni = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(u.ad),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Miktar (${u.birim})',
            helperText:
                mevcut == null ? null : 'Burada: ${u.miktarMetni(mevcut)}',
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
    if (yeni == null || yeni < 0) return;
    if (mevcut != null && yeni > mevcut) {
      _mesaj('${u.ad}: burada ${u.miktarMetni(mevcut)} var', hata: true);
      return;
    }
    setState(() => _satirlar[u.id] = yeni);
  }

  Future<void> _kaydet() async {
    final miktarlar = {
      for (final e in _satirlar.entries)
        if (e.value > 0) e.key: e.value
    };
    if (miktarlar.isEmpty) {
      _mesaj('Miktar girin', hata: true);
      return;
    }
    setState(() => _kaydediliyor = true);
    try {
      final (devam, k) = await _kaydetKonumu();
      if (!devam || !mounted) return;
      if (_islem == MalzemeIslemi.kullanim &&
          _yerCtrl.text.trim().isEmpty &&
          k == null) {
        _mesaj('Konum yok: nerede kullanıldığını yazın', hata: true);
        return;
      }
      final db = ref.read(appDatabaseProvider);
      await db.malzemeHareketiKaydet(
            islem: _islem,
            kaynakDepoId: _islem.kaynakli ? _kaynakId : null,
            hedefDepoId: _islem.hedefli ? _hedefId : null,
            miktarlar: miktarlar,
            kullaniciId:
                ref.read(aktifKullaniciIdProvider) ?? 'demo-kullanici',
            not_: _notCtrl.text,
            kullanimYeri: _yerCtrl.text,
            enlem: k?.enlem,
            boylam: k?.boylam,
            konumHassasiyet: k?.hassasiyet,
            il: k == null ? null : _il,
            ilce: k == null ? null : _ilce,
            mahalle: k == null ? null : _mahalle,
          );
      // İnternet varsa eksik bölge (il / ilçe / mahalle) hemen tamamlanır.
      if (k != null) unawaited(AdresTamamlayici.calistir(db));
      SesServisi.basari();
      await taslakTamamlandi();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final konumMetni = _konum == null
          ? ''
          : (k == null
              ? ' · konumsuz'
              : ' · konum ±${(k.hassasiyet ?? 0).round()} m');
      // 1.30.3: girişten sonra "Kaç kutu geldi? Etiket basılsın mı?"
      if (_islem == MalzemeIslemi.giris) {
        final urunler =
            ref.read(urunlerStreamProvider).valueOrNull ?? <Urun>[];
        final harita = {for (final u in urunler) u.id: u};
        await girisSonrasiEtiketSor(context, [
          for (final e in miktarlar.entries)
            if (harita[e.key] != null) (harita[e.key]!, e.value),
        ]);
        if (!mounted) return;
      }
      messenger.showSnackBar(SnackBar(
          content: Text('${_islem.baslik}: ${miktarlar.length} kalem '
              'kaydedildi$konumMetni')));
      Navigator.pop(context);
    } catch (e) {
      SesServisi.hata();
      _mesaj(e is StateError ? e.message : 'Kaydedilemedi: $e', hata: true);
    } finally {
      if (mounted) {
        setState(() {
          _kaydediliyor = false;
          _bekleSn = null;
        });
      }
    }
  }

  // ---------------------------------------------------------------

  List<Depo> _kaynaklar(List<Depo> tumu) => switch (_islem) {
        MalzemeIslemi.iade => [
            ...tumu.where((d) => d.arac),
            ...tumu.where((d) => !d.arac),
          ],
        MalzemeIslemi.kullanim => [
            ...tumu.where((d) => d.arac),
            ...tumu.where((d) => !d.arac),
          ],
        _ => tumu,
      };

  List<Depo> _hedefler(List<Depo> tumu) {
    final l = tumu.where((d) => d.id != _kaynakId).toList();
    return switch (_islem) {
      MalzemeIslemi.yukle => [
          ...l.where((d) => d.arac),
          ...l.where((d) => !d.arac),
        ],
      MalzemeIslemi.iade => l.where((d) => !d.arac).toList(),
      _ => l,
    };
  }

  @override
  Widget build(BuildContext context) {
    final depolar = ref.watch(depolarStreamProvider).valueOrNull ?? <Depo>[];
    final urunler = ref.watch(urunlerStreamProvider).valueOrNull ?? <Urun>[];
    final stok = ref.watch(malzemeStoklariProvider).valueOrNull ??
        const <String, Map<String, int>>{};
    final malzemeler = urunler.where((u) => u.miktarli).toList();
    final urunMap = {for (final u in urunler) u.id: u};
    final kaynaklar = _kaynaklar(depolar);
    final hedefler = _hedefler(depolar);
    final kalem = _satirlar.values.where((m) => m > 0).length;

    return yarimIsKapsayici(
      child: Scaffold(
        appBar: AppBar(title: Text(_islem.baslik)),
        body: Column(
          children: [
            if (_konum != null)
              KonumSeridi(
                izleyici: _konum!,
                kaydet: _konumKaydet,
                onChanged: (v) => setState(() => _konumKaydet = v),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                children: [
                  if (_islem.kaynakli)
                    DropdownButtonFormField<String>(
                      value: kaynaklar.any((d) => d.id == _kaynakId)
                          ? _kaynakId
                          : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                          labelText: _islem == MalzemeIslemi.kullanim
                              ? 'Hangi araçtan / depodan düşülecek?'
                              : 'Nereden?'),
                      items: depoDropdownOgeleri(kaynaklar),
                      onChanged: (v) => setState(() {
                        _kaynakId = v;
                        if (_hedefId == v) _hedefId = null;
                      }),
                    ),
                  if (_islem.hedefli)
                    DropdownButtonFormField<String>(
                      value: hedefler.any((d) => d.id == _hedefId)
                          ? _hedefId
                          : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                          labelText: switch (_islem) {
                        MalzemeIslemi.giris => 'Hangi depo / araca girilecek?',
                        MalzemeIslemi.yukle => 'Hangi araca yüklenecek?',
                        MalzemeIslemi.iade => 'Hangi depoya iade edilecek?',
                        _ => 'Nereye?',
                      }),
                      items: depoDropdownOgeleri(hedefler),
                      onChanged: (v) => setState(() => _hedefId = v),
                    ),
                  if (_islem == MalzemeIslemi.kullanim)
                    TextField(
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: metinBuyuk,
                      controller: _yerCtrl,
                      decoration: InputDecoration(
                        labelText: 'Nerede kullanıldı?',
                        hintText: 'ÖRN: ZABITA MÜDÜRLÜĞÜ, PARK CAD. 12',
                        helperText: _yerKaynagi ??
                            (_konumKaydet
                                ? 'Konum kaydedilirse boş bırakılabilir'
                                : null),
                      ),
                      onChanged: (t) {
                        if (_yerKaynagi != null &&
                            t.trim() != _yerOtomatik) {
                          setState(() => _yerKaynagi = null);
                        }
                      },
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: bilgisayarTarayicisi
                  ? Row(
                      children: [
                        Expanded(
                          child: TextField(
                            textCapitalization: TextCapitalization.characters,
                            inputFormatters: kodBuyuk,
                            controller: _barkodCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Stok kodu (okuyucuyla okutun)',
                              prefixIcon: Icon(Icons.qr_code_scanner),
                            ),
                            onSubmitted: (v) => _barkodIsle(v, malzemeler),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          onPressed: () => _malzemeSec(malzemeler, stok),
                          icon: const Icon(Icons.playlist_add),
                          label: const Text('Malzeme seç'),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () => _kameraIleOkut(malzemeler),
                            icon: const Icon(Icons.qr_code_scanner),
                            label: const Text('Barkod okut'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () => _malzemeSec(malzemeler, stok),
                            icon: const Icon(Icons.playlist_add),
                            label: const Text('Malzeme seç'),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _satirlar.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          malzemeler.isEmpty
                              ? 'Henüz miktarla takip edilen malzeme yok.\n\n'
                                  'Ürünler sekmesinde yeni ürün eklerken takip '
                                  'türünü "Miktar" seçin (kablo, adaptör…).'
                              : 'Stok kodu etiketini okutun ya da '
                                  '"Malzeme seç" ile listeden seçin. Miktarı '
                                  '+/- ile ya da sayıya dokunup yazarak girin.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final e in _satirlar.entries)
                          if (urunMap[e.key] != null)
                            _MalzemeSatiri(
                              urun: urunMap[e.key]!,
                              miktar: e.value,
                              mevcut: _mevcut(stok, e.key),
                              azalt: e.value > 0
                                  ? () => setState(
                                      () => _satirlar[e.key] = e.value - 1)
                                  : null,
                              artir: () => _ekle(urunMap[e.key]!),
                              yaz: () => _miktarYaz(
                                  urunMap[e.key]!, _mevcut(stok, e.key)),
                              sil: () =>
                                  setState(() => _satirlar.remove(e.key)),
                            ),
                      ],
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: metinBuyuk,
                      controller: _notCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Not (isteğe bağlı)'),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        // 1.30.3: miktar girilmeden Kaydet kapalı.
                        onPressed: _kaydediliyor || kalem == 0 ? null : _kaydet,
                        icon: Icon(_bekleSn != null
                            ? Icons.gps_not_fixed
                            : Icons.save),
                        label: Text(_bekleSn != null
                            ? 'Konum bekleniyor… ($_bekleSn sn)'
                            : _kaydediliyor
                                ? 'Kaydediliyor...'
                                : 'Kaydet ($kalem kalem)'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MalzemeSatiri extends StatelessWidget {
  const _MalzemeSatiri({
    required this.urun,
    required this.miktar,
    required this.mevcut,
    required this.azalt,
    required this.artir,
    required this.yaz,
    required this.sil,
  });

  final Urun urun;
  final int miktar;
  final int? mevcut;
  final VoidCallback? azalt;
  final VoidCallback artir;
  final VoidCallback yaz;
  final VoidCallback sil;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      title: Text(urun.ad),
      subtitle: Text(mevcut == null
          ? urun.birim
          : 'Burada: ${urun.miktarMetni(mevcut!)}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: azalt,
          ),
          InkWell(
            onTap: yaz,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              constraints: const BoxConstraints(minWidth: 44),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              alignment: Alignment.center,
              child: Text('$miktar',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: artir,
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Kaldır',
            onPressed: sil,
          ),
        ],
      ),
    );
  }
}
