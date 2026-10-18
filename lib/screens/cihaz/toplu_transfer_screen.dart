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

  const TopluTransferScreen({
    super.key,
    this.tip = HareketTipi.transfer,
    this.onceHedefDepoId,
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

  @override
  void initState() {
    super.initState();
    _hedefId = widget.onceHedefDepoId;
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

  Future<void> _ekle(String ham) async {
    final seri = ham.trim().toUpperCase();
    if (seri.isEmpty) return;

    if (_hedefId == null) {
      SesServisi.hata();
      _mesaj('Önce hedef depo / araç seçin', hata: true);
      return;
    }
    if (_liste.any((b) => b.cihaz.seriNo == seri)) {
      SesServisi.hata();
      _mesaj('$seri zaten listede', hata: true);
      return;
    }

    final bilgi = await ref.read(appDatabaseProvider).seriNoIleCihazBilgi(seri);
    if (!mounted) return;
    if (bilgi == null) {
      SesServisi.hata();
      _mesaj('Kayıtlı cihaz yok: $seri', hata: true);
      return;
    }
    if (bilgi.cihaz.durum != CihazDurumu.depoda) {
      SesServisi.hata();
      _mesaj('$seri şu an depoda değil (${cihazKonumMetni(bilgi)})',
          hata: true);
      return;
    }
    if (bilgi.cihaz.depoId == _hedefId) {
      SesServisi.hata();
      _mesaj('$seri zaten hedefte: ${bilgi.depoAdi ?? '-'}', hata: true);
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
    if (_hedefId == null) {
      _mesaj('Hedef depo / araç seçin', hata: true);
      return;
    }
    if (_liste.isEmpty) {
      _mesaj('Önce seri numarası ekleyin', hata: true);
      return;
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
              onChanged: (v) => setState(() => _hedefId = v),
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
