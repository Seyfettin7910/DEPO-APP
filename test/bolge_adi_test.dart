import 'package:depo_app/services/rapor/rapor_olusturucu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('büyük / küçük harf farkı birleşir', () {
    expect(bolgeAdiDuzelt('KULAT'), 'Kulat');
    expect(bolgeAdiDuzelt('Kulat'), 'Kulat');
    expect(bolgeAdiDuzelt('  kulat '), 'Kulat');
  });

  test('Mahallesi / Mah. / Köyü ekleri atılır', () {
    expect(bolgeAdiDuzelt('1. Sakarya Mahallesi'), '1. Sakarya');
    expect(bolgeAdiDuzelt('Sakarya Mah.'), 'Sakarya');
    expect(bolgeAdiDuzelt('Kayalar Köyü'), 'Kayalar');
    expect(bolgeAdiDuzelt('ÖMERKÖY MAHALLESİ'), 'Ömerköy');
  });

  test('Türkçe harfler', () {
    expect(bolgeAdiDuzelt('İSMETPAŞA'), 'İsmetpaşa');
    expect(bolgeAdiDuzelt('ılıca'), 'Ilıca');
  });

  test('boş', () {
    expect(bolgeAdiDuzelt(null), '');
    expect(bolgeAdiDuzelt('   '), '');
  });
}
