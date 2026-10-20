import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/ses_servisi.dart';
import 'kod_yardimci.dart';
import 'hedefli_tarayici.dart';

/// Kamerayı açıp bir barkod/QR kod okur ve okunan değeri
/// Navigator.pop ile geri döndürür. Kullanım:
///
///   final kod = await Navigator.of(context).push<String>(
///     MaterialPageRoute(builder: (_) => const BarkodOkuyucuSayfasi()),
///   );
class BarkodOkuyucuSayfasi extends StatefulWidget {
  const BarkodOkuyucuSayfasi({super.key, this.urunBarkodu = false});

  /// true: kutu üstündeki ürün barkodları (EAN / UPC) da okunur (malzemenin
  /// fabrika barkodu).
  final bool urunBarkodu;

  @override
  State<BarkodOkuyucuSayfasi> createState() => _BarkodOkuyucuSayfasiState();
}

class _BarkodOkuyucuSayfasiState extends State<BarkodOkuyucuSayfasi> {
  final _controller = tarayiciOlustur();
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
          HedefliTarayici(
              controller: _controller,
              onDetect: _okundu,
              urunBarkodu: widget.urunBarkodu),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.all(16),
              child: Text(
                _coklu
                    ? 'Çerçevede birden çok kod var. Telefonu yaklaştırıp yalnızca istediğiniz kodu çerçeveye alın.'
                    : 'Okutmak istediğiniz kodu yeşil çerçevenin içine alın',
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
