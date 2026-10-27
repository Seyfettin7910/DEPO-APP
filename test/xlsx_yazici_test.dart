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
      'office/mac', 'drawing', 'chartex', 'theme',
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

  test('hücreler: yazı, sayı, bağlantı, stil', () {
    final d = _ac(ExcelRaporService.olustur(_ornekRapor()));
    final sayfa = XmlDocument.parse(d['xl/worksheets/sheet1.xml']!);
    final sst = XmlDocument.parse(d['xl/sharedStrings.xml']!);
    final yazilar = [
      for (final si in sst.findAllElements('si')) si.findElements('t').first.innerText
    ];
    expect(yazilar, contains('Hareket Geçmişi'));
    expect(yazilar, contains('Ağ ürünleri & "kayıt" <cihazları>'));
    expect(yazilar, contains('ÇİĞDEM ŞÜKRÜ İĞNE'));
    expect(yazilar, contains('Kayıt yok'));

    XmlElement hucre(String ref) => sayfa
        .findAllElements('c')
        .firstWhere((c) => c.getAttribute('r') == ref);
    String yaziOf(XmlElement c) =>
        yazilar[int.parse(c.findElements('v').first.innerText)];

    // A1: büyük başlık
    expect(hucre('A1').getAttribute('s'), '${XlsxStil.baslik.index}');
    expect(yaziOf(hucre('A1')), 'Hareket Geçmişi');
    // Özet: "Toplam" 12 sayı olarak
    final b4 = hucre('B4');
    expect(b4.getAttribute('t'), isNull);
    expect(b4.findElements('v').first.innerText, '12');
    // Bağlantı formülü + hazır sonuç
    final link = sayfa.findAllElements('f').single;
    expect(link.innerText,
        'HYPERLINK("https://maps.google.com/?q=39.6,27.9","Haritada aç")');
    final linkHucre = link.parent! as XmlElement;
    expect(linkHucre.getAttribute('t'), 'str');
    expect(linkHucre.findElements('v').first.innerText, 'Haritada aç');
    // Ondalık sayı
    expect(sayfa.findAllElements('v').any((v) => v.innerText == '2.5'), isTrue);
    // Sütun genişlikleri en az 14
    final cols = sayfa.findAllElements('col').toList();
    expect(cols.length, 5);
    for (final c in cols) {
      expect(double.parse(c.getAttribute('width')!) >= 14, isTrue);
    }
    // Ürün sütunu 30
    expect(cols[1].getAttribute('width'), '30.00');
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
