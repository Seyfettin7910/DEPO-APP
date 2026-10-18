import 'package:mobile_scanner/mobile_scanner.dart';

/// Kamerada görünen barkod/QR kodların benzersiz, boş olmayan değerleri.
/// Birden fazla farklı kod görünüyorsa hangisinin seri numarası olduğu
/// belli olmaz; ekranlar bu durumda kullanıcıyı uyarır.
List<String> okunanKodlar(BarcodeCapture capture) {
  final kodlar = <String>{};
  for (final b in capture.barcodes) {
    final v = b.rawValue;
    if (v != null && v.trim().isNotEmpty) kodlar.add(v.trim());
  }
  return kodlar.toList();
}
