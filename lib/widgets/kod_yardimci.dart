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
  var parcalar = seriAyikla(kod)
      .split(_ayirici)
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  // Yalnızca boşlukla ayrılmış liste: "GA834 GA835 ..." (her parça seri no
  // gibi görünüyorsa). "SN 12345" gibi tek seri no bölünmez.
  if (parcalar.length == 1) {
    final kelimeler = parcalar.first.split(_bosluk);
    if (kelimeler.length > 1 &&
        kelimeler.every((k) =>
            k.length >= 5 && _rakam.hasMatch(k) && !k.contains('/'))) {
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
/// - Otomatik yakınlaştırma KAPALI (1.27.2): ani yakınlaşıp uzaklaşması (ve
///   telefonun zoom kamerasına geçmesi) okumayı bozuyordu. Kamera 2x sabit
///   açılır; alttaki 1x · 2x · 3x seçiciyle değiştirilir (HedefliTarayici).
MobileScannerController tarayiciOlustur() => MobileScannerController(
      cameraResolution: const Size(1920, 1080),
      autoZoom: false,
      detectionSpeed: DetectionSpeed.normal,
      // Küçük / sık çizgili barkodlar için saniyede daha çok deneme
      detectionTimeoutMs: 120,
    );

/// Bilgisayar tarayıcısında (web, telefon dışı) kamera genelde yoktur; seri
/// numarası USB barkod okuyucuyla (klavye gibi yazar) girilir. Telefonda
/// hatalı girişi önlemek için seri no yalnızca kamerayla okutulur.
bool get bilgisayarTarayicisi =>
    kIsWeb &&
    defaultTargetPlatform != TargetPlatform.android &&
    defaultTargetPlatform != TargetPlatform.iOS;

final _macAdresi = RegExp(r'^([0-9A-F]{2}[:\-]){5}[0-9A-F]{2}$');
// Ayırıcısız MAC (ör. B039566EE07D): 12 onaltılık karakter, harf + rakam
final _macDuz = RegExp(r'^(?=.*[A-F])(?=.*\d)[0-9A-F]{12}$');
final _yalnizRakam = RegExp(r'^\d+$');

/// Kutu üstündeki ürün barkodu türleri (EAN / UPC). Seri no ya da kurum
/// etiketi olmaz; yalnızca malzemenin fabrika barkodu olabilir.
bool urunBarkoduTuru(Barcode b) =>
    b.format == BarcodeFormat.ean13 ||
    b.format == BarcodeFormat.ean8 ||
    b.format == BarcodeFormat.upcA ||
    b.format == BarcodeFormat.upcE;

/// Seri no / kurum etiketi / koli karekodu olamayacak kodlar: web adresi,
/// Wi-Fi, kartvizit, telefon, e-posta, MAC adresi, çok kısa kod. Bunlar
/// okutma ekranlarında yok sayılır.
bool gereksizKod(String deger) => gereksizSebep(deger) != null;

/// Kod neden yok sayılır (ekranda kısa ipucu olarak gösterilir); okunacaksa
/// null.
String? gereksizSebep(String deger) {
  final v = deger.trim();
  if (v.length < 4) return 'çok kısa';
  final k = v.toUpperCase();
  const adresler = ['HTTP://', 'HTTPS://', 'WWW.'];
  if (adresler.any(k.startsWith)) return 'web adresi';
  if (k.startsWith('WIFI:')) return 'Wi-Fi';
  const digerleri = [
    'MAILTO:', 'TEL:', 'SMSTO:', 'SMS:', 'MATMSG:', 'MECARD:', 'BEGIN:VCARD',
    'BEGIN:VEVENT', 'GEO:',
  ];
  if (digerleri.any(k.startsWith)) return 'iletişim bilgisi';
  if (k.startsWith('MAC:') || k.startsWith('MAC ') ||
      _macAdresi.hasMatch(k) || _macDuz.hasMatch(k)) {
    return 'MAC adresi';
  }
  // Sipariş no (3000527901/10), "@722363267 ..." gibi kutu kodları
  if (k.contains('/') || k.startsWith('@')) return 'sipariş / kutu kodu';
  return null;
}

final _seriOnEki = RegExp(
    r'^(?:(?:S\s*/\s*N|SN|SERIAL\s*(?:NO\.?|NUMBER)?)\s*[:#.]\s*|S\s*/\s*N\s+)',
    caseSensitive: false);
final _bosluklar = RegExp(r'\s+');

/// Barkodun içindeki seri noyu ayıklar: "S/N:22440W0015776" → seri no;
/// "22440W0015776 EU/3.0" gibi sonda ek bilgi varsa yalnızca seri no.
/// Çok satırlı (koli) kodlara dokunmaz.
String seriAyikla(String deger) {
  var s = deger.trim();
  if (s.contains('\n') || s.contains('\r')) return s;
  s = s.replaceFirst(_seriOnEki, '').trim();
  if (s.contains(' ')) {
    final p = s.split(_bosluklar);
    final ilk = p.first;
    if (ilk.length >= 5 &&
        _rakam.hasMatch(ilk) &&
        !ilk.contains('/') &&
        p.skip(1).every((x) => x.contains('/') || x.length <= 4)) {
      return ilk;
    }
  }
  return s;
}

/// Seri no olabilir ama çoğu zaman değildir: yalnızca rakamdan oluşan kodlar
/// (malzeme kodu, lot no, IMEI) ve tire / boşluk içeren kodlar (model,
/// parça no: GS1300-10HP-EU0101F). Okut ekranında yalnızca sistemde
/// kayıtlıysa okunur; diğer ekranlarda daha uzun sabit tutulması gerekir.
bool supheliKod(String deger) {
  final v = deger.trim();
  return _yalnizRakam.hasMatch(v) || v.contains('-') || v.contains(' ');
}
