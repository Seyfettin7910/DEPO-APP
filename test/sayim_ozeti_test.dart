import 'package:depo_app/services/sayim_ozeti.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const nvr = 'HIKVISION 7104 POE 4 KANAL';
  const kamera = 'HIKVISION DS-2CD2T46G2-2I 4 MM BULLET KAMERA';
  const monitor = 'LG MONİTÖR 22"';

  final beklenen = [
    ('N1', nvr), ('N2', nvr), ('N3', nvr), ('N4', nvr),
    ('K1', kamera), ('K2', kamera),
    ('M1', monitor),
  ];

  test('Model bazında olmalı / bulunan / eksik / fazla', () {
    final g = sayimOzeti(beklenen: beklenen, okunan: {
      'N1': nvr,
      'K1': kamera,
      'K2': kamera,
      'M1': monitor,
      'X9': kamera, // başka yerde kayıtlı kamera: fazla
      'Y7': null, // kayıtsız: fazla
    });
    final adlar = [for (final x in g) x.urunAdi];
    // Eksiği en çok olan en üstte; sonra fazlası çok olan; sonra ada göre.
    expect(adlar.first, nvr);
    expect(adlar, containsAll([kamera, monitor, sayimKayitsizBasligi]));

    final n = g.firstWhere((x) => x.urunAdi == nvr);
    expect(n.olmali, ['N1', 'N2', 'N3', 'N4']);
    expect(n.bulunan, ['N1']);
    expect(n.eksik, ['N2', 'N3', 'N4']);
    expect(n.fazla, isEmpty);
    expect(n.tamam, isFalse);

    final k = g.firstWhere((x) => x.urunAdi == kamera);
    expect(k.bulunan, ['K1', 'K2']);
    expect(k.eksik, isEmpty);
    expect(k.fazla, ['X9']);
    expect(k.tamam, isFalse);
    expect(adlar.indexOf(kamera), 1, reason: 'fazlası olan, tamam olandan önce');

    final m = g.firstWhere((x) => x.urunAdi == monitor);
    expect(m.tamam, isTrue);

    final kayitsiz = g.firstWhere((x) => x.urunAdi == sayimKayitsizBasligi);
    expect(kayitsiz.olmali, isEmpty);
    expect(kayitsiz.fazla, ['Y7']);
  });

  test('Hiç okutma yokken hepsi eksik', () {
    final g = sayimOzeti(beklenen: beklenen, okunan: {});
    expect(g.fold<int>(0, (t, x) => t + x.eksik.length), beklenen.length);
    expect(g.fold<int>(0, (t, x) => t + x.bulunan.length), 0);
    expect(g.first.urunAdi, nvr);
  });

  test('Boş konum', () {
    expect(sayimOzeti(beklenen: const [], okunan: {}), isEmpty);
  });

  test('Arama: seri no ve model; harf / boşluk farkı önemsiz', () {
    expect(sayimAramaUyar('', seri: 'GB0269481', urun: nvr), isTrue);
    expect(sayimAramaUyar('gb026', seri: 'GB0269481', urun: nvr), isTrue);
    expect(sayimAramaUyar('7104 poe', seri: 'GB0269481', urun: nvr), isTrue);
    expect(sayimAramaUyar('monitor', seri: 'M1', urun: monitor), isTrue);
    expect(sayimAramaUyar('kamera', seri: 'GB0269481', urun: nvr), isFalse);
    expect(sayimAramaUyar('999', seri: 'GB0269481', urun: nvr), isFalse);
  });
}
