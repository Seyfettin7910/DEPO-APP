import 'package:depo_app/database/app_database.dart' show mesafeMetre;
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

  test('konumdan yer: İLÇE MAHALLE', () {
    expect(yerMetni('Susurluk', 'Kulat Mahallesi'), 'SUSURLUK KULAT');
    expect(yerMetni('Karesi', '1. Sakarya Mah.'), 'KARESİ 1. SAKARYA');
    expect(yerMetni(null, 'Kayalar Köyü'), 'KAYALAR');
    expect(yerMetni('', ''), '');
  });

  test('mesafe (15 m sınırı)', () {
    // ~0.0001 derece enlem ≈ 11 m
    final m = mesafeMetre(39.9, 28.1, 39.9001, 28.1);
    expect(m, closeTo(11.1, 0.5));
    expect(mesafeMetre(39.9, 28.1, 39.9002, 28.1) > 15, isTrue);
  });
}
