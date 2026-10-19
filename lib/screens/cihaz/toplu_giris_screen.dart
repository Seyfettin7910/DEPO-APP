import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../database/app_database.dart';
import '../../database/models.dart';
import '../../providers/app_providers.dart';
import '../../widgets/etiket_secimi.dart';
import '../etiket/etiket_ayarlari_screen.dart';
import '../../services/ses_servisi.dart';
import '../../services/taslak_servisi.dart';
import '../../widgets/depo_secici.dart';
import '../../widgets/kod_yardimci.dart';
import '../../widgets/hedefli_tarayici.dart';
import '../../widgets/alim_bilgisi_alanlari.dart';

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
    this.taslaktan = false,
  });

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
    for (final k in widget.onceSeriNolari) {
      for (final s in seriNolariAyir(k)) {
        if (!_seriler.contains(s)) _seriler.add(s);
      }
    }
    taslakKorumasiniBaslat(dinlenecekler: [_notCtrl]);
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
    if (_seriler.isEmpty) return null;
    final urun = (ref.read(urunlerStreamProvider).value ?? <Urun>[])
        .where((u) => u.id == _urunId)
        .firstOrNull;
    return Taslak(
      tur: taslakTuru,
      baslik: 'Depoya giriş${urun == null ? '' : ' · ${urun.ad}'}',
      ozet: '${_seriler.length} seri no',
      veri: {
        'urunId': _urunId,
        'depoId': _depoId,
        'seriler': List.of(_seriler),
        'seriNosuz': _seriNosuz.toList(),
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
    _notCtrl.text = v['not'] as String? ?? '';
    final nosuz = {for (final s in (v['seriNosuz'] as List? ?? [])) '$s'};
    // Liste yeniden denetlenir: bu arada başka biri girdiyse atlanır.
    final atlanan = <String>[];
    for (final s in [for (final x in (v['seriler'] as List? ?? [])) '$x']) {
      final engel = await _engel(s);
      if (!mounted) return;
      if (engel == null) {
        setState(() {
          _seriler.add(s);
          if (nosuz.contains(s)) _seriNosuz.add(s);
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
    if (_urunId == null || _depoId == null) {
      _mesaj('Ürün ve depo seçin', hata: true);
      return;
    }
    if (_seriler.isEmpty) {
      _mesaj('Önce seri numarası ekleyin', hata: true);
      return;
    }
    setState(() => _kaydediliyor = true);
    try {
      final adet = _seriler.length;
      final etiketli = _etiket.kurumKoduId != null;
      await ref.read(appDatabaseProvider).cihazlariGirisYap(
            urunId: _urunId!,
            depoId: _depoId!,
            seriNolar: List.of(_seriler),
            kullaniciId: ref.read(aktifKullaniciIdProvider) ?? 'demo-kullanici',
            not_: _notCtrl.text.trim().isEmpty ? null : _notCtrl.text.trim(),
            alim: _alim.bos ? null : _alim,
            kurumKoduId: _etiket.kurumKoduId,
            etiketKuyruga: _etiket.kuyruga,
            seriNosuz: Set.of(_seriNosuz),
          );
      SesServisi.basari();
      await taslakTamamlandi();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$adet cihaz depoya alındı'
              '${!etiketli ? '' : _etiket.kuyruga ? ' · etiketler basım kuyruğuna alındı' : ' · kurum kodları üretildi'}')));
      Navigator.pop(context);
    } catch (e) {
      SesServisi.hata();
      _mesaj(e is StateError ? e.message : 'Kaydedilemedi: $e', hata: true);
    } finally {
      if (mounted) setState(() => _kaydediliyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final urunler = ref.watch(urunlerStreamProvider).value ?? <Urun>[];
    final depolar = ref.watch(depolarStreamProvider).value ?? <Depo>[];

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
                DropdownButtonFormField<String>(
                  value: urunler.any((u) => u.id == _urunId) ? _urunId : null,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Ürün / model'),
                  items: [
                    for (final u in urunler)
                      DropdownMenuItem(
                        value: u.id,
                        child: Text(
                          u.kategori == null ? u.ad : '${u.ad} (${u.kategori})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    if (_urunId != null && v != _urunId) {
                      _seriler.clear();
                      _seriNosuz.clear();
                    }
                    _urunId = v;
                  }),
                ),
                DropdownButtonFormField<String>(
                  value: depolar.any((d) => d.id == _depoId) ? _depoId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Depo / araç'),
                  items: depoDropdownOgeleri(depolar),
                  onChanged: (v) => setState(() => _depoId = v),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('Alım / garanti bilgileri'),
                  subtitle: Text(
                    _alim.bos
                        ? 'Opsiyonel: alım tarihi, firma, ihale, garanti'
                        : alimOzeti(_alim),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: _alimDuzenle,
                ),
                Builder(builder: (context) {
                  final kodlar = (ref.watch(kurumKodlariProvider).value ??
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
                    controller: _seriCtrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'Seri numarası (barkod okuyucuyla okutun)',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.add_circle),
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
                            icon: const Icon(Icons.videocam_off),
                            label: const Text('Okutma bitti, kamerayı kapat'),
                          )
                        : FilledButton.tonalIcon(
                            onPressed: _kameraDegistir,
                            icon: const Icon(Icons.add_circle),
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
                    itemBuilder: (context, i) => ListTile(
                      dense: true,
                      leading: Icon(_seriNosuz.contains(_seriler[i])
                          ? Icons.qr_code
                          : Icons.qr_code_2),
                      title: Text(_seriler[i]),
                      subtitle: _seriNosuz.contains(_seriler[i])
                          ? const Text('Seri nosuz ürün · kurum kodu')
                          : null,
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(
                            () => _seriNosuz.remove(_seriler.removeAt(i))),
                      ),
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _notCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Not (opsiyonel)'),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _kaydediliyor ? null : _kaydet,
                      icon: const Icon(Icons.save),
                      label: Text(_kaydediliyor
                          ? 'Kaydediliyor...'
                          : 'Depoya al (${_seriler.length})'),
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
