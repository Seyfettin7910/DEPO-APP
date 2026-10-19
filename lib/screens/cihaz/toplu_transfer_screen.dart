import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../database/app_database.dart';
import '../../database/models.dart';
import '../../providers/app_providers.dart';
import '../../services/ses_servisi.dart';
import '../../widgets/depo_secici.dart';
import '../../widgets/kod_yardimci.dart';
import 'cihaz_detay_screen.dart';
import '../../widgets/hedefli_tarayici.dart';
import '../../widgets/iade_sebebi.dart';

/// Birden çok cihazı seri numarasıyla okutup tek seferde bir depoya veya
/// araca (seyyar depo) taşır. [tip] transfer ya da kullanıma verme olabilir;
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
  });

  @override
  ConsumerState<TopluTransferScreen> createState() =>
      _TopluTransferScreenState();
}

class _TopluTransferScreenState extends ConsumerState<TopluTransferScreen> {
  final _seriCtrl = TextEditingController();
  final _notCtrl = TextEditingController();
  final _liste = <CihazBilgi>[];
  String? _sebep; // toplu iadede opsiyonel geri alma sebebi
  String? _arizaKarari; // iadede "Arıza" seçildiyse: tamir | degisim

  String? _hedefId;
  bool _kameraAcik = false;
  bool _coklu = false;
  bool _kaydediliyor = false;
  bool _mesgul = false;
  MobileScannerController? _kamera;
  String? _sonKod;
  DateTime _sonZaman = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _kullanim => widget.tip == HareketTipi.kullanim;
  bool get _iade => widget.tip == HareketTipi.iade;

  /// Hedef seçilmeden gelen seri numaraları (hedef seçilince eklenir).
  final _bekleyen = <String>[];

  @override
  void initState() {
    super.initState();
    _hedefId = widget.onceHedefDepoId;
    for (final k in widget.onceSeriNolari) {
      for (final s in seriNolariAyir(k)) {
        if (!_bekleyen.contains(s)) _bekleyen.add(s);
      }
    }
    if (_hedefId != null && _bekleyen.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bekleyenleriEkle());
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
    if (_liste.isEmpty) {
      _mesaj('Önce seri numarası ekleyin', hata: true);
      return;
    }
    if (_iade) {
      final h = iadeSebebiHatasi(_sebep, _notCtrl.text,
          zorunlu: false, arizaKarari: _arizaKarari, arizaSor: true);
      if (h != null) {
        _mesaj(h, hata: true);
        return;
      }
      final hedefArac = (ref.read(depolarStreamProvider).value ?? <Depo>[])
          .any((d) => d.id == _hedefId && d.arac);
      if (_sebep == 'Arıza' && hedefArac) {
        _mesaj('Arızalı cihazlar bir depoya iade edilmeli', hata: true);
        return;
      }
    }
    setState(() => _kaydediliyor = true);
    try {
      final adet = _liste.length;
      await ref.read(appDatabaseProvider).cihazlariTopluHareketKaydet(
            cihazIdleri: [for (final b in _liste) b.cihaz.id],
            tip: widget.tip,
            kullaniciId: ref.read(aktifKullaniciIdProvider) ?? 'demo-kullanici',
            hedefDepoId: _hedefId,
            not_: _notCtrl.text.trim().isEmpty ? null : _notCtrl.text.trim(),
            sebep: _iade ? _sebep : null,
            arizaKarari: _iade && _sebep == 'Arıza' ? _arizaKarari : null,
          );
      SesServisi.basari();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_kullanim
              ? '$adet cihaz kullanıma verildi'
              : (_iade
                  ? '$adet cihaz iade edildi'
                  : '$adet cihaz transfer edildi'))));
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
    final tumu = ref.watch(depolarStreamProvider).value ?? <Depo>[];
    final hedefler = [...tumu];
    if (_kullanim) {
      hedefler.sort((a, b) => (a.arac ? 0 : 1).compareTo(b.arac ? 0 : 1));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_kullanim
            ? 'Toplu Kullanıma Ver'
            : (_iade ? 'Toplu İade' : 'Toplu Transfer')),
        actions: [
          IconButton(
            icon: Icon(_kameraAcik ? Icons.videocam_off : Icons.videocam),
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
                      ? 'Hangi depo / araca verilecek?'
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
              controller: _seriCtrl,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Seri numarası (elle yaz veya okut)',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add_circle),
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
                        subtitle:
                            Text('${b.urunAdi} · ${b.depoAdi ?? '-'} içinde'),
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
                      icon: Icon(_kullanim
                          ? Icons.local_shipping_outlined
                          : (_iade
                              ? Icons.assignment_return_outlined
                              : Icons.swap_horiz)),
                      label: Text(_kaydediliyor
                          ? 'Kaydediliyor...'
                          : (_kullanim
                              ? 'Kullanıma ver (${_liste.length})'
                              : (_iade
                                  ? 'İade al (${_liste.length})'
                                  : 'Transfer et (${_liste.length})'))),
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
