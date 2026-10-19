import 'dart:ui' show Size;

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

final _ayirici = RegExp(r'[\r\n\t,;|]+');
final _bosluk = RegExp(r'\s+');
final _rakam = RegExp(r'\d');

/// Okunan bir koddaki seri numaraları.
///
/// Kolilerin üzerindeki karekod, kolideki bütün cihazların seri numaralarını
/// alt alta (ya da virgül / noktalı virgülle ayrılmış) içerir. Bu durumda her
/// satır ayrı bir seri no olarak döner. Tek seri no içeren kodda tek eleman
/// döner. Sonuç büyük harfe çevrilmiş, tekrarsız ve sıralıdır (koddaki sırayla).
List<String> seriNolariAyir(String kod) {
  var parcalar = kod
      .split(_ayirici)
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  // Yalnızca boşlukla ayrılmış liste: "GA834 GA835 ..." (her parça seri no
  // gibi görünüyorsa). "SN 12345" gibi tek seri no bölünmez.
  if (parcalar.length == 1) {
    final kelimeler = parcalar.first.split(_bosluk);
    if (kelimeler.length > 1 &&
        kelimeler.every((k) => k.length >= 5 && _rakam.hasMatch(k))) {
      parcalar = kelimeler;
    }
  }

  // Birden çok satır varsa, rakam içermeyen satırlar (ör. "Model", firma adı)
  // seri no değildir; atılır.
  if (parcalar.length > 1) {
    final ayiklanan =
        parcalar.where((s) => s.length >= 4 && _rakam.hasMatch(s)).toList();
    if (ayiklanan.isNotEmpty) parcalar = ayiklanan;
  }

  final sonuc = <String>[];
  for (final p in parcalar) {
    final s = p.toUpperCase();
    if (!sonuc.contains(s)) sonuc.add(s);
  }
  return sonuc;
}

/// Tüm tarama ekranları için ortak kamera ayarları.
///
/// - Yüksek çözünürlük: koli karekodları yoğun (çok satır) olduğundan düşük
///   çözünürlükte ancak çok yakından okunur; o mesafede de kamera netleyemez.
///   Yüksek çözünürlükle telefon 15-25 cm uzakta tutulabilir.
/// - Otomatik yakınlaştırma (Android): kod küçük görünüyorsa kamera kendisi
///   yaklaştırır.
MobileScannerController tarayiciOlustur() => MobileScannerController(
      cameraResolution: const Size(1920, 1080),
      autoZoom: true,
      detectionSpeed: DetectionSpeed.normal,
      detectionTimeoutMs: 250,
    );

/// Bilgisayar tarayıcısında (web, telefon dışı) kamera genelde yoktur; seri
/// numarası USB barkod okuyucuyla (klavye gibi yazar) girilir. Telefonda
/// hatalı girişi önlemek için seri no yalnızca kamerayla okutulur.
bool get bilgisayarTarayicisi =>
    kIsWeb &&
    defaultTargetPlatform != TargetPlatform.android &&
    defaultTargetPlatform != TargetPlatform.iOS;
