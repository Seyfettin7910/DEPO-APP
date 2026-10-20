import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../database/app_database.dart';
import '../../providers/app_providers.dart';
import '../../services/etiket/etiket_kodu.dart';
import '../../services/ses_servisi.dart';
import '../malzeme/malzeme_islem_screen.dart';
import '../../widgets/silme_islemleri.dart';
import '../../widgets/kod_yardimci.dart';
import '../cihaz/cihaz_ara_screen.dart';
import '../cihaz/cihaz_detay_screen.dart';
import '../cihaz/toplu_giris_screen.dart';
import '../cihaz/toplu_transfer_screen.dart';
import '../../widgets/hedefli_tarayici.dart';
import '../../widgets/kritik_stok_seridi.dart';
import '../../widgets/renkler.dart';
import '../../widgets/sync_durum_dugmesi.dart';
import '../rapor/sayim_screen.dart';
import '../../database/models.dart';
import '../../widgets/koli_karekodu.dart';

/// Hızlı tarama: seri numarası okutulunca cihazın kartı (hangi ürün, hangi
/// depoda / araçta) açılır. Kayıtlı değilse uyarı sesi + titreşim verir ve
/// "Depoya ekle" önerir. Koli karekodu (içinde birden çok seri no) okutulursa
/// seri numaraları ayrılır ve kolinin özeti açılır.
///
/// Not: mobile_scanner iOS ve Android'de kamera ile doğrudan çalışır.
class BarkodTaramaScreen extends ConsumerStatefulWidget {
  const BarkodTaramaScreen({super.key});

  @override
  ConsumerState<BarkodTaramaScreen> createState() => _BarkodTaramaScreenState();
}

class _BarkodTaramaScreenState extends ConsumerState<BarkodTaramaScreen> {
  // Arka plana gidip dönüşte kamerayı HedefliTarayici yönetir.
  final _controller = tarayiciOlustur();

  Future<void> _durdur() async {
    try {
      await _controller.stop();
    } catch (_) {}
  }

  Future<void> _baslat() async {
    try {
      await _controller.start();
    } catch (_) {}
  }
  bool _mesgul = false;
  bool _coklu = false;
  String? _sonKod;
  DateTime _sonZaman = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Başka bir sayfa açarken arkadaki kamera durur (yoksa açılan sayfada
  /// okutulan kodları bu ekran da yakalar ve uyarı / "Depoya ekle" çıkar);
  /// geri dönünce yeniden başlar.
  Future<void> _ac(Widget ekran) async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    await _durdur();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ekran));
    if (!mounted) return;
    _sonZaman = DateTime.now(); // dönüşte aynı kodu hemen tekrar işlemesin
    // Açılan sayfanın kamerası tamamen kapansın, sonra bu ekranınki açılsın.
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) await _baslat();
  }

  Future<void> _kodBulundu(String kod) async {
    if (_mesgul) return;
    // Üstte başka sayfa açıksa (ör. depoya giriş) okunan kod bu ekranın değil.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;

    // Aynı kod kamerada durduğu sürece sürekli alarm çalmasın.
    final simdi = DateTime.now();
    if (kod == _sonKod &&
        simdi.difference(_sonZaman) < const Duration(seconds: 3)) {
      return;
    }
    _sonKod = kod;
    _sonZaman = simdi;
    _mesgul = true;

    try {
      // Koli karekodu: içinde kolideki bütün seri numaraları var.
      final seriler = seriNolariAyir(kod);
      if (seriler.isEmpty) return;
      if (seriler.length > 1) {
        SesServisi.basari();
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        await koliKarekoduGoster(context, ref, seriler, ac: _ac);
        _sonZaman = DateTime.now(); // kapanınca aynı koliyi hemen tekrar açmasın
        return;
      }
      kod = seriler.first;
      final bilgi =
          await ref.read(appDatabaseProvider).seriNoIleCihazBilgi(kod);
      if (!mounted) return;

      if (bilgi == null) {
        // Malzemenin (kablo, adaptör…) fabrika barkodu mu?
        final urun = await ref.read(appDatabaseProvider).barkodIleUrunBul(kod);
        if (!mounted) return;
        if (urun != null && !urun.deleted && urun.miktarli) {
          SesServisi.basari();
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          final secim = await secenekMenusu(context,
              baslik: '${urun.ad} (malzeme, ${urun.birim})',
              secenekler: const [
                ('giris', Icons.add_circle_outline, 'Giriş'),
                ('yukle', Icons.local_shipping_outlined, 'Araca Yükle'),
                ('kullanim', Icons.task_alt, 'Montaj / Kullanıldı'),
                ('transfer', Icons.swap_horiz, 'Transfer'),
              ]);
          if (secim == null || !mounted) return;
          await _ac(MalzemeIslemScreen(
              islem: MalzemeIslemi.values.firstWhere((m) => m.name == secim),
              onceUrunId: urun.id));
          return;
        }
        SesServisi.hata();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Kayıtlı cihaz yok: $kod'),
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Depoya ekle',
                textColor: Colors.white,
                onPressed: () =>
                    _ac(TopluGirisScreen(onceSeriNolari: [kod])),
              ),
            ),
          );
        return;
      }

      // Eski (yenisi basılmış) kurum etiketi okutulduysa uyar.
      final okuma = EtiketKodu.coz(kod);
      if (okuma?.surum != null) {
        final e = await ref.read(appDatabaseProvider).etiketBul(okuma!.kod);
        if (e != null && okuma.surum! < e.surum && mounted) {
          SesServisi.hata();
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(Icons.warning_amber, color: Colors.orange),
              title: const Text('Eski etiket'),
              content: Text('Bu etiketin yenisi basıldı (sürüm ${e.surum}). '
                  'Okuttuğunuz etiket sürüm ${okuma.surum}; cihaz üzerindeki '
                  'eski etiketi yenisiyle değiştirin.\n\n${e.kod} · ${e.seriNo}'),
              actions: [
                FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Tamam')),
              ],
            ),
          );
          if (!mounted) return;
        }
      }

      SesServisi.basari();
      await _ac(CihazDetayScreen(cihazId: bilgi.cihaz.id));
    } finally {
      _mesgul = false;
    }
  }

  void _okundu(BarcodeCapture capture) {
    final kodlar = okunanKodlar(capture);
    if (kodlar.isEmpty) return;
    if (kodlar.length > 1) {
      // Etikette birden çok barkod: hangisinin seri no olduğu belli değil.
      if (!_coklu) setState(() => _coklu = true);
      return;
    }
    if (_coklu) setState(() => _coklu = false);
    _kodBulundu(kodlar.first);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seri No Okut'),
        actions: ustDugmeler(),
      ),
      body: Column(
        children: [
          const KritikStokSeridi(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _kamera(),
              ),
            ),
          ),
          _altBolum(),
        ],
      ),
    );
  }

  /// Kameranın altı: "Elle yaz" / "Fener" ve hızlı işlemler (Depoya giriş,
  /// Transfer, Araca Yükle, Sayım).
  Widget _altBolum() {
    final tema = Theme.of(context);
    Widget ikincil(IconData ikon, Color renk, String ad, VoidCallback f) =>
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: tema.colorScheme.onSurface,
              side: BorderSide(color: tema.colorScheme.outline, width: 1.2),
              textStyle:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            icon: Icon(ikon, color: renk, size: 22),
            label: Text(ad),
            onPressed: f,
          ),
        );

    Widget kutu(IconData ikon, Color renk, Color zemin, String ad,
            VoidCallback f) =>
        Material(
          color: zemin,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: f,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(children: [
                RenkliSimge(ikon,
                    renk: renk, zemin: zemin, boyut: 38, dolu: true),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(ad,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w500)),
                ),
              ]),
            ),
          ),
        );

    final kutular = [
      kutu(Icons.add_box_outlined, Renkler.okut, Renkler.okutZemin,
          'Depoya giriş', () => _ac(const TopluGirisScreen())),
      kutu(Icons.swap_horiz, Renkler.depo, Renkler.depoZemin, 'Transfer',
          () => _ac(const TopluTransferScreen())),
      kutu(Icons.local_shipping_outlined, Renkler.urun, Renkler.urunZemin,
          'Araca Yükle',
          () => _ac(const TopluTransferScreen(tip: HareketTipi.kullanim))),
      kutu(Icons.fact_check_outlined, Renkler.ara, Renkler.araZemin, 'Sayım',
          () => _ac(const SayimScreen())),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              ikincil(Icons.keyboard_outlined, Renkler.depo, 'Elle yaz',
                  () => _ac(const CihazAraScreen())),
              const SizedBox(width: 8),
              ikincil(Icons.flashlight_on_outlined, Renkler.zil, 'Fener',
                  () async {
                try {
                  await _controller.toggleTorch();
                } catch (_) {}
              }),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
              child: Text('HIZLI İŞLEMLER',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.4,
                      color: tema.colorScheme.onSurfaceVariant)),
            ),
            LayoutBuilder(builder: (context, c) {
              // Geniş ekranda (bilgisayar) dördü tek satırda.
              final sutun = c.maxWidth >= 640 ? 4 : 2;
              final satirlar = <Widget>[];
              for (var i = 0; i < kutular.length; i += sutun) {
                if (i > 0) satirlar.add(const SizedBox(height: 8));
                satirlar.add(Row(children: [
                  for (var j = i; j < i + sutun; j++) ...[
                    if (j > i) const SizedBox(width: 8),
                    Expanded(child: kutular[j]),
                  ],
                ]));
              }
              return Column(children: satirlar);
            }),
          ],
        ),
      ),
    );
  }

  Widget _kamera() {
    return Stack(
        children: [
          HedefliTarayici(
            controller: _controller,
            onDetect: _okundu,
            // Kayıtlı seri no / kurum etiketi / malzeme barkodu hızlı okunur,
            // bilinmeyen kod biraz daha uzun sabit tutulmalı.
            bilinenMi: (kod) async {
              final db = ref.read(appDatabaseProvider);
              if (await db.seriNoIleCihazBilgi(kod) != null) return true;
              final u = await db.barkodIleUrunBul(kod);
              return u != null && u.miktarli;
            },
          ),
          if (_coklu)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                color: Colors.black87,
                padding: const EdgeInsets.all(12),
                child: const Text(
                  'Çerçevede birden çok kod var. Yaklaştırıp yalnızca seri no kodunu çerçeveye alın.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.amber),
                ),
              ),
            ),
        ],
      );
  }
}
