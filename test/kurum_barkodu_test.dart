import 'dart:math';

import 'package:depo_app/services/kurum_barkodu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EAN-13 kontrol hanesi (bilinen barkodlar)', () {
    expect(ean13KontrolHanesi('400638133393'), '1'); // 4006381333931
    expect(ean13Gecerli('4006381333931'), isTrue);
    expect(ean13Gecerli('8690504000017'), isFalse); // son hane yanlış
    expect(ean13Gecerli('869050400001'), isFalse); // 12 hane
  });

  test('üretilen kod: 266 ile başlar, 13 hane, geçerli', () {
    final r = Random(7);
    for (var i = 0; i < 200; i++) {
      final k = kurumBarkoduUret(r);
      expect(k.length, 13);
      expect(k.startsWith('266'), isTrue);
      expect(ean13Gecerli(k), isTrue);
      expect(kurumBarkoduMu(k), isTrue);
    }
  });

  test('fabrika barkodu kurum kodu sayılmaz', () {
    expect(kurumBarkoduMu('4006381333931'), isFalse);
    expect(kurumBarkoduMu('2661234567890'), isFalse); // kontrol hanesi yanlış
  });

  test('tek hane hatası yakalanır', () {
    final k = kurumBarkoduUret(Random(1));
    final son = int.parse(k[5]);
    final bozuk = k.substring(0, 5) + '${(son + 1) % 10}' + k.substring(6);
    expect(ean13Gecerli(bozuk), isFalse);
  });
}
