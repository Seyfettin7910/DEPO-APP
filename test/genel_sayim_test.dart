import 'package:depo_app/services/genel_sayim.dart';
import 'package:depo_app/services/sayim_ozeti.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const nvr = 'HIKVISION 7104 POE 4 KANAL';
  const kamera = 'HIKVISION DS-2CD2T46G2-2I 4 MM BULLET KAMERA';

  final yerler = <SayimYeri>[
    ('d1', 'TERMİNAL', false),
    ('d2', 'MUSTAFA', false),
    ('d3', 'ORGANİZE', false),
    ('a1', '10 AFB 261', true),
  ];

  SayimKaydi kayit(String id, String ad, int gun, SayimIcerigi icerik,
          {String? kim}) =>
      SayimKaydi(
        depoId: id,
        depoAdi: ad,
        tarih: DateTime(2026, 11, gun, 10),
        kullanici: kim,
        icerik: icerik,
      );

  test('Yeri yanlış kayıtlı cihaz kendi yerindeki eksikten düşülür', () {
    final g = genelSayim(yerler: yerler, kayitlar: [
      kayit('d1', 'TERMİNAL', 3, const SayimIcerigi(
        bulunan: [('N1', nvr), ('N2', nvr)],
        eksik: [('N3', nvr), ('N4', nvr)],
        fazla: [('K9', kamera, 'Sistemde: MUSTAFA'), ('Y7', null, 'Sistemde kayıtlı değil')],
        malzeme: [('CAT 6 KABLO', 'metre', 305, 300), ('PRİZ', 'adet', 4, 4)],
      ), kim: 'Ahmet'),
      kayit('d2', 'MUSTAFA', 3, const SayimIcerigi(
        bulunan: [('K1', kamera)],
        eksik: [('K9', kamera)],
      )),
      kayit('a1', '10 AFB 261', 3, const SayimIcerigi(
        fazla: [('N3', nvr, 'Sistemde: TERMİNAL')],
      )),
    ]);

    expect(g.sayilanYer, 3);
    expect(g.yerler.length, 4);
    // Sayılmayan yer en sonda.
    expect(g.yerler.last.yer.$2, 'ORGANİZE');
    expect(g.yerler.last.kayit, isNull);
    // Sayılan depolar önce (ada göre), araç sonra.
    expect([for (final y in g.yerler) y.yer.$2],
        ['MUSTAFA', 'TERMİNAL', '10 AFB 261', 'ORGANİZE']);

    // K9 MUSTAFA'da eksik, TERMİNAL'de fazla → yeri yanlış, eksik değil.
    // N3 TERMİNAL'de eksik, araçta fazla → yeri yanlış.
    expect([for (final y in g.yeriYanlis) y.seri]..sort(), ['K9', 'N3']);
    expect(g.yeriYanlis.every((y) => y.kendiYerindeEksik), isTrue);
    final k9 = g.yeriYanlis.firstWhere((y) => y.seri == 'K9');
    expect(k9.bulunduguYer, 'TERMİNAL');
    expect(k9.sistemdekiYer, 'Sistemde: MUSTAFA');

    // Gerçek eksik yalnız N4.
    expect(g.eksikler, [('N4', nvr, 'TERMİNAL')]);
    expect(g.kayitsizlar, [('Y7', 'TERMİNAL')]);

    final terminal = g.yerler.firstWhere((y) => y.yer.$1 == 'd1');
    expect(terminal.olmali, 4);
    expect(terminal.bulunan, 2);
    expect(terminal.eksik, 1, reason: 'N3 araçta bulundu');
    expect(terminal.fazla, 2);
    expect(terminal.kayit!.kullanici, 'Ahmet');
    final mustafa = g.yerler.firstWhere((y) => y.yer.$1 == 'd2');
    expect(mustafa.eksik, 0);

    final m = g.modeller.firstWhere((x) => x.urun == nvr);
    expect((m.olmali, m.bulunan, m.eksik, m.yeriYanlis), (4, 2, 1, 1));
    final k = g.modeller.firstWhere((x) => x.urun == kamera);
    expect((k.olmali, k.bulunan, k.eksik, k.yeriYanlis), (2, 1, 0, 1));
    expect(g.modeller.first.urun, nvr, reason: 'eksiği çok olan üstte');

    // Yalnız farkı olan malzeme.
    expect(g.malzemeFarklari, [('TERMİNAL', 'CAT 6 KABLO', 'metre', 305, 300)]);
    expect(g.olmali, 6);
    expect(g.bulunan, 3);
  });

  test('Aynı yer iki kez sayıldıysa sonuncusu geçerli', () {
    final g = genelSayim(yerler: yerler, kayitlar: [
      kayit('d1', 'TERMİNAL', 4, const SayimIcerigi(
          bulunan: [('N1', nvr), ('N2', nvr)])),
      kayit('d1', 'TERMİNAL', 2, const SayimIcerigi(
          bulunan: [('N1', nvr)], eksik: [('N2', nvr)])),
    ]);
    final t = g.yerler.firstWhere((y) => y.yer.$1 == 'd1');
    expect(t.kayit!.tarih.day, 4);
    expect(t.eksik, 0);
    expect(g.eksikler, isEmpty);
  });

  test('Fazla çıkan cihazın kendi yeri sayılmadıysa yine yeri yanlış', () {
    final g = genelSayim(yerler: yerler, kayitlar: [
      kayit('d1', 'TERMİNAL', 3, const SayimIcerigi(
          fazla: [('K5', kamera, 'Sistemde: montaj yapıldı (KULAT)')])),
    ]);
    expect(g.yeriYanlis.single.kendiYerindeEksik, isFalse);
    expect(g.eksikler, isEmpty);
  });

  test('Silinmiş depo sayımı da görünür', () {
    final g = genelSayim(yerler: yerler, kayitlar: [
      kayit('eski', 'ESKİ DEPO', 3,
          const SayimIcerigi(bulunan: [('N1', nvr)])),
    ]);
    expect(g.yerler.any((y) => y.yer.$2 == 'ESKİ DEPO' && y.kayit != null),
        isTrue);
  });

  test('İçerik JSON: yaz / oku, bozuk içerik çökertmez', () {
    const ic = SayimIcerigi(
      bulunan: [('N1', nvr)],
      eksik: [('N2', nvr)],
      fazla: [('Y7', null, 'Sistemde kayıtlı değil'), ('K9', kamera, 'Sistemde: MUSTAFA')],
      malzeme: [('KABLO', 'metre', 305, null), ('PRİZ', 'adet', 4, 3)],
    );
    final geri = SayimIcerigi.coz(ic.json());
    expect(geri.bulunan, ic.bulunan);
    expect(geri.eksik, ic.eksik);
    expect(geri.fazla, ic.fazla);
    expect(geri.malzeme, ic.malzeme);
    expect(SayimIcerigi.coz('bozuk{').bulunan, isEmpty);
    expect(SayimIcerigi.coz(null).fazla, isEmpty);
  });

  test('Sayım ekranındaki gruplardan içerik', () {
    final gruplar = sayimOzeti(
      beklenen: [('N1', nvr), ('N2', nvr)],
      okunan: {'N1': nvr, 'K9': kamera, 'Y7': null},
    );
    final ic = sayimIcerigi(
      gruplar: gruplar,
      sistemdekiYer: (s) => s == 'Y7' ? 'Sistemde kayıtlı değil' : 'Sistemde: MUSTAFA',
    );
    expect(ic.bulunan, [('N1', nvr)]);
    expect(ic.eksik, [('N2', nvr)]);
    expect(ic.fazla, containsAll([
      ('K9', kamera, 'Sistemde: MUSTAFA'),
      ('Y7', null, 'Sistemde kayıtlı değil'),
    ]));
  });
}
