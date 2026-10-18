import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/ses_servisi.dart';
import 'kod_yardimci.dart';

/// Kamerayı açıp bir barkod/QR kod okur ve okunan değeri
/// Navigator.pop ile geri döndürür. Kullanım:
///
///   final kod = await Navigator.of(context).push<String>(
///     MaterialPageRoute(builder: (_) => const BarkodOkuyucuSayfasi()),
///   );
class BarkodOkuyucuSayfasi extends StatefulWidget {
  const BarkodOkuyucuSayfasi({super.key});

  @override
  State<BarkodOkuyucuSayfasi> createState() => _BarkodOkuyucuSayfasiState();
}

class _BarkodOkuyucuSayfasiState extends State<BarkodOkuyucuSayfasi> {
  final _controller = MobileScannerController();
  bool _tamamlandi = false;
  bool _coklu = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _okundu(BarcodeCapture capture) {
    if (_tamamlandi) return;
    final kodlar = okunanKodlar(capture);
    if (kodlar.isEmpty) return;
    if (kodlar.length > 1) {
      // Etikette birden çok barkod var: hangisinin seçileceği belli değil.
      if (!_coklu) setState(() => _coklu = true);
      return;
    }
    if (_coklu) setState(() => _coklu = false);
    final deger = kodlar.first;
    _tamamlandi = true;
    SesServisi.basari();
    Navigator.of(context).pop(deger);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Barkod / QR Oku'),
        actions: [
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
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.all(16),
              child: Text(
                _coklu
                    ? 'Birden çok barkod görünüyor. Yalnızca istediğiniz barkodu çerçeveye alın.'
                    : 'Barkodu veya QR kodu çerçeveye getirin',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _coklu ? Colors.amber : Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
