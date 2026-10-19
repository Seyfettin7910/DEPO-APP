import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../database/app_database.dart';
import '../../providers/app_providers.dart';
import '../../services/etiket/etiket_kodu.dart';
import '../../services/ses_servisi.dart';
import '../../widgets/kod_yardimci.dart';
import '../cihaz/cihaz_ara_screen.dart';
import '../cihaz/cihaz_detay_screen.dart';
import '../cihaz/toplu_giris_screen.dart';
import '../cihaz/toplu_transfer_screen.dart';
import '../../widgets/hedefli_tarayici.dart';
import '../../widgets/kritik_stok_seridi.dart';
import '../../widgets/bildirim_dugmesi.dart';
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
        actions: [
          const BildirimDugmesi(),
          IconButton(
            icon: const Icon(Icons.keyboard),
            tooltip: 'Seri no yazarak ara',
            onPressed: () => _ac(const CihazAraScreen()),
          ),
          IconButton(
            icon: const Icon(Icons.add_box_outlined),
            tooltip: 'Seri no ile depoya giriş',
            onPressed: () => _ac(const TopluGirisScreen()),
          ),
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Toplu transfer',
            onPressed: () => _ac(const TopluTransferScreen()),
          ),
          IconButton(
            icon: const Icon(Icons.flash_on),
            tooltip: 'Flaş',
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Column(
        children: [
          const KritikStokSeridi(),
          Expanded(child: _kamera()),
        ],
      ),
    );
  }

  Widget _kamera() {
    return Stack(
        children: [
          HedefliTarayici(controller: _controller, onDetect: _okundu),
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
