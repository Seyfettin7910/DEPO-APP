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

  etiketTestleri();
}

// 1.33.0: Seyfettin'in Hikvision monitör kutusu (02.11.2026)
void etiketTestleri() {
  const hikvision = [
    'HIKVISION',
    'Monitor',
    'Model: DS-D5222F2-1V1S',
    'SN: 30174162968',
    'Lot No.: WAZN2570281',
    'Material Code: 317500403',
    'Made in China',
  ];

  group('etiketOku', () {
    test('Hikvision kutusu: SN, lot, malzeme, model ayrılır', () {
      final e = etiketOku(hikvision);
      expect(e.sn, '30174162968');
      expect(e.tur('30174162968'), EtiketKodTuru.seri);
      expect(e.tur('317500403'), EtiketKodTuru.malzeme);
      expect(e.tur('WAZN2570281'), EtiketKodTuru.lot);
      expect(e.tur('DS-D5222F2-1V1S'), EtiketKodTuru.model);
      expect(e.tur('9999999999'), isNull);
    });

    test('yazı tanıma harfleri karıştırsa da barkodla eşleşir', () {
      final e = etiketOku(['SN: 3O174I62968', 'Material Code: 3175OO4O3']);
      expect(e.tur('30174162968'), EtiketKodTuru.seri);
      expect(e.tur('317500403'), EtiketKodTuru.malzeme);
    });

    test('etiket tek başına satırda: değer alt satırda', () {
      final e = etiketOku(['Lot No.', 'WAZN2570281', 'S/N', 'Q2HB12345678']);
      expect(e.tur('WAZN2570281'), EtiketKodTuru.lot);
      expect(e.tur('Q2HB12345678'), EtiketKodTuru.seri);
    });

    test('P/N, Part No, Batch, Model No', () {
      final e = etiketOku([
        'P/N: 1.0.01.24.12345',
        'Part No: 9871234',
        'Batch No: B2025001',
        'Model No.: IPC-HFW1230S',
      ]);
      expect(e.tur('9871234'), EtiketKodTuru.malzeme);
      expect(e.tur('B2025001'), EtiketKodTuru.lot);
      expect(e.tur('IPC-HFW1230S'), EtiketKodTuru.model);
    });

    test('seriAnahtari: büyük harf, boşluksuz, öneksiz', () {
      expect(seriAnahtari('SN: 30174162968'), '30174162968');
      expect(seriAnahtari('s/n 3017 4162968'), '30174162968');
      expect(seriAnahtari('Serial No. Q2HB-ABCD-1234'), 'Q2HB-ABCD-1234');
      expect(seriAnahtari(' ab12 34 '), 'AB1234');
    });

    test('SN yoksa seri bulunmaz; kısa kod eşleşmez', () {
      final e = etiketOku(['Lot No.: AB1', 'Material Code: 317500403']);
      expect(e.sn, isNull);
      expect(e.tur('30174162968'), isNull);
      expect(ayniKod('AB1', 'AB1'), isFalse);
    });
  });
}
