import 'package:depo_app/services/sn_metni.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('snAyikla', () {
    test('S/N: değer aynı satırda', () {
      expect(snAyikla(['Model: DS-2CD1043G0-I', 'S/N: E12345678']),
          'E12345678');
    });
    test('yazı tanıma / işaretini I ya da 1 okursa', () {
      expect(snAyikla(['SIN: K98765432']), 'K98765432');
      expect(snAyikla(['S1N:AB12CD34']), 'AB12CD34');
      expect(snAyikla(['5/N F4455667']), 'F4455667');
    });
    test('SN, S.N., Serial No, Seri No', () {
      expect(snAyikla(['SN:Q2HB-ABCD-1234']), 'Q2HB-ABCD-1234');
      expect(snAyikla(['S.N. 2104556677']), '2104556677');
      expect(snAyikla(['Serial No.: ab12345678']), 'AB12345678');
      expect(snAyikla(['Serial Number 9X8Y7Z6W']), '9X8Y7Z6W');
      expect(snAyikla(['SERİ NO: TR00123456']), 'TR00123456');
      expect(snAyikla(['Seri No TR00123456']), 'TR00123456');
    });
    test('aynı satırda başka bilgiler', () {
      expect(snAyikla(['P/N: 1234-567  S/N: ZX12345  Made in China']),
          'ZX12345');
    });
    test('etiket tek başına satırda: değer alt satırda', () {
      expect(snAyikla(['S/N', 'G20231105AAWR', 'MAC: 00:11:22']),
          'G20231105AAWR');
    });
    test('etiketsiz satır alınmaz', () {
      expect(snAyikla(['E12345678', 'DS-2CD1043G0-I']), isNull);
      expect(snAyikla(['P/N: 1234567890']), isNull);
      expect(snAyikla(['SNMP v3 enabled']), isNull);
      expect(snAyikla(['ASN 123456789']), isNull);
    });
    test('çok kısa ya da rakamsız değer alınmaz', () {
      expect(snAyikla(['S/N: AB12']), isNull);
      expect(snAyikla(['S/N: ABCDEFGH']), isNull);
    });
    test('sondaki tire atılır', () {
      expect(snAyikla(['S/N: AB123456-']), 'AB123456');
    });
  });
}
