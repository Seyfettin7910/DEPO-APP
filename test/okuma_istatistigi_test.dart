import 'package:depo_app/services/okuma_istatistigi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 1.31.0: okuma sayıları (telefonda birikir, akşam 17:00-17:30 gönderilir).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('gönderim penceresi 17:00 - 17:30', () {
    expect(OkumaIstatistigi.gonderimSaati(DateTime(2026, 10, 28, 16, 59)), isFalse);
    expect(OkumaIstatistigi.gonderimSaati(DateTime(2026, 10, 28, 17, 0)), isTrue);
    expect(OkumaIstatistigi.gonderimSaati(DateTime(2026, 10, 28, 17, 29)), isTrue);
    expect(OkumaIstatistigi.gonderimSaati(DateTime(2026, 10, 28, 17, 30)), isFalse);
    expect(OkumaIstatistigi.gonderimSaati(DateTime(2026, 10, 28, 18, 5)), isFalse);
  });

  test('gönderilecek günler', () {
    const gunler = ['2026-10-26', '2026-10-27', '2026-10-28'];
    // Sabah: yalnız geçmiş günler
    expect(
        OkumaIstatistigi.gonderilecekGunler(
            gunler, DateTime(2026, 10, 28, 9, 0), null),
        ['2026-10-26', '2026-10-27']);
    // 17:10: bugün de
    expect(
        OkumaIstatistigi.gonderilecekGunler(
            gunler, DateTime(2026, 10, 28, 17, 10), null),
        gunler);
    // 17:10 ama bugün zaten gönderildi
    expect(
        OkumaIstatistigi.gonderilecekGunler(
            ['2026-10-28'], DateTime(2026, 10, 28, 17, 20), '2026-10-28'),
        isEmpty);
    // 20:00: bugün beklemez, yarın geçmiş gün olarak gider
    expect(
        OkumaIstatistigi.gonderilecekGunler(
            ['2026-10-28'], DateTime(2026, 10, 28, 20, 0), null),
        isEmpty);
  });

  test('sayaç: ekleme ve JSON', () {
    final a = GunlukSayac()
      ..barkod = 3
      ..yazi = 1
      ..hayir = 1
      ..sureToplamMs = 4000
      ..sureAdet = 2;
    a.yokSayilan['MAC adresi'] = 2;
    a.yakinlik['2x'] = 4;
    final b = GunlukSayac.fromJson(a.toJson());
    expect(b.okuma, 4);
    expect(b.yokSayilan, {'MAC adresi': 2});
    b.ekle(a);
    expect(b.barkod, 6);
    expect(b.yokToplam, 4);
    expect(b.yakinlik['2x'], 8);
    expect(GunlukSayac().bos, isTrue);
  });

  test('sayma telefonda birikir', () async {
    SharedPreferences.setMockInitialValues({});
    OkumaIstatistigi.testIcinSifirla();
    OkumaIstatistigi.kabul(OkumaKaynagi.barkod,
        sure: const Duration(seconds: 2), yakinlik: 2);
    OkumaIstatistigi.kabul(OkumaKaynagi.karekod);
    OkumaIstatistigi.kabul(OkumaKaynagi.yazi,
        sure: const Duration(minutes: 5)); // 2 dk'dan uzun: süre sayılmaz
    OkumaIstatistigi.yokSayildi('fabrika barkodu');
    OkumaIstatistigi.dogruMu(false);
    OkumaIstatistigi.kameraDurdu();
    final s = await OkumaIstatistigi.bugun();
    expect(s.barkod, 1);
    expect(s.karekod, 1);
    expect(s.yazi, 1);
    expect(s.sureAdet, 1);
    expect(s.sureToplamMs, 2000);
    expect(s.yakinlik, {'2x': 1});
    expect(s.yokSayilan, {'fabrika barkodu': 1});
    expect(s.hayir, 1);
    expect(s.kameraDurdu, 1);
    // İkinci tur eklenir (üzerine yazılmaz)
    OkumaIstatistigi.kabul(OkumaKaynagi.barkod);
    expect((await OkumaIstatistigi.bugun()).barkod, 2);
    OkumaIstatistigi.testIcinSifirla();
  });
}
