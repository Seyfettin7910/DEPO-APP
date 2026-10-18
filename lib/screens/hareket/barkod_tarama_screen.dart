import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../providers/app_providers.dart';
import '../../services/ses_servisi.dart';
import '../../widgets/kod_yardimci.dart';
import '../cihaz/cihaz_ara_screen.dart';
import '../cihaz/cihaz_detay_screen.dart';
import '../cihaz/toplu_giris_screen.dart';
import '../cihaz/toplu_transfer_screen.dart';

/// Hızlı tarama: seri numarası okutulunca cihazın kartı (hangi ürün, hangi
/// depoda / araçta) açılır. Kayıtlı değilse uyarı sesi + titreşim verir ve
/// "Depoya ekle" önerir.
///
/// Not: mobile_scanner iOS ve Android'de kamera ile doğrudan çalışır.
class BarkodTaramaScreen extends ConsumerStatefulWidget {
  const BarkodTaramaScreen({super.key});

  @override
  ConsumerState<BarkodTaramaScreen> createState() => _BarkodTaramaScreenState();
}

class _BarkodTaramaScreenState extends ConsumerState<BarkodTaramaScreen> {
  final _controller = MobileScannerController();
  bool _mesgul = false;
  bool _coklu = false;
  String? _sonKod;
  DateTime _sonZaman = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _kodBulundu(String kod) async {
    if (_mesgul) return;

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
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TopluGirisScreen(onceSeriNolari: [kod]),
                  ),
                ),
              ),
            ),
          );
        return;
      }

      SesServisi.basari();
      await Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => CihazDetayScreen(cihazId: bilgi.cihaz.id)),
      );
      // Geri dönünce aynı kodu hemen tekrar işlemesin.
      _sonZaman = DateTime.now();
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
        title: const Text('Seri No Tara'),
        actions: [
          IconButton(
            icon: const Icon(Icons.keyboard),
            tooltip: 'Seri no yazarak ara',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CihazAraScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_box_outlined),
            tooltip: 'Seri no ile depoya giriş',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TopluGirisScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Toplu transfer',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TopluTransferScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.flash_on),
            tooltip: 'Flaş',
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _okundu),
          if (_coklu)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                color: Colors.black87,
                padding: const EdgeInsets.all(12),
                child: const Text(
                  'Birden çok barkod görünüyor. Yalnızca seri no barkodunu çerçeveye alın.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.amber),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
