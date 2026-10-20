import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../database/app_database.dart';
import '../../database/models.dart';
import '../../providers/app_providers.dart';
import '../../services/rapor/rapor_olusturucu.dart';
import '../../services/ses_servisi.dart';
import '../../services/taslak_servisi.dart';
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
  const SayimScreen({super.key, this.onceSeciliDepoId, this.taslaktan = false});

  final String? onceSeciliDepoId;

  /// Yarım kalan sayıma devam etmek için açıldı (soru sorulmaz).
  final bool taslaktan;

  @override
  ConsumerState<SayimScreen> createState() => _SayimScreenState();
}

class _SayimScreenState extends ConsumerState<SayimScreen>
    with YarimIsKorumasi<SayimScreen> {
  final _seriCtrl = TextEditingController();
  final _seriOdak = FocusNode();

  String? _depoId;
  DateTime _baslangic = DateTime.now();

  /// Okutulan seri no -> sistemdeki bilgisi (kayıtsızsa null). Ekleme sırası korunur.
  final _okunanlar = <String, CihazBilgi?>{};

  /// Miktarlı malzemelerde sayılan miktar (urunId -> miktar).
  final _malzemeSayim = <String, int>{};

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
    taslakKorumasiniBaslat();
  }

  @override
  String get taslakTuru => 'sayim';

  @override
  bool get taslaktanAcildi => widget.taslaktan;

  @override
  Taslak? taslakOlustur() {
    if (_depoId == null || (_okunanlar.isEmpty && _malzemeSayim.isEmpty)) {
      return null;
    }
    final depo = (ref.read(depolarStreamProvider).valueOrNull ?? <Depo>[])
        .where((d) => d.id == _depoId)
        .firstOrNull;
    return Taslak(
      tur: taslakTuru,
      baslik: 'Sayım · ${depo?.ad ?? '-'}',
      ozet: '${_okunanlar.length} okutma'
          '${_malzemeSayim.isEmpty ? '' : ' · ${_malzemeSayim.length} malzeme'}',
      veri: {
        'depoId': _depoId,
        'baslangic': _baslangic.millisecondsSinceEpoch,
        'seriler': _okunanlar.keys.toList(),
        'malzeme': Map.of(_malzemeSayim),
      },
    );
  }

  @override
  Future<void> taslagiYukle(Taslak t) async {
    final db = ref.read(appDatabaseProvider);
    final seriler = [for (final s in (t.veri['seriler'] as List? ?? [])) '$s'];
    final yeni = <String, CihazBilgi?>{};
    for (final s in seriler) {
      yeni[s] = await db.seriNoIleCihazBilgi(s);
    }
    if (!mounted) return;
    setState(() {
      _depoId = t.veri['depoId'] as String? ?? _depoId;
      final b = t.veri['baslangic'];
      if (b is num) _baslangic = DateTime.fromMillisecondsSinceEpoch(b.toInt());
      _okunanlar
        ..clear()
        ..addAll(yeni);
      _malzemeSayim.clear();
      for (final e in ((t.veri['malzeme'] as Map?) ?? const {}).entries) {
        _malzemeSayim['${e.key}'] = (e.value as num?)?.toInt() ?? 0;
      }
    });
  }

  @override
  void dispose() {
    taslakKorumasiniBitir();
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
    if (_okunanlar.isNotEmpty || _malzemeSayim.isNotEmpty) {
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
      _malzemeSayim.clear();
      _baslangic = DateTime.now();
    });
  }

  /// Koli karekodu: kolideki bütün seri numaraları tek seferde sayılır.
  Future<void> _cokluOkut(List<String> seriler, List<CihazBilgi> beklenen) async {
    if (_depoId == null) {
      SesServisi.hata();
      _mesaj('Önce sayılacak depoyu veya aracı seçin',
          renk: Colors.red.shade700);
      return;
    }
    var burada = 0, fazla = 0, onceden = 0;
    final yeniler = <String, CihazBilgi?>{};
    final db = ref.read(appDatabaseProvider);
    for (final ham in seriler) {
      final seri = await db.seriyeCevir(ham);
      if (_okunanlar.containsKey(seri) || yeniler.containsKey(seri)) {
        onceden++;
        continue;
      }
      final b = beklenen.where((c) => c.cihaz.seriNo == seri).firstOrNull;
      if (b != null) {
        yeniler[seri] = b;
        burada++;
      } else {
        yeniler[seri] =
            await ref.read(appDatabaseProvider).seriNoIleCihazBilgi(seri);
        fazla++;
      }
    }
    if (!mounted) return;
    setState(() => _okunanlar.addAll(yeniler));
    if (fazla > 0) {
      SesServisi.hata();
    } else {
      SesServisi.basari();
    }
    _mesaj(
        'Koli: $burada sayıldı'
        '${fazla > 0 ? ' · $fazla fazla' : ''}'
        '${onceden > 0 ? ' · $onceden zaten sayılmıştı' : ''}',
        renk: fazla > 0 ? Colors.orange.shade800 : Colors.green.shade700);
  }

  Future<void> _okut(String ham, List<CihazBilgi> beklenen) async {
    final seriler = seriNolariAyir(ham);
    if (seriler.length > 1) {
      _seriCtrl.clear();
      await _cokluOkut(seriler, beklenen);
      return;
    }
    // Kurum etiketi okutulduysa cihazın seri numarasına çevrilir.
    final seri = ham.trim().isEmpty
        ? ''
        : await ref.read(appDatabaseProvider).seriyeCevir(_norm(ham));
    if (seri.isEmpty || !mounted) return;
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
        _kamera = tarayiciOlustur();
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

  void _raporAl(String depoAdi, List<CihazBilgi> beklenen,
      List<(Urun, int)> malzemeler) {
    final rapor = RaporOlusturucu.sayim(
      depoAdi: depoAdi,
      beklenen: beklenen,
      okunanlar: Map.of(_okunanlar),
      baslangic: _baslangic,
      malzemeler: [
        for (final (u, sistemde) in malzemeler)
          (u.ad, u.birim, sistemde, _malzemeSayim[u.id]),
      ],
    );
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RaporOnizlemeScreen(rapor: rapor)));
  }

  @override
  Widget build(BuildContext context) {
    final depolar = ref.watch(depolarStreamProvider).valueOrNull ?? <Depo>[];
    final secili = depolar.where((d) => d.id == _depoId).firstOrNull;
    final beklenen = _depoId == null
        ? <CihazBilgi>[]
        : (ref.watch(depoCihazlariProvider(_depoId!)).valueOrNull ?? <CihazBilgi>[])
            // Garanti servisindeki cihaz fiziksel olarak firmadadır.
            .where((c) => c.cihaz.servisDurumu != ServisDurumu.garantide)
            .toList();

    final beklenenSeriler = {for (final c in beklenen) c.cihaz.seriNo};
    final malzemeStok = ref.watch(malzemeStoklariProvider).valueOrNull ??
        const <String, Map<String, int>>{};
    final malzemeler = _depoId == null
        ? <(Urun, int)>[]
        : [
            for (final u in ref.watch(urunlerStreamProvider).valueOrNull ?? <Urun>[])
              if (u.miktarli &&
                  ((malzemeStok[u.id]?[_depoId] ?? 0) != 0 ||
                      _malzemeSayim.containsKey(u.id)))
                (u, malzemeStok[u.id]?[_depoId] ?? 0),
          ];
    final bulunan =
        beklenen.where((c) => _okunanlar.containsKey(c.cihaz.seriNo)).toList();
    final eksik =
        beklenen.where((c) => !_okunanlar.containsKey(c.cihaz.seriNo)).toList();
    final fazla = _okunanlar.entries
        .where((e) => !beklenenSeriler.contains(e.key))
        .toList()
        .reversed
        .toList();

    return yarimIsKapsayici(
        child: DefaultTabController(
      length: 4,
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
                  : () => _raporAl(secili.ad, beklenen, malzemeler),
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
                height: (MediaQuery.sizeOf(context).height * 0.34)
                    .clamp(220.0, 340.0),
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
            TabBar(isScrollable: true, tabs: [
              Tab(text: 'Eksik (${eksik.length})'),
              Tab(text: 'Bulunan (${bulunan.length})'),
              Tab(text: 'Fazla (${fazla.length})'),
              Tab(text: 'Malzeme (${malzemeler.length})'),
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
                      _malzemeListesi(malzemeler),
                    ]),
            ),
          ],
        ),
      ),
    ));
  }

  Widget _malzemeListesi(List<(Urun, int)> malzemeler) {
    if (malzemeler.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Burada miktarla takip edilen malzeme yok',
              textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.separated(
      itemCount: malzemeler.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final (u, sistemde) = malzemeler[i];
        final sayilan = _malzemeSayim[u.id];
        final fark = sayilan == null ? null : sayilan - sistemde;
        return ListTile(
          leading: Icon(Icons.cable_outlined,
              color: fark == null
                  ? null
                  : (fark == 0
                      ? Colors.green.shade700
                      : Colors.orange.shade800)),
          title: Text(u.ad),
          subtitle: Text('Sistemde: ${u.miktarMetni(sistemde)}'
              '${fark == null || fark == 0 ? '' : ' · fark ${fark > 0 ? '+' : ''}$fark'}'),
          trailing: OutlinedButton(
            onPressed: () => _malzemeSay(u, sistemde),
            child: Text(sayilan == null ? 'Say' : u.miktarMetni(sayilan)),
          ),
        );
      },
    );
  }

  Future<void> _malzemeSay(Urun u, int sistemde) async {
    final ctrl = TextEditingController(
        text: '${_malzemeSayim[u.id] ?? sistemde}');
    final n = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(u.ad),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Sayılan (${u.birim})',
            helperText: 'Sistemde: ${u.miktarMetni(sistemde)}',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v.trim())),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, -1),
              child: const Text('Sayımı sil')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
              child: const Text('Tamam')),
        ],
      ),
    );
    ctrl.dispose();
    if (n == null || !mounted) return;
    setState(() {
      if (n < 0) {
        _malzemeSayim.remove(u.id);
      } else {
        _malzemeSayim[u.id] = n;
      }
    });
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
