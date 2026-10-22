/// Ürün adlarını karşılaştırma anahtarı (1.29.3): büyük / küçük harf, Türkçe
/// harfler (İ / I / ı, Ç / C, Ğ / G, Ö / O, Ş / S, Ü / U), boşluk ve
/// noktalama farkı yok sayılır. "HİKVİSİON 7104 POE 4 KANAL NVR" ile
/// "Hikvision 7104-POE 4 Kanal NVR" aynı anahtarı verir.
/// Testleri: test/urun_adi_test.dart.
library;

const _harf = {
  'İ': 'I', 'ı': 'I', 'i': 'I', 'Ç': 'C', 'ç': 'C', 'Ğ': 'G', 'ğ': 'G',
  'Ö': 'O', 'ö': 'O', 'Ş': 'S', 'ş': 'S', 'Ü': 'U', 'ü': 'U',
};
final _harfRakam = RegExp(r'[A-Z0-9]');

String urunAdiAnahtari(String ad) {
  final b = StringBuffer();
  for (final ch in ad.split('')) {
    final c = _harf[ch] ?? ch.toUpperCase();
    if (_harfRakam.hasMatch(c)) b.write(c);
  }
  return b.toString();
}
