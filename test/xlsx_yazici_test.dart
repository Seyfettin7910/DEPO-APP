import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:depo_app/services/excel_rapor_service.dart';
import 'package:depo_app/services/rapor/rapor_modeli.dart';
import 'package:depo_app/services/xlsx_yazici.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

/// 1.30.4: Excel 2007 uyumlu .xlsx yazıcısı.
Map<String, String> _ac(List<int> bayt) {
  final a = ZipDecoder().decodeBytes(bayt);
  return {
    for (final f in a.files)
      if (f.isFile) f.name: utf8.decode(f.content as List<int>),
  };
}

Rapor _ornekRapor() => const Rapor(
      baslik: 'Hareket Geçmişi',
      altBaslik: '01.10.2026 - 27.10.2026',
      sutunlar: ['Tarih', 'Ürün', 'Seri No', 'Miktar', 'Konum'],
      genislikler: [16, 30, 20, 8, 20],
      dosyaOn: 'hareket_gecmisi',
      ozet: [MapEntry('Toplam', '12'), MapEntry('Dönem', 'Ekim')],
      bolumler: [
        RaporBolumu(
          baslik: 'KAMERA MONTAJ EKİBİ DEPOSU',
          aciklama: 'Ağ ürünleri & "kayıt" <cihazları>',
          satirlar: [
            ['27.10.2026 09:13', 'HIKVISION DS-2CD1043', 'GA8346123', 1,
              RaporLink('Haritada aç', 'https://maps.google.com/?q=39.6,27.9')],
            ['27.10.2026 09:14', 'ÇİĞDEM ŞÜKRÜ İĞNE', '', 2.5, null],
          ],
        ),
        RaporBolumu(baslik: 'Boş bölüm', satirlar: []),
      ],
    );

void main() {
  test('sütun harfleri', () {
    expect(XlsxYazici.sutunHarfi(0), 'A');
    expect(XlsxYazici.sutunHarfi(25), 'Z');
    expect(XlsxYazici.sutunHarfi(26), 'AA');
    expect(XlsxYazici.sutunHarfi(27), 'AB');
    expect(XlsxYazici.sutunHarfi(701), 'ZZ');
    expect(XlsxYazici.sutunHarfi(702), 'AAA');
  });

  test('XML kaçışı ve yasak karakterler', () {
    expect(XlsxYazici.kacis('a & b < c > "d"'),
        'a &amp; b &lt; c &gt; &quot;d&quot;');
    expect(XlsxYazici.kacis('x\u0001y\tz'), 'xy\tz');
    expect(XlsxYazici.kacis('İĞŞÇÖÜ'), 'İĞŞÇÖÜ');
  });

  test('rapor dosyası: bütün parçalar var ve XML geçerli', () {
    final bayt = ExcelRaporService.olustur(_ornekRapor());
    // Elle açıp bakmak için örnek (CI'da yapıt olarak yüklenir).
    Directory('build').createSync(recursive: true);
    File('build/ornek_rapor.xlsx').writeAsBytesSync(bayt);
    final dosyalar = _ac(bayt);
    expect(
        dosyalar.keys.toSet(),
        {
          '[Content_Types].xml',
          '_rels/.rels',
          'docProps/app.xml',
          'docProps/core.xml',
          'xl/workbook.xml',
          'xl/_rels/workbook.xml.rels',
          'xl/styles.xml',
          'xl/sharedStrings.xml',
          'xl/worksheets/sheet1.xml',
        });
    for (final e in dosyalar.entries) {
      expect(() => XmlDocument.parse(e.value), returnsNormally,
          reason: '${e.key} geçerli XML olmalı');
    }
  });

  test('Excel 2007\'nin tanımadığı parça yok', () {
    final dosyalar = _ac(ExcelRaporService.olustur(_ornekRapor()));
    const yasak = [
      'markup-compatibility', // mc:Ignorable (Excel 2010+)
      'mc:',
      'x14', 'x15', 'xr:', 'xr2', 'xr3', // 2009+ ad alanları
      'spreadsheetml/2009', 'spreadsheetml/2010', 'spreadsheetml/2014',
      'office/mac', 'drawing', 'chartex', 'theme1',
    ];
    for (final e in dosyalar.entries) {
      for (final y in yasak) {
        expect(e.value.contains(y), isFalse,
            reason: '${e.key} içinde "$y" olmamalı');
      }
    }
    // Yalnız 2006 standardının ad alanları
    final ad = RegExp(r'xmlns(?::\w+)?="([^"]+)"');
    for (final e in dosyalar.entries) {
      for (final m in ad.allMatches(e.value)) {
        final u = m.group(1)!;
        expect(
            u.contains('/2006/') ||
                u == 'http://purl.org/dc/elements/1.1/' ||
                u == 'http://purl.org/dc/terms/' ||
                u == 'http://www.w3.org/2001/XMLSchema-instance',
            isTrue,
            reason: '${e.key}: beklenmeyen ad alanı $u');
      }
    }
  });

  test('hücreler ve PDF gibi görünüm', () {
    final d = _ac(ExcelRaporService.olustur(_ornekRapor()));
    final sayfa = XmlDocument.parse(d['xl/worksheets/sheet1.xml']!);
    final sst = XmlDocument.parse(d['xl/sharedStrings.xml']!);
    final stil = XmlDocument.parse(d['xl/styles.xml']!);
    final kitap = XmlDocument.parse(d['xl/workbook.xml']!);
    final yazilar = [
      for (final si in sst.findAllElements('si'))
        si.findElements('t').first.innerText
    ];
    final xfler = stil
        .findAllElements('cellXfs')
        .single
        .findElements('xf')
        .toList();
    final yazitipleri = stil.findAllElements('font').toList();
    final dolgular = stil.findAllElements('fill').toList();
    final kenarlar = stil.findAllElements('border').toList();

    XmlElement hucre(String ref) => sayfa
        .findAllElements('c')
        .firstWhere((c) => c.getAttribute('r') == ref);
    String deger(String ref) {
      final c = hucre(ref);
      final v = c.findElements('v').first.innerText;
      return c.getAttribute('t') == 's' ? yazilar[int.parse(v)] : v;
    }

    XmlElement xf(String ref) =>
        xfler[int.parse(hucre(ref).getAttribute('s') ?? '0')];
    XmlElement yazi(String ref) =>
        yazitipleri[int.parse(xf(ref).getAttribute('fontId')!)];
    bool kalin(String ref) => yazi(ref).findElements('b').isNotEmpty;
    String boyut(String ref) =>
        yazi(ref).findElements('sz').first.getAttribute('val')!;
    String? zemin(String ref) => dolgular[int.parse(xf(ref).getAttribute('fillId')!)]
        .findAllElements('fgColor')
        .firstOrNull
        ?.getAttribute('rgb');
    XmlElement kenar(String ref) =>
        kenarlar[int.parse(xf(ref).getAttribute('borderId')!)];
    bool cerceveli(String ref) =>
        kenar(ref).findElements('left').single.getAttribute('style') == 'thin';

    // Başlık: kalın 16
    expect(deger('A1'), 'Hareket Geçmişi');
    expect(kalin('A1'), isTrue);
    expect(boyut('A1'), '16');
    // Alt başlık gri, altında çizgi (tablo genişliğince)
    expect(yazi('A2').findElements('color').single.getAttribute('rgb'),
        'FF616161');
    expect(kenar('E2').findElements('bottom').single.getAttribute('style'),
        'thin');
    // Özet kutuları: yan yana, yeşil; değer sayı, kalın 14
    expect(deger('A4'), 'Toplam');
    expect(deger('B4'), 'Dönem');
    expect(zemin('A4'), 'FFE8F5E9');
    expect(hucre('A5').getAttribute('t'), isNull);
    expect(deger('A5'), '12');
    expect(kalin('A5'), isTrue);
    expect(boyut('A5'), '14');
    expect(zemin('B5'), 'FFE8F5E9');
    // Bölüm başlığı yeşil, bütün tablo genişliğince
    expect(deger('A7'), 'KAMERA MONTAJ EKİBİ DEPOSU');
    expect(zemin('A7'), 'FFC8E6C9');
    expect(zemin('E7'), 'FFC8E6C9');
    expect(deger('A8'), 'Ağ ürünleri & "kayıt" <cihazları>');
    // Tablo başlığı: gri, kalın, çerçeveli
    expect(deger('A9'), 'Tarih');
    expect(deger('E9'), 'Konum');
    expect(zemin('A9'), 'FFE0E0E0');
    expect(kalin('A9'), isTrue);
    expect(cerceveli('A9'), isTrue);
    // Satırlar: çerçeveli; ilki beyaz, ikincisi açık gri
    expect(cerceveli('A10'), isTrue);
    expect(zemin('A10'), isNull);
    expect(zemin('A11'), 'FFF5F5F5');
    expect(cerceveli('C11'), isTrue); // boş hücre de çizgili
    expect(deger('D10'), '1');
    expect(deger('D11'), '2.5');
    expect(deger('B11'), 'ÇİĞDEM ŞÜKRÜ İĞNE');
    // Bağlantı: formül + hazır sonuç, mavi altı çizili, çerçeve korunur
    final link = hucre('E10');
    expect(link.getAttribute('t'), 'str');
    expect(link.findElements('f').single.innerText,
        'HYPERLINK("https://maps.google.com/?q=39.6,27.9","Haritada aç")');
    expect(link.findElements('v').single.innerText, 'Haritada aç');
    expect(yazi('E10').findElements('u').isNotEmpty, isTrue);
    expect(cerceveli('E10'), isTrue);
    // Boş bölüm
    expect(deger('A13'), 'Boş bölüm');
    expect(deger('A14'), 'Kayıt yok');
    // Tek tablo: başlık satırı sabit (9. satırın altından), yazdırmada tekrar
    final pane = sayfa.findAllElements('pane').single;
    expect(pane.getAttribute('ySplit'), '9');
    expect(pane.getAttribute('state'), 'frozen');
    expect(kitap.findAllElements('definedName').single.innerText,
        "'Rapor'!\$9:\$9");
    // Yazdırma: sayfa genişliğine sığdır, alt bilgi
    final ps = sayfa.findAllElements('pageSetup').single;
    expect(ps.getAttribute('fitToWidth'), '1');
    expect(ps.getAttribute('fitToHeight'), '0');
    expect(sayfa.findAllElements('oddFooter').single.innerText,
        '&R&8DEPO YÖNETİM SİSTEMİ · Sayfa &P / &N');
    // Sütun genişlikleri en az 14, ürün sütunu 30
    final cols = sayfa.findAllElements('col').toList();
    expect(cols.length, 5);
    for (final c in cols) {
      expect(double.parse(c.getAttribute('width')!) >= 14, isTrue);
    }
    expect(cols[1].getAttribute('width'), '30.00');
    // Biçim tekrarlanmaz (her birleşim bir kez)
    expect(xfler.length, lessThan(20));
  });

  test('sayfa adı ve boş kitap', () {
    final x = XlsxYazici(sayfaAdi: 'Rapor: Ekim [2026] / depo ve araçlar listesi');
    expect(x.sayfaAdi.length <= 31, isTrue);
    expect(x.sayfaAdi.contains(RegExp(r'[:\\/?*\[\]]')), isFalse);
    final d = _ac(x.kaydet());
    expect(() => XmlDocument.parse(d['xl/worksheets/sheet1.xml']!),
        returnsNormally);
  });

  test('çok uzun bağlantı yazı olarak yazılır', () {
    final x = XlsxYazici()
      ..satirEkle([XlsxBaglanti('uzun', 'https://x.y/${'a' * 300}')]);
    final d = _ac(x.kaydet());
    expect(d['xl/worksheets/sheet1.xml']!.contains('<f>'), isFalse);
    expect(d['xl/sharedStrings.xml']!.contains('uzun'), isTrue);
  });
}
