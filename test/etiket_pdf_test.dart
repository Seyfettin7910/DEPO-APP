import 'dart:io';

import 'package:depo_app/database/etiket_modelleri.dart';
import 'package:depo_app/services/etiket/etiket_kodu.dart';
import 'package:depo_app/services/etiket/etiket_pdf.dart';
import 'package:depo_app/services/etiket/etiket_sablonu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('kod üretimi ve kontrol karakteri', () {
    for (var i = 0; i < 2000; i++) {
      final kod = EtiketKodu.uret('BLD-BIM');
      expect(EtiketKodu.gecerliMi(kod), isTrue, reason: kod);
      expect(kod.length, 'BLD-BIM-'.length + 8);
      // Tek karakter hatası yakalanmalı
      final son = kod.length - 3;
      final yanlis = kod.substring(0, son) +
          (kod[son] == '2' ? '3' : '2') +
          kod.substring(son + 1);
      expect(EtiketKodu.gecerliMi(yanlis), isFalse, reason: yanlis);
      // Yan yana iki karakterin yer değiştirmesi yakalanmalı
      final a = kod.length - 4;
      if (kod[a] != kod[a + 1]) {
        final ters = kod.substring(0, a) + kod[a + 1] + kod[a] + kod.substring(a + 2);
        expect(EtiketKodu.gecerliMi(ters), isFalse, reason: ters);
      }
      for (final c in ['0', 'O', '1', 'I', 'L']) {
        expect(kod.substring(8).contains(c), isFalse);
      }
    }
    expect(EtiketKodu.kurumKoduDuzenle(' bld bim '), 'BLD-BIM');
    expect(EtiketKodu.kurumKoduDuzenle('Fen İşleri'), 'FEN-ISLERI');
    expect(EtiketKodu.kurumKoduDuzenle('ÇOK-UZUN-KURUM-KODU-OLUR'), isNull);
    expect(EtiketKodu.gecerliMi('GA8346562'), isFalse);

    final kod = EtiketKodu.uret('BLD');
    final o = EtiketKodu.coz(EtiketKodu.karekodIcerigi(kod, 2, 'GA8346562'))!;
    expect(o.kod, kod);
    expect(o.surum, 2);
    expect(o.seriNo, 'GA8346562');
    expect(EtiketKodu.coz(kod)!.kod, kod);
    expect(EtiketKodu.coz('GA8346562'), isNull);
  });

  test('etiket PDF örnekleri', () async {
    final dizin = Directory('etiket_ornek')..createSync(recursive: true);
    final simdi = DateTime(2026, 10, 19);
    final etiketler = [
      EtiketBilgi(
          id: '1', cihazId: '1', kod: EtiketKodu.uret('BLD-BIM'), surum: 1,
          durum: EtiketDurumu.kuyrukta, seriNosuz: false, olusturma: simdi,
          seriNo: 'GA8346562', urunAdi: 'NVR 16 Kanal', depoAdi: 'Merkez Depo'),
      EtiketBilgi(
          id: '2', cihazId: '2', kod: EtiketKodu.uret('BLD-BIM'), surum: 2,
          durum: EtiketDurumu.kuyrukta, seriNosuz: false, olusturma: simdi,
          seriNo: 'SN-2023-AXQ-0049812', urunAdi: 'WİTEK 8 PORT POE SWITCH ŞĞÜİÖÇ',
          depoAdi: 'Merkez Depo'),
      EtiketBilgi(
          id: '3', cihazId: '3', kod: 'BLD-BIM-7K3Q9X2M', surum: 1,
          durum: EtiketDurumu.kuyrukta, seriNosuz: true, olusturma: simdi,
          seriNo: 'BLD-BIM-7K3Q9X2M', urunAdi: 'Cat6 kablo makarası'),
    ];
    for (final s in EtiketSablonu.hazirlar) {
      final ad = s.ad
          .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
          .replaceAll(RegExp(r'_+$'), '');
      final sablon = s.kopya(kurumAdi: 'T.C. Belediyesi Bilgi İşlem');
      File('${dizin.path}/$ad.pdf').writeAsBytesSync(
          await EtiketPdf.olustur(etiketler, sablon, baslangic: s.rulo ? 0 : 1));
    }
    File('${dizin.path}/hizalama_3x8.pdf').writeAsBytesSync(
        await EtiketPdf.hizalamaTesti(EtiketSablonu.hazirlar.first));
    File('${dizin.path}/ornek_3x8.pdf').writeAsBytesSync(
        await EtiketPdf.ornek(EtiketSablonu.hazirlar.first));
  });
}
