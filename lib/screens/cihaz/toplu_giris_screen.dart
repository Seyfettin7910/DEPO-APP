import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../database/app_database.dart';
import '../../database/models.dart';
import '../../providers/app_providers.dart';
import '../../widgets/etiket_secimi.dart';
import '../etiket/etiket_ayarlari_screen.dart';
import '../../services/cihaz_tercihleri.dart';
import '../../services/ses_servisi.dart';
import '../../services/taslak_servisi.dart';
import '../../widgets/kod_yardimci.dart';
import '../../widgets/hedefli_tarayici.dart';
import '../../widgets/alim_bilgisi_alanlari.dart';
import '../../widgets/renkler.dart';
import '../../widgets/malzeme_kalemleri.dart';
import '../../widgets/buyuk_harf.dart';
import '../../services/bolge_adi.dart';
import '../urun/urun_form_dialog.dart';
import '../../widgets/malzeme_etiketi.dart';

/// Seri numaralarıyla depoya giriş: model ve depo seçilir, seri numaraları
/// kamerayla tek tek okutulur, hepsi tek seferde kaydedilir. Hatalı girişi
/// önlemek için telefonda elle yazma yoktur (bilgisayar tarayıcısında USB
/// barkod okuyucu için yazma alanı vardır). Koli karekodu okutulursa içindeki
/// bütün seri numaraları ayrı ayrı eklenir.
class TopluGirisScreen extends ConsumerStatefulWidget {
  final String? onceSeciliUrunId;
  final String? onceSeciliDepoId;
  final List<String> onceSeriNolari;

  const TopluGirisScreen({
    super.key,
    this.onceSeciliUrunId,
    this.onceSeciliDepoId,
    this.onceSeriNolari = const [],
    this.onceMalzemeler = const {},
    this.taslaktan = false,
  });

  /// Okut'tan gelen malzemeler (ürün id → miktar); aynı depoya girilir.
  final Map<String, int> onceMalzemeler;

  /// Yarım kalan girişe devam etmek için açıldı (soru sorulmaz).
  final bool taslaktan;

  @override
  ConsumerState<TopluGirisScreen> createState() => _TopluGirisScreenState();
}

class _TopluGirisScreenState extends ConsumerState<TopluGirisScreen>
    with YarimIsKorumasi<TopluGirisScreen> {
  final _seriCtrl = TextEditingController();
  final _notCtrl = TextEditingController();
  final _seriler = <String>[];

  /// Seri nosuz malzemeler (kablo…): ürün id → miktar.
  final _malzemeler = <String, int>{};

  /// Karışık modellerde seri noya özel model (yoksa üstteki model geçerli).
  final _seriModel = <String, String>{};

  String? _urunId;
  String? _depoId;
  bool _kameraAcik = false;
  bool _coklu = false;
  bool _kaydediliyor = false;
  MobileScannerController? _kamera;
  String? _sonKod;
  DateTime _sonZaman = DateTime.fromMillisecondsSinceEpoch(0);
  bool _mesgul = false;

  /// Bu girişteki tüm cihazlara uygulanacak alım / garanti bilgisi.
  AlimBilgisi _alim = AlimBilgisi();
  List<String> _firmalar = const [];
  List<String> _ihaleler = const [];

  /// Kurum etiketi: hangi kurum koduyla kod üretilecek, kuyruğa alınacak mı.
  EtiketTercihi _etiket = const EtiketTercihi();

  /// Seri numarası olmayan ürünler için üretilmiş kodlar (seri no yerine).
  final _seriNosuz = <String>{};

  @override
  void initState() {
    super.initState();
    _onerileriYukle();
    _etiketTercihiYukle();
    _urunId = widget.onceSeciliUrunId;
    _depoId = widget.onceSeciliDepoId;
    if (_depoId == null) _varsayilanDepoyuYukle();
    _malzemeler.addAll(widget.onceMalzemeler);
    for (final k in widget.onceSeriNolari) {
      for (final s in seriNolariAyir(k)) {
        if (!_seriler.contains(s)) _seriler.add(s);
      }
    }
    taslakKorumasiniBaslat(dinlenecekler: [_notCtrl]);
  }

  /// Ayarlar'daki "Varsayılan giriş deposu" seçili gelir.
  Future<void> _varsayilanDepoyuYukle() async {
    final id = await CihazTercihleri.girisDeposu();
    if (id != null && mounted && _depoId == null) {
      setState(() => _depoId = id);
    }
  }

  /// Taslaktan geri yüklenen etiket tercihi, kayıtlı tercihle ezilmesin.
  bool _etiketTaslaktan = false;

  static int? _ms(DateTime? t) => t?.millisecondsSinceEpoch;
  static DateTime? _tarih(Object? v) =>
      v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;

  @override
  String get taslakTuru => 'giris';

  @override
  bool get taslaktanAcildi => widget.taslaktan;

  @override
  Taslak? taslakOlustur() {
    if (_seriler.isEmpty && _malzemeler.isEmpty) return null;
    final urun = (ref.read(urunlerStreamProvider).valueOrNull ?? <Urun>[])
        .where((u) => u.id == _urunId)
        .firstOrNull;
    return Taslak(
      tur: taslakTuru,
      baslik: 'Depoya giriş${urun == null ? '' : ' · ${urun.ad}'}',
      ozet: '${_seriler.length} seri no'
          '${_malzemeler.isEmpty ? '' : ' · ${_malzemeler.length} malzeme'}',
      veri: {
        'urunId': _urunId,
        'depoId': _depoId,
        'seriler': List.of(_seriler),
        'seriNosuz': _seriNosuz.toList(),
        'seriModel': Map.of(_seriModel),
        'malzemeler': Map.of(_malzemeler),
        'not': _notCtrl.text,
        'alim': {
          'tarih': _ms(_alim.alimTarihi),
          'firma': _alim.firma,
          'ihale': _alim.ihale,
          'garanti': _ms(_alim.garantiBitis),
        },
        'kurumKoduId': _etiket.kurumKoduId,
        'kuyruga': _etiket.kuyruga,
      },
    );
  }

  @override
  Future<void> taslagiYukle(Taslak t) async {
    final v = t.veri;
    final a = (v['alim'] as Map?) ?? const {};
    setState(() {
      _urunId = v['urunId'] as String? ?? _urunId;
      _depoId = v['depoId'] as String? ?? _depoId;
      _alim = AlimBilgisi(
        alimTarihi: _tarih(a['tarih']),
        firma: a['firma'] as String? ?? '',
        ihale: a['ihale'] as String? ?? '',
        garantiBitis: _tarih(a['garanti']),
      );
      _etiketTaslaktan = true;
      _etiket = EtiketTercihi(
        kurumKoduId: v['kurumKoduId'] as String?,
        kuyruga: v['kuyruga'] as bool? ?? true,
      );
    });
    _notCtrl.text = trBuyuk(v['not'] as String? ?? '');
    final nosuz = {for (final s in (v['seriNosuz'] as List? ?? [])) '$s'};
    for (final e in ((v['malzemeler'] as Map?) ?? const {}).entries) {
      final m = (e.value as num?)?.toInt() ?? 0;
      if (m > 0) _malzemeler['${e.key}'] = m;
    }
    final modeller = {
      for (final e in ((v['seriModel'] as Map?) ?? const {}).entries)
        '${e.key}': '${e.value}'
    };
    // Liste yeniden denetlenir: bu arada başka biri girdiyse atlanır.
    final atlanan = <String>[];
    for (final s in [for (final x in (v['seriler'] as List? ?? [])) '$x']) {
      final engel = await _engel(s);
      if (!mounted) return;
      if (engel == null) {
        setState(() {
          _seriler.add(s);
          if (nosuz.contains(s)) _seriNosuz.add(s);
          if (modeller[s] != null) _seriModel[s] = modeller[s]!;
        });
      } else {
        atlanan.add(engel);
      }
    }
    if (atlanan.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${atlanan.length} seri no artık eklenemiyor, atlandı:\n'
            '${atlanan.take(4).join('\n')}'),
        backgroundColor: Colors.orange.shade800,
        duration: const Duration(seconds: 6),
      ));
    }
  }

  @override
  void dispose() {
    taslakKorumasiniBitir(dinlenecekler: [_notCtrl]);
    _seriCtrl.dispose();
    _notCtrl.dispose();
    _kamera?.dispose();
    super.dispose();
  }

  Future<void> _onerileriYukle() async {
    final db = ref.read(appDatabaseProvider);
    final f = await db.oncekiAlimDegerleri('firma');
    final i = await db.oncekiAlimDegerleri('ihale');
    if (mounted) {
      setState(() {
        _firmalar = f;
        _ihaleler = i;
      });
    }
  }

  Future<void> _etiketTercihiYukle() async {
    final kodlar =
        await ref.read(appDatabaseProvider).kurumKodlari(sadeceAktif: true);
    final t = await EtiketTercihi.yukle(kodlar);
    if (mounted && !_etiketTaslaktan) setState(() => _etiket = t);
  }

  Future<void> _etiketDuzenle(List<KurumKodu> kodlar) async {
    if (kodlar.isEmpty) {
      await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const EtiketAyarlariScreen()));
      return;
    }
    final yeni =
        await etiketTercihiSec(context, kodlar: kodlar, mevcut: _etiket);
    if (yeni == null) return;
    if (yeni.kurumKoduId == null && _seriNosuz.isNotEmpty) {
      _mesaj('Listede seri nosuz ürün var; kurum kodu gerekli', hata: true);
      return;
    }
    setState(() => _etiket = yeni);
    await yeni.kaydet();
  }

  /// Seri numarası olmayan ürünler (kablo, mobilya…): kurum kodu üretilir ve
  /// seri no yerine kullanılır.
  Future<void> _seriNosuzEkle() async {
    if (_urunId == null) {
      _mesaj('Önce ürün (model) seçin', hata: true);
      return;
    }
    final kurum = _etiket.kurumKoduId;
    if (kurum == null) {
      _mesaj('Önce "Kurum etiketi"nden kurum kodu seçin', hata: true);
      return;
    }
    final ctrl = TextEditingController(text: '1');
    final adet = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seri numarası olmayan ürün'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Her biri için kurum kodu üretilir ve seri numarası yerine '
                'kullanılır. Etiketi basılıp ürüne yapıştırılır.'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Adet (1-200)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(ctrl.text.trim()) ?? 0;
              if (n >= 1 && n <= 200) Navigator.pop(ctx, n);
            },
            child: const Text('Kod üret'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (adet == null) return;
    try {
      final kodlar =
          await ref.read(appDatabaseProvider).seriNosuzKodlarUret(kurum, adet);
      if (!mounted) return;
      SesServisi.basari();
      setState(() {
        _seriler.insertAll(0, kodlar);
        _seriNosuz.addAll(kodlar);
      });
    } catch (e) {
      _mesaj(e is StateError ? e.message : 'Kod üretilemedi: $e', hata: true);
    }
  }

  Future<void> _alimDuzenle() async {
    final yeni = await alimBilgisiPenceresi(
      context,
      mevcut: _alim,
      firmalar: _firmalar,
      ihaleler: _ihaleler,
      aciklama: 'Bu girişteki tüm cihazlara uygulanır. '
          'Sonradan cihaz kartından tek tek de değiştirilebilir.',
    );
    if (yeni != null) setState(() => _alim = yeni);
  }

  void _mesaj(String metin, {bool hata = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(metin),
        backgroundColor: hata ? Colors.red.shade700 : null,
        duration: const Duration(seconds: 2),
      ));
  }

  /// Bir seri numarasının listeye eklenip eklenemeyeceği; eklenemezse sebebi.
  Future<String?> _engel(String seri) async {
    if (_seriler.contains(seri)) return '$seri zaten listede';
    final mevcut =
        await ref.read(appDatabaseProvider).seriNoIleCihazBilgi(seri);
    if (mevcut != null) {
      if (mevcut.cihaz.durum == CihazDurumu.depoda) {
        return '$seri zaten kayıtlı: ${mevcut.depoAdi ?? '-'} deposunda';
      }
      if (mevcut.cihaz.urunId != _urunId) {
        return '$seri başka modele ait: ${mevcut.urunAdi}';
      }
    }
    return null;
  }

  /// Koli karekodundaki seri numaralarının hepsini birden ekler; eklenemeyenler
  /// (zaten kayıtlı, başka model, listede) atlanır ve özetle bildirilir.
  Future<void> _cokluEkle(List<String> seriler) async {
    if (_urunId == null) {
      SesServisi.hata();
      _mesaj('Önce ürün (model) seçin', hata: true);
      return;
    }
    final eklenecek = <String>[];
    final atlanan = <String>[];
    final db = ref.read(appDatabaseProvider);
    for (final ham in seriler) {
      final s = await db.seriyeCevir(ham);
      final engel = eklenecek.contains(s) ? '$s tekrar' : await _engel(s);
      if (engel == null) {
        eklenecek.add(s);
      } else {
        atlanan.add(engel);
      }
    }
    if (!mounted) return;
    if (eklenecek.isEmpty) {
      SesServisi.hata();
    } else {
      SesServisi.basari();
      setState(() => _seriler.insertAll(0, eklenecek.reversed));
    }
    final ozet = 'Koli: ${eklenecek.length} seri no eklendi'
        '${atlanan.isEmpty ? '' : ', ${atlanan.length} atlandı'}';
    if (atlanan.isEmpty) {
      _mesaj(ozet, hata: eklenecek.isEmpty);
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('$ozet\n${atlanan.take(4).join('\n')}'
            '${atlanan.length > 4 ? '\n…' : ''}'),
        backgroundColor: eklenecek.isEmpty ? Colors.red.shade700 : Colors.orange.shade800,
        duration: const Duration(seconds: 6),
      ));
  }

  /// Listeye bir seri numarası ekler; geçersizse uyarı sesi verir.
  Future<void> _ekle(String ham) async {
    final seriler = seriNolariAyir(ham);
    if (seriler.isEmpty) return;
    if (seriler.length > 1) {
      _seriCtrl.clear();
      await _cokluEkle(seriler);
      return;
    }
    if (_urunId == null) {
      SesServisi.hata();
      _mesaj('Önce ürün (model) seçin', hata: true);
      return;
    }
    // Kurum etiketi okutulduysa cihazın seri numarasına çevrilir.
    final seri =
        await ref.read(appDatabaseProvider).seriyeCevir(seriler.first);
    if (!mounted) return;
    final engel = await _engel(seri);
    if (!mounted) return;
    if (engel != null) {
      SesServisi.hata();
      _mesaj(engel, hata: true);
      return;
    }

    SesServisi.basari();
    setState(() {
      _seriler.insert(0, seri);
      _seriCtrl.clear();
    });
  }

  void _kameraDegistir() {
    if (_kameraAcik) {
      final eski = _kamera;
      setState(() {
        _kameraAcik = false;
        _kamera = null;
        _coklu = false;
      });
      // Widget ağaçtan çıktıktan sonra denetleyiciyi kapat.
      WidgetsBinding.instance.addPostFrameCallback((_) => eski?.dispose());
    } else {
      setState(() {
        _kamera = tarayiciOlustur();
        _kameraAcik = true;
      });
    }
  }

  Future<void> _okundu(BarcodeCapture capture) async {
    if (_mesgul) return;
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

  Future<void> _kaydet() async {
    if (_depoId == null) {
      _mesaj('Depo seçin', hata: true);
      return;
    }
    if (_seriler.isEmpty && _malzemeler.isEmpty) {
      _mesaj('Önce seri numarası ekleyin', hata: true);
      return;
    }
    if (_seriler.any((s) => _seriModel[s] == null) && _urunId == null) {
      _mesaj('Ürün (model) seçin', hata: true);
      return;
    }
    setState(() => _kaydediliyor = true);
    try {
      final adet = _seriler.length;
      final malzemeAdet = _malzemeler.length;
      final etiketli = _etiket.kurumKoduId != null;
      // Karışık modeller: her model kendi grubunda kaydedilir.
      final gruplar = <String, List<String>>{};
      for (final s in _seriler) {
        gruplar.putIfAbsent(_seriModel[s] ?? _urunId!, () => []).add(s);
      }
      for (final g in gruplar.entries) {
        await ref.read(appDatabaseProvider).cihazlariGirisYap(
              urunId: g.key,
              depoId: _depoId!,
              seriNolar: g.value,
              kullaniciId:
                  ref.read(aktifKullaniciIdProvider) ?? 'demo-kullanici',
              not_: _notCtrl.text.trim().isEmpty ? null : _notCtrl.text.trim(),
              alim: _alim.bos ? null : _alim,
              kurumKoduId: _etiket.kurumKoduId,
              etiketKuyruga: _etiket.kuyruga,
              seriNosuz: {
                for (final s in g.value)
                  if (_seriNosuz.contains(s)) s
              },
            );
        // Kaydedilen grup listeden çıkar: sonraki grupta hata olursa
        // tekrar kaydedilmeye çalışılmasın.
        if (mounted) {
          setState(() {
            _seriler.removeWhere(g.value.contains);
            for (final s in g.value) {
              _seriModel.remove(s);
              _seriNosuz.remove(s);
            }
          });
        }
      }
      final girenMalzemeler = Map.of(_malzemeler);
      if (_malzemeler.isNotEmpty) {
        await ref.read(appDatabaseProvider).malzemeHareketiKaydet(
              islem: MalzemeIslemi.giris,
              hedefDepoId: _depoId,
              miktarlar: Map.of(_malzemeler),
              kullaniciId:
                  ref.read(aktifKullaniciIdProvider) ?? 'demo-kullanici',
              not_: _notCtrl.text.trim().isEmpty ? null : _notCtrl.text.trim(),
            );
        if (mounted) setState(_malzemeler.clear);
      }
      SesServisi.basari();
      await taslakTamamlandi();
      if (!mounted) return;
      // 1.30.3: malzeme girdiyse "Kaç kutu geldi? Etiket basılsın mı?"
      if (girenMalzemeler.isNotEmpty) {
        final urunler =
            ref.read(urunlerStreamProvider).valueOrNull ?? <Urun>[];
        final harita = {for (final u in urunler) u.id: u};
        await girisSonrasiEtiketSor(context, [
          for (final e in girenMalzemeler.entries)
            if (harita[e.key] != null) (harita[e.key]!, e.value),
        ]);
        if (!mounted) return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${adet == 0 ? '' : '$adet cihaz'}'
              '${adet > 0 && malzemeAdet > 0 ? ' ve ' : ''}'
              '${malzemeAdet == 0 ? '' : '$malzemeAdet malzeme'} depoya alındı'
              '${!etiketli ? '' : _etiket.kuyruga ? ' · etiketler basım kuyruğuna alındı' : ' · kurum kodları üretildi'}')));
      Navigator.pop(context, true);
    } catch (e) {
      SesServisi.hata();
      _mesaj(e is StateError ? e.message : 'Kaydedilemedi: $e', hata: true);
    } finally {
      if (mounted) setState(() => _kaydediliyor = false);
    }
  }

  /// Depo seçenekleri açıkta, alt alta (yalnız depolar).
  Widget _depoSecimi(List<Depo> depolar) {
    if (depolar.isEmpty) return const SizedBox.shrink();
    final secili = depolar.any((d) => d.id == _depoId) ? _depoId : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Text('Hangi depoya?',
              style: Theme.of(context).textTheme.labelLarge),
        ),
        // Çok depo varsa ekran taşmasın: en fazla ~3 satır, kaydırılır.
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 132),
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [
        for (final d in depolar)
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
                secili == d.id
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: secili == d.id ? Renkler.okut : null),
            title: Text(d.ad,
                style: TextStyle(
                    fontWeight:
                        secili == d.id ? FontWeight.bold : FontWeight.normal)),
            trailing: const Icon(Icons.warehouse_outlined,
                color: Renkler.depo, size: 20),
            onTap: () => setState(() => _depoId = d.id),
          ),
            ],
          ),
        ),
      ],
    );
  }

  /// Listedeki bir seri noya ayrı model seçer (karışık koli).
  /// "+ Yeni": listede olmayan modeli tanımlar (benzer ad kontrolüyle) ve
  /// seçer.
  Future<void> _yeniModel() async {
    final id = await urunFormDialog(context, ref, sadeceModel: true);
    if (id != null && mounted) setState(() => _urunId = id);
  }

  Future<void> _seriModeliSec(String seri, List<Urun> urunler) async {
    final secim = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('$seri · model',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold)),
              ),
              ListTile(
                leading: const Icon(Icons.undo),
                title: const Text('Üstteki model (varsayılan)'),
                onTap: () => Navigator.pop(ctx, ''),
              ),
              for (final u in urunler)
                ListTile(
                  leading: Icon(
                      (_seriModel[seri] ?? _urunId) == u.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: Renkler.urun),
                  title: Text(u.ad),
                  subtitle: u.kategori == null ? null : Text(u.kategori!),
                  onTap: () => Navigator.pop(ctx, u.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (secim == null || !mounted) return;
    setState(() {
      if (secim.isEmpty || secim == _urunId) {
        _seriModel.remove(seri);
      } else {
        _seriModel[seri] = secim;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Seri numarasız malzemeler (kablo, adaptör…) bu ekranda değil,
    // "Malzeme girişi"nden girilir.
    final urunler = (ref.watch(urunlerStreamProvider).valueOrNull ?? <Urun>[])
        .where((u) => !u.miktarli)
        .toList();
    // Yeni cihaz önce depoya girer; araçlara "Araca Yükle" ile geçer.
    final depolar = (ref.watch(depolarStreamProvider).valueOrNull ?? <Depo>[])
        .where((d) => !d.arac)
        .toList();

    return yarimIsKapsayici(
        child: Scaffold(
      appBar: AppBar(
        title: const Text('Seri No ile Depoya Giriş'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: urunler.any((u) => u.id == _urunId)
                            ? _urunId
                            : null,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: 'Ürün / model'),
                        items: [
                          for (final u in urunler)
                            DropdownMenuItem(
                              value: u.id,
                              child: Text(
                                u.kategori == null
                                    ? u.ad
                                    : '${u.ad} (${u.kategori})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        // Model değişince liste silinmez: kendi modeli
                        // seçilmemiş seri nolar yeni modele geçer.
                        onChanged: (v) => setState(() => _urunId = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 1.30.1: listede olmayan model buradan tanımlanır;
                    // okutulan seriler yerinde kalır, yeni model seçili gelir.
                    FilledButton.tonalIcon(
                      onPressed: _yeniModel,
                      icon: const Icon(Icons.add),
                      label: const Text('Yeni'),
                    ),
                  ],
                ),
                _depoSecimi(depolar),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('Alım / garanti bilgileri'),
                  subtitle: Text(
                    _alim.bos
                        ? 'İsteğe bağlı: alım tarihi, firma, ihale, garanti'
                        : alimOzeti(_alim),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: _alimDuzenle,
                ),
                Builder(builder: (context) {
                  final kodlar = (ref.watch(kurumKodlariProvider).valueOrNull ??
                          const <KurumKodu>[])
                      .where((k) => k.aktif)
                      .toList();
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.qr_code_2),
                    title: const Text('Kurum etiketi'),
                    subtitle: Text(
                      kodlar.isEmpty
                          ? 'Kurum kodu tanımlı değil (ayarlamak için dokunun)'
                          : _etiket.ozet(kodlar),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => _etiketDuzenle(kodlar),
                  );
                }),
                if (urunler.isEmpty || depolar.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      urunler.isEmpty
                          ? 'Önce Ürünler sekmesinden bir ürün (model) ekleyin.'
                          : 'Önce Depolar sekmesinden bir depo ekleyin.',
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
          if (_kameraAcik && _kamera != null)
            SizedBox(
              height: (MediaQuery.sizeOf(context).height * 0.34)
                  .clamp(220.0, 340.0),
              child: Stack(
                children: [
                  HedefliTarayici(controller: _kamera!, onDetect: _okundu),
                  if (_coklu)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: double.infinity,
                        color: Colors.black87,
                        padding: const EdgeInsets.all(6),
                        child: const Text(
                          'Çerçevede birden çok kod var. Yaklaştırıp yalnızca seri no kodunu çerçeveye alın.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.amber, fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: bilgisayarTarayicisi
                // Bilgisayarda USB barkod okuyucu klavye gibi yazar.
                ? TextField(
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: kodBuyuk,
                    controller: _seriCtrl,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'Seri numarası (barkod okuyucuyla okutun)',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.add_circle, color: Renkler.okut),
                        tooltip: 'Listeye ekle',
                        onPressed: () => _ekle(_seriCtrl.text),
                      ),
                    ),
                    onSubmitted: _ekle,
                  )
                : SizedBox(
                    width: double.infinity,
                    child: _kameraAcik
                        ? OutlinedButton.icon(
                            onPressed: _kameraDegistir,
                            style: OutlinedButton.styleFrom(
                                foregroundColor: Renkler.cikis),
                            icon: const Icon(Icons.no_photography_outlined),
                            label: const Text('Okutma bitti, kamerayı kapat'),
                          )
                        : FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                                backgroundColor: Renkler.okutZemin,
                                foregroundColor: Renkler.okut),
                            onPressed: _kameraDegistir,
                            icon: const Icon(Icons.qr_code_scanner),
                            label: Text(_seriler.isEmpty
                                ? 'Seri no okut'
                                : '${_seriler.length + 1}. seri noyu okut'),
                          ),
                  ),
          ),
          if (_etiket.kurumKoduId != null)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  onPressed: _seriNosuzEkle,
                  icon: const Icon(Icons.qr_code, size: 18),
                  label: const Text('Seri no yok: kurum kodu üret'),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Text('Eklenen: ${_seriler.length}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_seriler.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() {
                      _seriler.clear();
                      _seriNosuz.clear();
                    }),
                    child: const Text('Listeyi temizle'),
                  ),
              ],
            ),
          ),
          if (_malzemeler.isNotEmpty)
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.2),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: MalzemeKalemleri(
                  baslik: 'MALZEMELER (aynı depoya girilir)',
                  miktarlar: _malzemeler,
                  urunler: {
                    for (final u
                        in ref.watch(urunlerStreamProvider).valueOrNull ??
                            <Urun>[])
                      u.id: u
                  },
                  onDegisti: (id, n) => setState(() {
                    if (n <= 0) {
                      _malzemeler.remove(id);
                    } else {
                      _malzemeler[id] = n;
                    }
                  }),
                ),
              ),
            ),
          Expanded(
            child: _seriler.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        '"Seri no okut" ile kamerayı açıp seri numaralarını '
                        'tek tek okutun. Kamera açık kaldıkça okuttuğunuz her '
                        'seri listeye eklenir. Koli karekodu okutursanız '
                        'kolideki bütün seri numaraları birden eklenir.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _seriler.length,
                    itemBuilder: (context, i) {
                      final s = _seriler[i];
                      final ozel = _seriModel[s];
                      final model = urunler
                          .where((u) => u.id == (ozel ?? _urunId))
                          .firstOrNull;
                      return ListTile(
                        dense: true,
                        leading: Icon(_seriNosuz.contains(s)
                            ? Icons.qr_code
                            : Icons.qr_code_2),
                        title: Text(s),
                        subtitle: Text(
                          [
                            if (_seriNosuz.contains(s))
                              'Seri nosuz ürün · kurum kodu',
                            model == null
                                ? 'Model seçilmedi'
                                : '${model.ad}${ozel == null ? '' : ' (bu seri no için)'}',
                          ].join(' · '),
                          style: TextStyle(
                              color: ozel != null ? Renkler.urun : null),
                        ),
                        // Karışık koli: bu seri noya başka model seçilir.
                        onTap: () => _seriModeliSec(s, urunler),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _seriNosuz.remove(_seriler.removeAt(i));
                            _seriModel.remove(s);
                          }),
                        ),
                      );
                    },
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
                      onPressed: _kaydediliyor ? null : _kaydet,
                      icon: const Icon(Icons.save),
                      label: Text(_kaydediliyor
                          ? 'Kaydediliyor...'
                          : 'Depoya al (${_seriler.length + _malzemeler.length})'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ));
  }
}
