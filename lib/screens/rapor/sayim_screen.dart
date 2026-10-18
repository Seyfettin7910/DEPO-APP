import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../database/app_database.dart';
import '../../database/models.dart';
import '../../providers/app_providers.dart';
import '../../services/rapor/rapor_olusturucu.dart';
import '../../services/ses_servisi.dart';
import '../../widgets/depo_secici.dart';
import '../../widgets/hedefli_tarayici.dart';
import '../../widgets/kod_yardimci.dart';
import 'rapor_onizleme_screen.dart';

/// Sayım modu: bir depo veya araç seçilir, oradaki cihazlar tek tek
/// okutulur. Sistemdeki kayıtla karşılaştırılır:
///  - Bulunan: sistemde burada, okutuldu
///  - Eksik:   sistemde burada, okutulmadı
///  - Fazla:   okutuldu ama sistemde burada değil (başka yerde / kayıtsız)
/// Sayım sistemde hiçbir şeyi değiştirmez; sonunda rapor alınır.
class SayimScreen extends ConsumerStatefulWidget {
  const SayimScreen({super.key, this.onceSeciliDepoId});

  final String? onceSeciliDepoId;

  @override
  ConsumerState<SayimScreen> createState() => _SayimScreenState();
}

class _SayimScreenState extends ConsumerState<SayimScreen> {
  final _seriCtrl = TextEditingController();
  final _seriOdak = FocusNode();

  String? _depoId;
  DateTime _baslangic = DateTime.now();

  /// Okutulan seri no -> sistemdeki bilgisi (kayıtsızsa null). Ekleme sırası korunur.
  final _okunanlar = <String, CihazBilgi?>{};

  bool _kameraAcik = false;
  MobileScannerController? _kamera;
  bool _coklu = false;
  bool _mesgul = false;
  String? _sonKod;
  DateTime _sonZaman = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _depoId = widget.onceSeciliDepoId;
  }

  @override
  void dispose() {
    _seriCtrl.dispose();
    _seriOdak.dispose();
    _kamera?.dispose();
    super.dispose();
  }

  String _norm(String s) => s.trim().toUpperCase();

  void _mesaj(String metin, {Color? renk}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(metin),
        backgroundColor: renk,
        duration: const Duration(seconds: 2),
      ));
  }

  Future<void> _depoDegistir(String? yeni) async {
    if (yeni == _depoId) return;
    if (_okunanlar.isNotEmpty) {
      final onay = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sayım sıfırlansın mı?'),
          content: Text(
              '${_okunanlar.length} okutma silinecek ve yeni konumda baştan başlanacak.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Sıfırla')),
          ],
        ),
      );
      if (onay != true) return;
    }
    setState(() {
      _depoId = yeni;
      _okunanlar.clear();
      _baslangic = DateTime.now();
    });
  }

  Future<void> _okut(String ham, List<CihazBilgi> beklenen) async {
    final seri = _norm(ham);
    if (seri.isEmpty) return;
    if (_depoId == null) {
      SesServisi.hata();
      _mesaj('Önce sayılacak depoyu veya aracı seçin',
          renk: Colors.red.shade700);
      return;
    }
    if (_okunanlar.containsKey(seri)) {
      _mesaj('$seri zaten sayıldı');
      _seriCtrl.clear();
      return;
    }

    final buradaMi = beklenen.any((c) => c.cihaz.seriNo == seri);
    CihazBilgi? bilgi;
    if (buradaMi) {
      bilgi = beklenen.firstWhere((c) => c.cihaz.seriNo == seri);
    } else {
      bilgi = await ref.read(appDatabaseProvider).seriNoIleCihazBilgi(seri);
    }
    if (!mounted) return;

    setState(() {
      _okunanlar[seri] = bilgi;
      _seriCtrl.clear();
    });

    if (buradaMi) {
      SesServisi.basari();
      _mesaj('✓ $seri · ${bilgi!.urunAdi}', renk: Colors.green.shade700);
    } else {
      SesServisi.hata();
      _mesaj('Fazla: $seri · ${RaporOlusturucu.sistemdekiYer(bilgi)}',
          renk: Colors.orange.shade800);
    }
    _seriOdak.requestFocus();
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

  Future<void> _okundu(BarcodeCapture capture, List<CihazBilgi> beklenen) async {
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
      await _okut(kod, beklenen);
    } finally {
      _mesgul = false;
    }
  }

  void _raporAl(String depoAdi, List<CihazBilgi> beklenen) {
    final rapor = RaporOlusturucu.sayim(
      depoAdi: depoAdi,
      beklenen: beklenen,
      okunanlar: Map.of(_okunanlar),
      baslangic: _baslangic,
    );
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RaporOnizlemeScreen(rapor: rapor)));
  }

  @override
  Widget build(BuildContext context) {
    final depolar = ref.watch(depolarStreamProvider).value ?? <Depo>[];
    final secili = depolar.where((d) => d.id == _depoId).firstOrNull;
    final beklenen = _depoId == null
        ? <CihazBilgi>[]
        : (ref.watch(depoCihazlariProvider(_depoId!)).value ?? <CihazBilgi>[])
            // Garanti servisindeki cihaz fiziksel olarak firmadadır.
            .where((c) => c.cihaz.servisDurumu != ServisDurumu.garantide)
            .toList();

    final beklenenSeriler = {for (final c in beklenen) c.cihaz.seriNo};
    final bulunan =
        beklenen.where((c) => _okunanlar.containsKey(c.cihaz.seriNo)).toList();
    final eksik =
        beklenen.where((c) => !_okunanlar.containsKey(c.cihaz.seriNo)).toList();
    final fazla = _okunanlar.entries
        .where((e) => !beklenenSeriler.contains(e.key))
        .toList()
        .reversed
        .toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sayım'),
          actions: [
            IconButton(
              icon: Icon(_kameraAcik ? Icons.videocam_off : Icons.videocam),
              tooltip: _kameraAcik ? 'Kamerayı kapat' : 'Kamerayla okut',
              onPressed: _kameraDegistir,
            ),
            IconButton(
              icon: const Icon(Icons.summarize_outlined),
              tooltip: 'Sayımı bitir, rapor al',
              onPressed: secili == null
                  ? null
                  : () => _raporAl(secili.ad, beklenen),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: DropdownButtonFormField<String>(
                value: secili?.id,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Sayılacak depo / araç'),
                items: depoDropdownOgeleri(depolar),
                onChanged: _depoDegistir,
              ),
            ),
            if (_kameraAcik && _kamera != null)
              SizedBox(
                height: 200,
                child: Stack(
                  children: [
                    HedefliTarayici(
                      controller: _kamera!,
                      onDetect: (c) => _okundu(c, beklenen),
                    ),
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
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: TextField(
                controller: _seriCtrl,
                focusNode: _seriOdak,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Seri no (yazın veya USB okuyucuyla okutun)',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => _okut(_seriCtrl.text, beklenen),
                  ),
                ),
                onSubmitted: (v) => _okut(v, beklenen),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  _sayac('Olmalı', beklenen.length, Colors.blueGrey),
                  _sayac('Bulunan', bulunan.length, Colors.green.shade700),
                  _sayac('Eksik', eksik.length, Colors.red.shade700),
                  _sayac('Fazla', fazla.length, Colors.orange.shade800),
                ],
              ),
            ),
            if (_depoId != null && beklenen.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(
                  value: bulunan.length / beklenen.length,
                  minHeight: 6,
                ),
              ),
            TabBar(tabs: [
              Tab(text: 'Eksik (${eksik.length})'),
              Tab(text: 'Bulunan (${bulunan.length})'),
              Tab(text: 'Fazla (${fazla.length})'),
            ]),
            Expanded(
              child: _depoId == null
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Sayılacak depoyu veya aracı seçin, sonra oradaki '
                          'cihazların seri numaralarını tek tek okutun.\n\n'
                          'Sayım sistemde hiçbir şeyi değiştirmez; sonunda '
                          'sağ üstten raporu (PDF / Excel) alırsınız.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : TabBarView(children: [
                      _cihazListesi(eksik, Icons.help_outline,
                          Colors.red.shade700, 'Eksik yok, hepsi bulundu 🎉'),
                      _cihazListesi(bulunan, Icons.check_circle,
                          Colors.green.shade700, 'Henüz okutma yok'),
                      fazla.isEmpty
                          ? const Center(child: Text('Fazla cihaz yok'))
                          : ListView.separated(
                              itemCount: fazla.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final e = fazla[i];
                                return ListTile(
                                  dense: true,
                                  leading: Icon(Icons.warning_amber,
                                      color: Colors.orange.shade800),
                                  title: Text(e.key),
                                  subtitle: Text(
                                      '${e.value?.urunAdi ?? 'Bilinmeyen ürün'}\n'
                                      '${RaporOlusturucu.sistemdekiYer(e.value)}'),
                                  isThreeLine: true,
                                  trailing: IconButton(
                                    icon: const Icon(Icons.close),
                                    tooltip: 'Okutmayı geri al',
                                    onPressed: () => setState(
                                        () => _okunanlar.remove(e.key)),
                                  ),
                                );
                              },
                            ),
                    ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sayac(String etiket, int deger, Color renk) => Expanded(
        child: Column(
          children: [
            Text('$deger',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: renk)),
            Text(etiket, style: const TextStyle(fontSize: 12)),
          ],
        ),
      );

  Widget _cihazListesi(
      List<CihazBilgi> liste, IconData ikon, Color renk, String bos) {
    if (liste.isEmpty) return Center(child: Text(bos));
    return ListView.separated(
      itemCount: liste.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final c = liste[i];
        final okundu = _okunanlar.containsKey(c.cihaz.seriNo);
        return ListTile(
          dense: true,
          leading: Icon(ikon, color: renk),
          title: Text(c.cihaz.seriNo),
          subtitle: Text(c.urunAdi),
          trailing: okundu
              ? IconButton(
                  icon: const Icon(Icons.undo),
                  tooltip: 'Okutmayı geri al',
                  onPressed: () =>
                      setState(() => _okunanlar.remove(c.cihaz.seriNo)),
                )
              : null,
        );
      },
    );
  }
}
