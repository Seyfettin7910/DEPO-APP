import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../database/app_database.dart';
import '../../providers/app_providers.dart';
import '../../services/etiket/etiket_kodu.dart';
import '../../services/ses_servisi.dart';
import '../../widgets/hedefli_tarayici.dart';
import '../../widgets/kod_yardimci.dart';

class _Sonuc {
  _Sonuc(this.kod, this.seri, this.eslesti, this.mesaj);
  final String kod;
  final String seri;
  final bool eslesti;
  final String mesaj;
}

/// Yapıştırma doğrulaması: önce kurum etiketi, sonra cihazın kendi seri no
/// barkodu okutulur. Eşleşirse etiket "doğrulandı" olur; eşleşmezse alarm
/// verilir ve uyuşmazlık kaydedilir. Döngü kendiliğinden sıradakine geçer.
class EtiketDogrulaScreen extends ConsumerStatefulWidget {
  const EtiketDogrulaScreen({super.key});

  @override
  ConsumerState<EtiketDogrulaScreen> createState() =>
      _EtiketDogrulaScreenState();
}

class _EtiketDogrulaScreenState extends ConsumerState<EtiketDogrulaScreen> {
  final MobileScannerController? _kamera =
      bilgisayarTarayicisi ? null : tarayiciOlustur();
  final _ctrl = TextEditingController();
  final _odak = FocusNode();

  EtiketBilgi? _etiket; // okutulan etiket; cihazın seri nosu bekleniyor
  final _sonuclar = <_Sonuc>[];
  bool _mesgul = false;
  String? _sonKod;
  DateTime _sonZaman = DateTime.fromMillisecondsSinceEpoch(0);
  String? _uyari;

  @override
  void dispose() {
    _kamera?.dispose();
    _ctrl.dispose();
    _odak.dispose();
    super.dispose();
  }

  String get _kullanici =>
      ref.read(aktifKullaniciIdProvider) ?? 'demo-kullanici';

  void _okundu(BarcodeCapture capture) {
    final kodlar = okunanKodlar(capture);
    if (kodlar.length != 1) return;
    _isle(kodlar.first);
  }

  Future<void> _isle(String ham) async {
    if (_mesgul) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final kod = ham.trim();
    if (kod.isEmpty) return;
    final simdi = DateTime.now();
    if (kod == _sonKod && simdi.difference(_sonZaman) < const Duration(seconds: 3)) {
      return;
    }
    _sonKod = kod;
    _sonZaman = simdi;
    _mesgul = true;
    try {
      if (_etiket == null) {
        await _etiketOkundu(kod);
      } else {
        await _seriOkundu(kod);
      }
    } finally {
      _mesgul = false;
      _ctrl.clear();
      if (bilgisayarTarayicisi) _odak.requestFocus();
    }
  }

  Future<void> _etiketOkundu(String kod) async {
    final db = ref.read(appDatabaseProvider);
    final okuma = EtiketKodu.coz(kod);
    if (okuma == null) {
      SesServisi.hata();
      setState(() => _uyari =
          'Bu bir kurum etiketi değil. Önce yapıştırılan kurum etiketini okutun.');
      return;
    }
    final e = await db.etiketBul(okuma.kod);
    if (!mounted) return;
    if (e == null) {
      SesServisi.hata();
      setState(() => _uyari = '${okuma.kod}: etiket sistemde bulunamadı '
          '(henüz eşitlenmemiş olabilir; internet bağlantısını kontrol edin).');
      return;
    }
    if (okuma.surum != null && okuma.surum! < e.surum) {
      SesServisi.hata();
      setState(() => _uyari = '${e.kod}: ESKİ ETİKET (sürüm ${okuma.surum}). '
          'Bu etiketin yenisi basıldı (sürüm ${e.surum}); eskisini kullanmayın.');
      return;
    }
    if (e.seriNosuz) {
      await _dogrula(e, '');
      return;
    }
    SesServisi.basari();
    setState(() {
      _etiket = e;
      _uyari = null;
    });
  }

  Future<void> _seriOkundu(String kod) async {
    final e = _etiket!;
    final okuma = EtiketKodu.coz(kod);
    if (okuma != null) {
      if (okuma.kod == e.kod) return; // aynı etiket tekrar görüldü
      SesServisi.hata();
      setState(() => _uyari = 'Bu da bir kurum etiketi. Şimdi cihazın KENDİ '
          'seri numarası barkodunu okutun (üretici etiketi).');
      return;
    }
    final seriler = seriNolariAyir(kod);
    if (seriler.length != 1) {
      SesServisi.hata();
      setState(() => _uyari = 'Koli karekodu okutuldu. Cihazın kendi seri '
          'numarasını okutun.');
      return;
    }
    await _dogrula(e, seriler.first);
  }

  Future<void> _dogrula(EtiketBilgi e, String seri) async {
    final db = ref.read(appDatabaseProvider);
    try {
      final s = await db.etiketDogrula(
          etiketId: e.id, okunanSeri: seri, kullaniciId: _kullanici);
      if (!mounted) return;
      setState(() {
        _etiket = null;
        _uyari = null;
        _sonuclar.insert(
          0,
          _Sonuc(
            e.kod,
            e.seriNosuz ? 'seri nosuz' : s.okunanSeri,
            s.eslesti,
            s.eslesti
                ? e.urunAdi
                : 'Etiket ${s.beklenenSeri} cihazına ait!',
          ),
        );
      });
      if (s.eslesti) {
        SesServisi.basari();
      } else {
        await _alarm(e, s);
      }
    } catch (err) {
      SesServisi.hata();
      if (mounted) {
        setState(() => _uyari =
            err is StateError ? err.message : 'Kaydedilemedi: $err');
      }
    }
  }

  Future<void> _alarm(EtiketBilgi e, EtiketDogrulamaSonucu s) async {
    SesServisi.hata();
    await Future.delayed(const Duration(milliseconds: 350));
    SesServisi.hata();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.red.shade50,
        icon: Icon(Icons.report_gmailerrorred, color: Colors.red.shade700, size: 48),
        title: Text('UYUŞMAZLIK',
            style: TextStyle(color: Colors.red.shade800, fontWeight: FontWeight.bold)),
        content: Text(
          'Etiket ${e.kod}\n${s.beklenenSeri} seri nolu cihaza ait '
          '(${e.urunAdi}).\n\nOkuttuğunuz cihaz: ${s.okunanSeri}\n\n'
          'Etiket yanlış cihaza yapıştırılmış olabilir. Etiketi doğru cihaza '
          'yapıştırıp yeniden doğrulayın. Uyuşmazlık kaydedildi.',
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anladım'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = _etiket;
    final tema = Theme.of(context);
    final ikinci = e != null;
    final yukseklik = MediaQuery.sizeOf(context).height;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Etiket doğrula'),
        actions: [
          if (_kamera != null)
            IconButton(
              icon: const Icon(Icons.flash_on),
              tooltip: 'Flaş',
              onPressed: () => _kamera!.toggleTorch(),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_kamera != null)
            SizedBox(
              height: (yukseklik * 0.4).clamp(220.0, 380.0),
              child: HedefliTarayici(controller: _kamera!, onDetect: _okundu),
            ),
          Container(
            width: double.infinity,
            color: ikinci ? Colors.amber.shade100 : tema.colorScheme.primaryContainer,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: ikinci ? Colors.amber.shade700 : tema.colorScheme.primary,
                  foregroundColor: Colors.white,
                  child: Text(ikinci ? '2' : '1'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ikinci
                            ? 'Şimdi cihazın KENDİ seri no barkodunu okutun'
                            : 'Yapıştırılan kurum etiketini okutun',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      if (ikinci)
                        Text('Etiket: ${e.kod} · ${e.urunAdi}'),
                    ],
                  ),
                ),
                if (ikinci)
                  TextButton(
                    onPressed: () => setState(() {
                      _etiket = null;
                      _uyari = null;
                    }),
                    child: const Text('Vazgeç'),
                  ),
              ],
            ),
          ),
          if (bilgisayarTarayicisi)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _ctrl,
                focusNode: _odak,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: ikinci
                      ? 'Cihazın seri numarası (barkod okuyucuyla)'
                      : 'Kurum etiketi (barkod okuyucuyla)',
                ),
                onSubmitted: _isle,
              ),
            ),
          if (_uyari != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(_uyari!, style: TextStyle(color: Colors.red.shade800)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                Text(
                  'Bu oturumda: ${_sonuclar.where((s) => s.eslesti).length} doğrulandı'
                  '${_sonuclar.any((s) => !s.eslesti) ? ' · ${_sonuclar.where((s) => !s.eslesti).length} uyuşmazlık' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _sonuclar.length,
              itemBuilder: (_, i) {
                final s = _sonuclar[i];
                return ListTile(
                  dense: true,
                  leading: Icon(
                    s.eslesti ? Icons.verified : Icons.report_gmailerrorred,
                    color: s.eslesti ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                  title: Text('${s.kod} ↔ ${s.seri}'),
                  subtitle: Text(s.mesaj),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
