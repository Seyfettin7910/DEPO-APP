import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../database/models.dart';
import '../../providers/app_providers.dart';
import '../../services/ses_servisi.dart';
import '../../widgets/depo_secici.dart';
import '../../widgets/kod_yardimci.dart';
import '../../widgets/hedefli_tarayici.dart';
import '../../widgets/alim_bilgisi_alanlari.dart';

/// Seri numaralarıyla depoya giriş: model ve depo seçilir, seri numaraları
/// kamerayla tek tek okutulur, hepsi tek seferde kaydedilir. Hatalı girişi
/// önlemek için telefonda elle yazma yoktur (bilgisayar tarayıcısında USB
/// barkod okuyucu için yazma alanı vardır).
class TopluGirisScreen extends ConsumerStatefulWidget {
  final String? onceSeciliUrunId;
  final String? onceSeciliDepoId;
  final List<String> onceSeriNolari;

  const TopluGirisScreen({
    super.key,
    this.onceSeciliUrunId,
    this.onceSeciliDepoId,
    this.onceSeriNolari = const [],
  });

  @override
  ConsumerState<TopluGirisScreen> createState() => _TopluGirisScreenState();
}

class _TopluGirisScreenState extends ConsumerState<TopluGirisScreen> {
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

  @override
  void initState() {
    super.initState();
    _onerileriYukle();
    _urunId = widget.onceSeciliUrunId;
    _depoId = widget.onceSeciliDepoId;
    _seriler.addAll(widget.onceSeriNolari.map(_norm));
  }

  @override
  void dispose() {
    _seriCtrl.dispose();
    _notCtrl.dispose();
    _kamera?.dispose();
    super.dispose();
  }

  String _norm(String s) => s.trim().toUpperCase();

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

  /// Listeye bir seri numarası ekler; geçersizse uyarı sesi verir.
  Future<void> _ekle(String ham) async {
    final seri = _norm(ham);
    if (seri.isEmpty) return;

    if (_urunId == null) {
      SesServisi.hata();
      _mesaj('Önce ürün (model) seçin', hata: true);
      return;
    }
    if (_seriler.contains(seri)) {
      SesServisi.hata();
      _mesaj('$seri zaten listede', hata: true);
      return;
    }

    final db = ref.read(appDatabaseProvider);
    final mevcut = await db.seriNoIleCihazBilgi(seri);
    if (!mounted) return;
    if (mevcut != null) {
      if (mevcut.cihaz.durum == CihazDurumu.depoda) {
        SesServisi.hata();
        _mesaj('$seri zaten kayıtlı: ${mevcut.depoAdi ?? '-'} deposunda',
            hata: true);
        return;
      }
      if (mevcut.cihaz.urunId != _urunId) {
        SesServisi.hata();
        _mesaj('$seri başka modele ait: ${mevcut.urunAdi}', hata: true);
        return;
      }
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
        _kamera = MobileScannerController();
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
      await ref.read(appDatabaseProvider).cihazlariGirisYap(
            urunId: _urunId!,
            depoId: _depoId!,
            seriNolar: List.of(_seriler),
            kullaniciId: ref.read(aktifKullaniciIdProvider) ?? 'demo-kullanici',
            not_: _notCtrl.text.trim().isEmpty ? null : _notCtrl.text.trim(),
            alim: _alim.bos ? null : _alim,
          );
      SesServisi.basari();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$adet cihaz depoya alındı')));
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

    return Scaffold(
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
                    if (_urunId != null && v != _urunId) _seriler.clear();
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
              height: 200,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Text('Eklenen: ${_seriler.length}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_seriler.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(_seriler.clear),
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
                        'seri listeye eklenir.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _seriler.length,
                    itemBuilder: (context, i) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.qr_code_2),
                      title: Text(_seriler[i]),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _seriler.removeAt(i)),
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
    );
  }
}
