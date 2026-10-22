import 'package:depo_app/services/urun_adi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('İ / I farkı yok sayılır', () {
    expect(urunAdiAnahtari('HİKVİSİON 7104 POE 4 KANAL NVR'),
        urunAdiAnahtari('HIKVISION 7104 POE 4 KANAL NVR'));
  });
  test('büyük / küçük harf, boşluk, tire', () {
    expect(urunAdiAnahtari('Hikvision 7104-POE  4 Kanal NVR'),
        urunAdiAnahtari('HIKVISION 7104 POE 4 KANAL NVR'));
  });
  test('Türkçe harfler', () {
    expect(urunAdiAnahtari('3X2,5 ELEKTRİK KABLOSU'),
        urunAdiAnahtari('3x2.5 Elektrik Kablosu'));
    expect(urunAdiAnahtari('Çağrı Ünitesi'), 'CAGRIUNITESI');
  });
  test('farklı ürünler ayrı', () {
    expect(urunAdiAnahtari('HIKVISION 7104 NVR') ==
        urunAdiAnahtari('HIKVISION 7108 NVR'), isFalse);
  });
}
