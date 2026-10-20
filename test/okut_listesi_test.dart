import 'package:depo_app/services/okut_listesi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('İşlem seçilmeden okutma', () {
    test('kayıtlı cihaz → kart açılır', () {
      final l = OkutListesi();
      expect(l.okut('A1', kayitli: true), OkutSonucu.kartAc);
      expect(l.aktif, isFalse);
      expect(l.bos, isTrue);
    });

    test('1. kayıtsız → uyarı, liste başlamaz', () {
      final l = OkutListesi();
      expect(l.okut('K1', kayitli: false), OkutSonucu.ilkKayitsiz);
      expect(l.aktif, isFalse);
      expect(l.ilkKayitsiz, 'K1');
      expect(l.kalan, 100);
    });

    test('aynı kayıtsız iki kez → başlamaz', () {
      final l = OkutListesi();
      l.okut('K1', kayitli: false);
      expect(l.okut('K1', kayitli: false), OkutSonucu.ilkKayitsiz);
      expect(l.aktif, isFalse);
    });

    test('2 kayıtsız arka arkaya → arka arkaya okutma başlar, ikisi listede', () {
      final l = OkutListesi();
      l.okut('K1', kayitli: false);
      expect(l.okut('K2', kayitli: false), OkutSonucu.topluBasladi);
      expect(l.islem, OkutIslemi.giris);
      expect(l.seriler, ['K1', 'K2']);
      expect(l.kalan, 98);
    });

    test('başladıktan sonra kayıtlı → atlanır', () {
      final l = OkutListesi();
      l.okut('K1', kayitli: false);
      l.okut('K2', kayitli: false);
      expect(l.okut('A1', kayitli: true), OkutSonucu.atlandiKayitli);
      expect(l.seriler, ['K1', 'K2']);
      expect(l.okut('K3', kayitli: false), OkutSonucu.eklendi);
      expect(l.kalan, 97);
    });

    test('1. kayıtsızdan sonra kayıtlı → sorulur; Atla ile devam', () {
      final l = OkutListesi();
      l.okut('K1', kayitli: false);
      expect(l.okut('A1', kayitli: true), OkutSonucu.sor);
      // Atla: hiçbir şey değişmez, sonraki kayıtsız listeyi başlatır.
      expect(l.okut('K2', kayitli: false), OkutSonucu.topluBasladi);
      expect(l.seriler, ['K1', 'K2']);
    });

    test('1. kayıtsızdan sonra kayıtlı → Kartı aç: sayma baştan', () {
      final l = OkutListesi();
      l.okut('K1', kayitli: false);
      expect(l.okut('A1', kayitli: true), OkutSonucu.sor);
      l.saymayiSifirla();
      expect(l.okut('K2', kayitli: false), OkutSonucu.ilkKayitsiz);
      expect(l.aktif, isFalse);
    });

    test('Temizle → normale döner, kayıtlı yine kart açar', () {
      final l = OkutListesi();
      l.okut('K1', kayitli: false);
      l.okut('K2', kayitli: false);
      l.temizle();
      expect(l.aktif, isFalse);
      expect(l.bos, isTrue);
      expect(l.okut('A1', kayitli: true), OkutSonucu.kartAc);
    });
  });

  group('Hızlı işlem seçiliyken', () {
    test('Depoya giriş: kayıtsız girer, kayıtlı liste dışı', () {
      final l = OkutListesi()..islemSec(OkutIslemi.giris);
      expect(l.kalan, 100);
      expect(l.okut('K1', kayitli: false), OkutSonucu.eklendi);
      expect(l.okut('A1', kayitli: true), OkutSonucu.atlandiKayitli);
      expect(l.seriler, ['K1']);
    });

    for (final i in [OkutIslemi.transfer, OkutIslemi.yukle, OkutIslemi.montaj]) {
      test('${i.name}: kayıtlı girer, kayıtsız liste dışı', () {
        final l = OkutListesi()..islemSec(i);
        expect(l.okut('A1', kayitli: true), OkutSonucu.eklendi);
        expect(l.okut('K1', kayitli: false), OkutSonucu.atlandiKayitsiz);
        expect(l.seriler, ['A1']);
        expect(l.kalan, 99);
      });
    }

    test('aynı seri no iki kez girmez', () {
      final l = OkutListesi()..islemSec(OkutIslemi.transfer);
      l.okut('A1', kayitli: true);
      expect(l.okut('A1', kayitli: true), OkutSonucu.zatenListede);
      expect(l.seriler.length, 1);
    });

    test('bekleyen 1. kayıtsız Depoya girişe dokununca listeye alınır', () {
      final l = OkutListesi();
      l.okut('K1', kayitli: false);
      l.islemSec(OkutIslemi.giris);
      expect(l.seriler, ['K1']);
      expect(l.ilkKayitsiz, isNull);
    });

    test('✕ ile çıkarılınca sayaç artar', () {
      final l = OkutListesi()..islemSec(OkutIslemi.montaj);
      l.okut('A1', kayitli: true);
      l.okut('A2', kayitli: true);
      expect(l.kalan, 98);
      l.cikar('A1');
      expect(l.kalan, 99);
      expect(l.seriler, ['A2']);
    });
  });

  group('Sınır 100', () {
    test('100. kayıttan sonra dolu', () {
      final l = OkutListesi()..islemSec(OkutIslemi.transfer);
      for (var i = 0; i < 100; i++) {
        expect(l.okut('A$i', kayitli: true), OkutSonucu.eklendi);
      }
      expect(l.kalan, 0);
      expect(l.okut('A100', kayitli: true), OkutSonucu.dolu);
      expect(l.seriler.length, 100);
    });

    test('2 kayıtsızla başlayan liste de 100de durur', () {
      final l = OkutListesi();
      l.okut('K0', kayitli: false);
      l.okut('K1', kayitli: false);
      for (var i = 2; i < 100; i++) {
        l.okut('K$i', kayitli: false);
      }
      expect(l.kalan, 0);
      expect(l.okut('K100', kayitli: false), OkutSonucu.dolu);
    });
  });

  group('Koli karekodu', () {
    test('koli: eklenen, zaten listede, liste dışı sayılır', () {
      final l = OkutListesi()..islemSec(OkutIslemi.transfer);
      l.okut('A1', kayitli: true);
      final s = l.koliOkut([
        ('A1', true),
        ('A2', true),
        ('A3', true),
        ('K1', false),
      ]);
      expect(s.eklendi, 2);
      expect(s.zatenListede, 1);
      expect(s.disari, 1);
      expect(s.toplam, 4);
      expect(l.kalan, 97);
      expect(s.ozet(girisListesi: false),
          'Koli: 4 seri no · 2 eklendi · 1 zaten listede · 1 liste dışı (kayıtsız)');
    });

    test('koliler arka arkaya; aynı koli iki kez listeyi şişirmez', () {
      final l = OkutListesi()..islemSec(OkutIslemi.giris);
      final koli1 = [for (var i = 0; i < 10; i++) ('K$i', false)];
      final koli2 = [for (var i = 10; i < 20; i++) ('K$i', false)];
      expect(l.koliOkut(koli1).eklendi, 10);
      expect(l.koliOkut(koli2).eklendi, 10);
      expect(l.koliOkut(koli1).zatenListede, 10);
      expect(l.seriler.length, 20);
      expect(l.kalan, 80);
    });

    test('koli sığmazsa sığan kadarı eklenir', () {
      final l = OkutListesi()..islemSec(OkutIslemi.giris);
      for (var i = 0; i < 95; i++) {
        l.okut('X$i', kayitli: false);
      }
      final s = l.koliOkut([for (var i = 0; i < 15; i++) ('K$i', false)]);
      expect(s.eklendi, 5);
      expect(s.sigmadi, 10);
      expect(l.kalan, 0);
    });
  });

  test('kaydet / geri yükle', () {
    final l = OkutListesi()..islemSec(OkutIslemi.yukle);
    l.okut('A1', kayitli: true);
    l.okut('A2', kayitli: true);
    final y = OkutListesi()..fromJson(l.toJson());
    expect(y.islem, OkutIslemi.yukle);
    expect(y.seriler, ['A1', 'A2']);
  });
}
