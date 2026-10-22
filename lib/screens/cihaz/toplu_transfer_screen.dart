import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../database/app_database.dart';
import '../../database/models.dart';
import '../../providers/app_providers.dart';
import '../../services/ses_servisi.dart';
import '../../services/taslak_servisi.dart';
import '../../widgets/depo_secici.dart';
import '../../widgets/kod_yardimci.dart';
import 'cihaz_detay_screen.dart';
import '../../widgets/hedefli_tarayici.dart';
import '../../widgets/iade_sebebi.dart';
import '../../widgets/renkler.dart';
import '../../widgets/malzeme_kalemleri.dart';
import '../../widgets/buyuk_harf.dart';
import '../../services/bolge_adi.dart';

/// Birden çok cihazı seri numarasıyla okutup tek seferde bir depoya veya
/// araca taşır. [tip] transfer, Araca Yükle ya da iade olabilir;
/// ikisi de aynı şekilde çalışır, yalnızca kayıt türü farklıdır.
class TopluTransferScreen extends ConsumerStatefulWidget {
  final HareketTipi tip;
  final String? onceHedefDepoId;

  /// Önceden okutulmuş seri numaraları (ör. koli karekodundan). Hedef seçilince
  /// listeye eklenir.
  final List<String> onceSeriNolari;

  const TopluTransferScreen({
    super.key,
    this.tip = HareketTipi.transfer,
    this.onceHedefDepoId,
    this.onceSeriNolari = const [],
    this.onceMalzemeler = const {},
    this.taslaktan = false,
  });

  /// Okut'tan gelen malzemeler (ürün id → miktar).
  final Map<String, int> onceMalzemeler;

  /// Yarım kalan listeye devam etmek için açıldı (soru sorulmaz).
  final bool taslaktan;

  @override
  ConsumerState<TopluTransferScreen> createState() =>
      _TopluTransferScreenState();
}

class _TopluTransferScreenState extends ConsumerState<TopluTransferScreen>
    with YarimIsKorumasi<TopluTransferScreen> {
  final _seriCtrl = TextEditingController();
  final _notCtrl = TextEditingController();
  final _liste = <CihazBilgi>[];
  String? _sebep; // toplu iadede isteğe bağlı geri alma sebebi
  String? _arizaKarari; // iadede "Arıza" seçildiyse: tamir | degisim

  /// Transferde (araçtan depoya): "Arızalı" işaretlenirse arıza iadesi olur;
  /// sebep (açıklama) ve karar (tamir / değişim) ikisi de zorunludur.
  bool _arizali = false;
  final _arizaCtrl = TextEditingController();

  String? _hedefId;
  bool _kameraAcik = false;
  bool _coklu = false;
  bool _kaydediliyor = false;
  bool _mesgul = false;
  MobileScannerController? _kamera;
  String? _sonKod;
  DateTime _sonZaman = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _kullanim => widget.tip == HareketTipi.kullanim;

  /// Düz transferde hedef bir depoysa ve listede araçtan gelen cihaz varsa
  /// "Arızalı" seçeneği gösterilir.
  bool _arizaSecenegi(List<Depo> depolar) =>
      widget.tip == HareketTipi.transfer &&
      _hedefId != null &&
      depolar.any((d) => d.id == _hedefId && !d.arac) &&
      _liste.any((b) => b.depoArac);
  bool get _iade => widget.tip == HareketTipi.iade;

  /// Hedef seçilmeden gelen seri numaraları (hedef seçilince eklenir).
  final _bekleyen = <String>[];

  /// Malzemeler (kablo…): ürün id → miktar; [_malzemeKaynakId]'den düşer.
  final _malzemeler = <String, int>{};
  String? _malzemeKaynakId;

  @override
  void initState() {
    super.initState();
    _hedefId = widget.onceHedefDepoId;
    _malzemeler.addAll(widget.onceMalzemeler);
    for (final k in widget.onceSeriNolari) {
      for (final s in seriNolariAyir(k)) {
        if (!_bekleyen.contains(s)) _bekleyen.add(s);
      }
    }
    if (_hedefId != null && _bekleyen.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bekleyenleriEkle());
    }
    taslakKorumasiniBaslat(dinlenecekler: [_notCtrl, _arizaCtrl]);
  }

  String get _baslik => _kullanim
      ? 'Toplu Araca Yükle'
      : (_iade ? 'Toplu İade' : 'Toplu Transfer');

  @override
  String get taslakTuru => _kullanim
      ? 'toplu_kullanim'
      : (_iade ? 'toplu_iade' : 'toplu_transfer');

  @override
  bool get taslaktanAcildi => widget.taslaktan;

  @override
  Taslak? taslakOlustur() {
    if (_liste.isEmpty && _bekleyen.isEmpty && _malzemeler.isEmpty) {
      return null;
    }
    final hedef = (ref.read(depolarStreamProvider).valueOrNull ?? <Depo>[])
        .where((d) => d.id == _hedefId)
        .firstOrNull;
    return Taslak(
      tur: taslakTuru,
      baslik: '$_baslik${hedef == null ? '' : ' · ${hedef.ad}'}',
      ozet: '${_liste.length + _bekleyen.length} cihaz',
      veri: {
        'hedefId': _hedefId,
        'seriler': [for (final b in _liste) b.cihaz.seriNo],
        'bekleyen': List.of(_bekleyen),
        'sebep': _sebep,
        'arizaKarari': _arizaKarari,
        'not': _notCtrl.text,
        'arizali': _arizali,
        'malzemeler': Map.of(_malzemeler),
        'malzemeKaynak': _malzemeKaynakId,
        'ariza': _arizaCtrl.text,
      },
    );
  }

  @override
  Future<void> taslagiYukle(Taslak t) async {
    final v = t.veri;
    final seriler = [for (final s in (v['seriler'] as List? ?? [])) '$s'];
    setState(() {
      _hedefId = v['hedefId'] as String? ?? _hedefId;
      _sebep = v['sebep'] as String?;
      _arizaKarari = v['arizaKarari'] as String?;
      _arizali = v['arizali'] as bool? ?? false;
      _malzemeKaynakId = v['malzemeKaynak'] as String?;
      for (final e in ((v['malzemeler'] as Map?) ?? const {}).entries) {
        final m = (e.value as num?)?.toInt() ?? 0;
        if (m > 0) _malzemeler['${e.key}'] = m;
      }
      for (final s in (v['bekleyen'] as List? ?? [])) {
        if (!_bekleyen.contains('$s')) _bekleyen.add('$s');
      }
    });
    _notCtrl.text = trBuyuk(v['not'] as String? ?? '');
    _arizaCtrl.text = trBuyuk(v['ariza'] as String? ?? '');
    if (_hedefId == null) return;
    // Liste yeniden denetlenir: bu arada başka yere giden cihaz atlanır.
    final eklenecek = <CihazBilgi>[];
    final atlanan = <String>[];
    for (final s in seriler) {
      if (eklenecek.any((b) => b.cihaz.seriNo == s)) continue;
      final (bilgi, hata) = await _kontrol(s);
      if (bilgi != null) {
        eklenecek.add(bilgi);
      } else {
        atlanan.add(hata!);
      }
    }
    if (!mounted) return;
    setState(() => _liste.addAll(eklenecek));
    if (_bekleyen.isNotEmpty) await _bekleyenleriEkle();
    if (atlanan.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${atlanan.length} cihaz artık eklenemiyor, atlandı:\n'
            '${atlanan.take(4).join('\n')}'),
        backgroundColor: Colors.orange.shade800,
        duration: const Duration(seconds: 6),
      ));
    }
  }

  Future<void> _bekleyenleriEkle() async {
    if (_bekleyen.isEmpty || _hedefId == null) return;
    final liste = List.of(_bekleyen);
    setState(_bekleyen.clear);
    await _cokluEkle(liste);
  }

  void _hedefSecildi(String? v) {
    setState(() => _hedefId = v);
    if (_bekleyen.isNotEmpty) _bekleyenleriEkle();
  }

  @override
  void dispose() {
    taslakKorumasiniBitir(dinlenecekler: [_notCtrl, _arizaCtrl]);
    _arizaCtrl.dispose();
    _seriCtrl.dispose();
    _notCtrl.dispose();
    _kamera?.dispose();
    super.dispose();
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

  /// Malzemelerin düşüleceği yer: seçilmişse o; değilse listedeki
  /// cihazların bulunduğu (hedef olmayan) ilk yer.
  String? _malzemeKaynagi() {
    if (_malzemeKaynakId != null) return _malzemeKaynakId;
    for (final b in _liste) {
      final d = b.cihaz.depoId;
      if (d != null && d != _hedefId) return d;
    }
    return null;
  }

  /// Seri no listeye eklenebilir mi? Eklenebilirse cihaz bilgisi, değilse
  /// sebebi döner.
  Future<(CihazBilgi?, String?)> _kontrol(String seri) async {
    if (_liste.any((b) => b.cihaz.seriNo == seri)) {
      return (null, '$seri zaten listede');
    }
    final bilgi = await ref.read(appDatabaseProvider).seriNoIleCihazBilgi(seri);
    if (bilgi == null) return (null, 'Kayıtlı cihaz yok: $seri');
    if (bilgi.cihaz.durum != CihazDurumu.depoda) {
      return (null, '$seri şu an depoda değil (${cihazKonumMetni(bilgi)})');
    }
    if (bilgi.cihaz.arizali) {
      return (
        null,
        '$seri ${bilgi.cihaz.servisDurumu!.kisa.toLowerCase()}: '
            'servis işlemi bitmeden taşınamaz'
      );
    }
    if (bilgi.cihaz.depoId == _hedefId) {
      return (null, '$seri zaten hedefte: ${bilgi.depoAdi ?? '-'}');
    }
    // Kurum etiketiyle okutulduysa aynı cihaz listede olabilir.
    if (_liste.any((b) => b.cihaz.id == bilgi.cihaz.id)) {
      return (null, '${bilgi.cihaz.seriNo} zaten listede');
    }
    // Kurum etiketi engeli (ayarlardan açıksa; iade hariç)
    if (!_iade) {
      final engel = await ref
          .read(appDatabaseProvider)
          .etiketEngeli(bilgi.cihaz.id);
      if (engel != null) return (null, engel);
    }
    return (bilgi, null);
  }

  /// Koli karekodundaki seri numaralarını birden ekler; eklenemeyenler atlanır.
  Future<void> _cokluEkle(List<String> seriler) async {
    if (_hedefId == null) {
      SesServisi.hata();
      _mesaj('Önce hedef depo / araç seçin', hata: true);
      return;
    }
    final eklenecek = <CihazBilgi>[];
    final atlanan = <String>[];
    for (final s in seriler) {
      if (eklenecek.any((b) => b.cihaz.seriNo == s)) continue;
      final (bilgi, hata) = await _kontrol(s);
      if (bilgi != null) {
        eklenecek.add(bilgi);
      } else {
        atlanan.add(hata!);
      }
    }
    if (!mounted) return;
    if (eklenecek.isEmpty) {
      SesServisi.hata();
    } else {
      SesServisi.basari();
      setState(() => _liste.insertAll(0, eklenecek.reversed));
    }
    final ozet = 'Koli: ${eklenecek.length} cihaz eklendi'
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
        backgroundColor:
            eklenecek.isEmpty ? Colors.red.shade700 : Colors.orange.shade800,
        duration: const Duration(seconds: 6),
      ));
  }

  Future<void> _ekle(String ham) async {
    final seriler = seriNolariAyir(ham);
    if (seriler.isEmpty) return;
    if (seriler.length > 1) {
      _seriCtrl.clear();
      await _cokluEkle(seriler);
      return;
    }
    final seri = seriler.first;

    if (_hedefId == null) {
      SesServisi.hata();
      _mesaj('Önce hedef depo / araç seçin', hata: true);
      return;
    }
    final (bilgi, hata) = await _kontrol(seri);
    if (!mounted) return;
    if (bilgi == null) {
      SesServisi.hata();
      _mesaj(hata!, hata: true);
      return;
    }

    SesServisi.basari();
    setState(() {
      _liste.insert(0, bilgi);
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
    if (_hedefId == null) {
      _mesaj('Hedef depo / araç seçin', hata: true);
      return;
    }
    if (_liste.isEmpty && _malzemeler.isEmpty) {
      _mesaj('Önce seri numarası ekleyin', hata: true);
      return;
    }
    final malzemeKaynak = _malzemeKaynagi();
    if (_malzemeler.isNotEmpty) {
      if (malzemeKaynak == null) {
        _mesaj('Malzemelerin nereden alınacağını seçin', hata: true);
        return;
      }
      if (malzemeKaynak == _hedefId) {
        _mesaj('Malzemelerin kaynağı ile hedef aynı olamaz', hata: true);
        return;
      }
    }
    final depolar = ref.read(depolarStreamProvider).valueOrNull ?? <Depo>[];
    final arizaIadesi = _arizali && _arizaSecenegi(depolar);
    if (arizaIadesi &&
        (_arizaCtrl.text.trim().isEmpty || _arizaKarari == null)) {
      _mesaj(
          'Arıza sebebini yazın ve kararı (tamir / değişim) seçin ya da '
          '"Arızalı" işaretini kaldırın',
          hata: true);
      return;
    }
    if (_iade) {
      final h = iadeSebebiHatasi(_sebep, _notCtrl.text,
          zorunlu: false, arizaKarari: _arizaKarari, arizaSor: true);
      if (h != null) {
        _mesaj(h, hata: true);
        return;
      }
      final hedefArac = (ref.read(depolarStreamProvider).valueOrNull ?? <Depo>[])
          .any((d) => d.id == _hedefId && d.arac);
      if (_sebep == 'Arıza' && hedefArac) {
        _mesaj('Arızalı cihazlar bir depoya iade edilmeli', hata: true);
        return;
      }
    }
    setState(() => _kaydediliyor = true);
    try {
      final adet = _liste.length;
      final not_ = _notCtrl.text.trim();
      final malzemeAdet = _malzemeler.length;
      if (_liste.isNotEmpty) {
      await ref.read(appDatabaseProvider).cihazlariTopluHareketKaydet(
            cihazIdleri: [for (final b in _liste) b.cihaz.id],
            tip: arizaIadesi ? HareketTipi.iade : widget.tip,
            kullaniciId: ref.read(aktifKullaniciIdProvider) ?? 'demo-kullanici',
            hedefDepoId: _hedefId,
            not_: arizaIadesi
                ? [_arizaCtrl.text.trim(), if (not_.isNotEmpty) not_].join(' · ')
                : (not_.isEmpty ? null : not_),
            sebep: arizaIadesi ? 'Arıza' : (_iade ? _sebep : null),
            arizaKarari: arizaIadesi
                ? _arizaKarari
                : (_iade && _sebep == 'Arıza' ? _arizaKarari : null),
          );
        if (mounted) setState(_liste.clear);
      }
      if (_malzemeler.isNotEmpty) {
        await ref.read(appDatabaseProvider).malzemeHareketiKaydet(
              islem: _kullanim
                  ? MalzemeIslemi.yukle
                  : (_iade ? MalzemeIslemi.iade : MalzemeIslemi.transfer),
              kaynakDepoId: malzemeKaynak,
              hedefDepoId: _hedefId,
              miktarlar: Map.of(_malzemeler),
              kullaniciId:
                  ref.read(aktifKullaniciIdProvider) ?? 'demo-kullanici',
              not_: not_.isEmpty ? null : not_,
            );
        if (mounted) setState(_malzemeler.clear);
      }
      SesServisi.basari();
      await taslakTamamlandi();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text([
        if (adet > 0)
          _kullanim
              ? '$adet cihaz araca yüklendi'
              : (_iade || arizaIadesi
                  ? '$adet cihaz ${arizaIadesi ? 'arızalı olarak ' : ''}iade edildi'
                  : '$adet cihaz transfer edildi'),
        if (malzemeAdet > 0) '$malzemeAdet malzeme taşındı',
      ].join(' · '))));
      Navigator.pop(context, true);
    } catch (e) {
      SesServisi.hata();
      _mesaj(e is StateError ? e.message : 'Kaydedilemedi: $e', hata: true);
    } finally {
      if (mounted) setState(() => _kaydediliyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tumu = ref.watch(depolarStreamProvider).valueOrNull ?? <Depo>[];
    final hedefler = [...tumu];
    if (_kullanim) {
      hedefler.sort((a, b) => (a.arac ? 0 : 1).compareTo(b.arac ? 0 : 1));
    }

    return yarimIsKapsayici(
        child: Scaffold(
      appBar: AppBar(
        title: Text(_baslik),
        actions: [
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: DropdownButtonFormField<String>(
              value: hedefler.any((d) => d.id == _hedefId) ? _hedefId : null,
              isExpanded: true,
              decoration: InputDecoration(
                  labelText: _kullanim
                      ? 'Hangi araca (veya depoya) yüklenecek?'
                      : (_iade
                          ? 'Hangi depoya iade edilecek?'
                          : 'Hedef depo / araç')),
              items: depoDropdownOgeleri(hedefler),
              onChanged: _hedefSecildi,
            ),
          ),
          if (_bekleyen.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                  'Koliden ${_bekleyen.length} seri no hazır. Hedef depo / '
                  'aracı seçince listeye eklenecek.'),
            ),
          if (_malzemeler.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: DropdownButtonFormField<String>(
                value: tumu.any((d) => d.id == _malzemeKaynagi())
                    ? _malzemeKaynagi()
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Malzemeler nereden alınacak?'),
                items: depoDropdownOgeleri(
                    [for (final d in tumu) if (d.id != _hedefId) d]),
                onChanged: (v) => setState(() => _malzemeKaynakId = v),
              ),
            ),
          if (_malzemeler.isNotEmpty)
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.18),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: MalzemeKalemleri(
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
            child: TextField(
              textCapitalization: TextCapitalization.characters,
              inputFormatters: kodBuyuk,
              controller: _seriCtrl,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Seri numarası (elle yaz veya okut)',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add_circle, color: Renkler.okut),
                  tooltip: 'Listeye ekle',
                  onPressed: () => _ekle(_seriCtrl.text),
                ),
              ),
              onSubmitted: _ekle,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Text('Eklenen: ${_liste.length}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_liste.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(_liste.clear),
                    child: const Text('Listeyi temizle'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _liste.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Önce hedefi seçin, sonra taşınacak cihazların\n'
                        'seri numaralarını okutun veya yazın.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _liste.length,
                    itemBuilder: (context, i) {
                      final b = _liste[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.qr_code_2),
                        title: Text(b.cihaz.seriNo),
                        subtitle: Text(
                            '${b.urunAdi} · ${b.depoAdi ?? '-'} içinde'
                            '${b.etiketDogrulanmadi ? ' · ⚠ etiket doğrulanmadı' : ''}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _liste.removeAt(i)),
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
                  if (_iade)
                    IadeSebebiSecici(
                      secili: _sebep,
                      zorunlu: false,
                      onSecildi: (v) => setState(() => _sebep = v),
                      arizaKarari: _arizaKarari,
                      onArizaKarari: (v) => setState(() => _arizaKarari = v),
                    ),
                  if (_arizaSecenegi(tumu)) ...[
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: _arizali,
                      onChanged: (v) => setState(() => _arizali = v ?? false),
                      secondary: Icon(Icons.build_outlined,
                          color: _arizali ? Renkler.cikis : null),
                      title: const Text('Arızalı (arıza iadesi)'),
                      subtitle: const Text(
                          'İşaretlenmezse normal transfer olarak kaydedilir'),
                    ),
                    if (_arizali) ...[
                      TextField(
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: metinBuyuk,
                        controller: _arizaCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Arıza sebebi',
                            hintText: 'Örn: Görüntü gelmiyor'),
                      ),
                      ArizaKarariSecici(
                        secili: _arizaKarari,
                        onSecildi: (v) => setState(() => _arizaKarari = v),
                      ),
                    ],
                  ],
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
                      icon: Icon(_kullanim
                          ? Icons.local_shipping_outlined
                          : (_iade
                              ? Icons.assignment_return_outlined
                              : Icons.swap_horiz)),
                      label: Text(_kaydediliyor
                          ? 'Kaydediliyor...'
                          : (_kullanim
                              ? 'Araca Yükle (${_liste.length + _malzemeler.length})'
                              : (_iade
                                  ? 'İade al (${_liste.length})'
                                  : 'Transfer et (${_liste.length + _malzemeler.length})'))),
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
