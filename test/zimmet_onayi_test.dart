import 'package:depo_app/services/zimmet_onayi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('zimmetDeposuMu', () {
    test('Belediye Zimmeti deposu tanınır (harf / boşluk farkı önemsiz)', () {
      expect(zimmetDeposuMu('BELEDİYE ZİMMETİ'), isTrue);
      expect(zimmetDeposuMu('Belediye Zimmeti'), isTrue);
      expect(zimmetDeposuMu('BELEDIYE ZIMMETI'), isTrue);
      expect(zimmetDeposuMu('  belediye   zimmeti  '), isTrue);
      expect(zimmetDeposuMu('BELEDİYE ZİMMETİ DEPOSU'), isTrue);
    });

    test('Diğer depolar sayılmaz', () {
      expect(zimmetDeposuMu(null), isFalse);
      expect(zimmetDeposuMu(''), isFalse);
      expect(zimmetDeposuMu('ANA DEPO'), isFalse);
      expect(zimmetDeposuMu('BELEDİYE'), isFalse);
      expect(zimmetDeposuMu('ZİMMET'), isFalse);
      expect(zimmetDeposuMu('34 ABC 123'), isFalse);
    });
  });

  group('zimmetSecimiHatasi', () {
    test('Zimmet dışı üründe hiçbir şey sorulmaz', () {
      expect(zimmetSecimiHatasi(zimmet: false), isNull);
    });

    test('Zimmette yer seçilmeden kaydedilemez', () {
      expect(zimmetSecimiHatasi(zimmet: true), isNotNull);
      expect(zimmetSecimiHatasi(zimmet: true, yer: 'baska'), isNotNull);
    });

    test('Belediye hizmet yeri: evrak gerekmez', () {
      expect(zimmetSecimiHatasi(zimmet: true, yer: zimmetYeriHizmet), isNull);
    });

    test('Kırsal mahalle: evrak sayısı zorunlu', () {
      expect(zimmetSecimiHatasi(zimmet: true, yer: zimmetYeriKirsal), isNotNull);
      expect(
          zimmetSecimiHatasi(
              zimmet: true, yer: zimmetYeriKirsal, evrakSayisi: '   '),
          isNotNull);
      expect(
          zimmetSecimiHatasi(
              zimmet: true,
              yer: zimmetYeriKirsal,
              evrakSayisi: 'E-12345678-010.06-1234'),
          isNull);
    });
  });

  test('Rapordaki adlar', () {
    expect(zimmetYeriAdi(zimmetYeriHizmet), 'Belediye hizmet yeri');
    expect(zimmetYeriAdi(zimmetYeriKirsal), contains('Kırsal'));
    expect(zimmetYeriAdi(null), '');
  });
}
