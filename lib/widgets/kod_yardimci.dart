import 'package:flutter/foundation.dart';
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

/// Bilgisayar tarayıcısında (web, telefon dışı) kamera genelde yoktur; seri
/// numarası USB barkod okuyucuyla (klavye gibi yazar) girilir. Telefonda
/// hatalı girişi önlemek için seri no yalnızca kamerayla okutulur.
bool get bilgisayarTarayicisi =>
    kIsWeb &&
    defaultTargetPlatform != TargetPlatform.android &&
    defaultTargetPlatform != TargetPlatform.iOS;
