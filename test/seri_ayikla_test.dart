import 'package:depo_app/widgets/kod_yardimci.dart';
import 'package:flutter_test/flutter_test.dart';

/// 1.31.0: barkod türü işareti ("]C1") ve GS1 seri no alanı.
void main() {
  test('başındaki ]C1 atılır (Seyfettin\'in fotoğrafı)', () {
    expect(seriAyikla(']C1FB6637822'), 'FB6637822');
    expect(seriNolariAyir(']C1FB6637822'), ['FB6637822']);
  });

  test('diğer barkod türü işaretleri', () {
    expect(seriAyikla(']C0GA4562378'), 'GA4562378');
    expect(seriAyikla(']Q1GA4562378'), 'GA4562378');
    expect(seriAyikla(']E0'), '');
  });

  test('GS1: 21 seri no alanı ayıklanır', () {
    expect(seriAyikla(']C121GA4562378'), 'GA4562378');
    // 01 (GTIN, 14 hane) + 21 seri no
    expect(seriAyikla(']C10108691234567890' '21GA4562378'), 'GA4562378');
    // 10 (lot, değişken) GS ile biter, sonra 21
    expect(seriAyikla(']d210LOT42\u001D21ABC123456'), 'ABC123456');
    // GS1 ama seri no alanı yok → işaretsiz kod
    expect(seriAyikla(']C110LOT42'), '10LOT42');
  });

  test('görünmez GS karakteri atılır', () {
    expect(seriAyikla('GA4562378\u001D'), 'GA4562378');
  });

  test('eski kurallar bozulmadı', () {
    expect(seriAyikla('S/N:22440W0015776'), '22440W0015776');
    expect(seriAyikla('22440W0015776 EU/3.0'), '22440W0015776');
    expect(seriAyikla('GA4562378'), 'GA4562378');
    expect(seriNolariAyir('GA1\nGA2'), ['GA1', 'GA2']);
    expect(seriNolariAyir(']C1GA834\nGA835'), ['GA834', 'GA835']);
  });
}
