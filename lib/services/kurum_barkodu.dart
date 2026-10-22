/// Kurum içi malzeme barkodu (1.30.2): fabrika barkodu olmayan, metre / adet
/// ile takip edilen malzemeler için EAN-13.
///
/// - EAN-13'ün 200–299 önekleri uluslararası kuralda (GS1) kurum içi
///   kullanıma ayrılmıştır; hiçbir gerçek ürünün barkodu bunlarla başlamaz.
///   Önek **266** (Balıkesir alan kodu); 27–29 (tartılı ürün etiketleri)
///   aralığından uzak.
/// - Biçim: 266 + 9 haneli rastgele sayı + 1 kontrol hanesi = 13 hane.
///   Rastgele olduğu için iki telefon internetsizken aynı kodu üretmez
///   (1 milyar olasılık); üretilirken ayrıca veritabanında denetlenir.
/// Testleri: test/kurum_barkodu_test.dart.
library;

import 'dart:math';

const kurumBarkoduOneki = '266';

final _onIkiHane = RegExp(r'^\d{12}$');
final _onUcHane = RegExp(r'^\d{13}$');

/// EAN-13 kontrol hanesi (ilk 12 haneden).
String ean13KontrolHanesi(String ilk12) {
  if (!_onIkiHane.hasMatch(ilk12)) {
    throw ArgumentError('12 hane gerekli: $ilk12');
  }
  var toplam = 0;
  for (var i = 0; i < 12; i++) {
    final h = ilk12.codeUnitAt(i) - 48;
    toplam += i.isEven ? h : h * 3;
  }
  return '${(10 - toplam % 10) % 10}';
}

bool ean13Gecerli(String kod) =>
    _onUcHane.hasMatch(kod) &&
    ean13KontrolHanesi(kod.substring(0, 12)) == kod.substring(12);

/// Bizim ürettiğimiz kurum içi barkod mu (266 ile başlayan geçerli EAN-13)?
bool kurumBarkoduMu(String kod) {
  final k = kod.trim();
  return k.startsWith(kurumBarkoduOneki) && ean13Gecerli(k);
}

/// Yeni kurum içi barkod (benzersizliği çağıran denetler).
String kurumBarkoduUret([Random? rastgele]) {
  final r = rastgele ?? Random.secure();
  final govde = kurumBarkoduOneki +
      List.generate(12 - kurumBarkoduOneki.length, (_) => r.nextInt(10)).join();
  return govde + ean13KontrolHanesi(govde);
}
