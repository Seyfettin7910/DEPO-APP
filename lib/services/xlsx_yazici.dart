/// 1.30.4: Excel (.xlsx) dosyasını kendimiz yazarız.
///
/// Önceki hazır kütüphane, Google Sheets'ten alınmış bir şablon kullanıyordu;
/// içindeki Excel 2010+ eklentileri (x14ac, mc:Ignorable, Mac uzantıları, boş
/// çizim parçası) yüzünden Excel 2007 "okunamayan içerik buldu" diyordu.
///
/// Burada yalnız ilk xlsx standardındaki (ECMA-376, 2006) parçalar yazılır:
/// yazı, sayı, kalın / büyük başlık, dolgu rengi, sütun genişliği ve
/// HYPERLINK bağlantısı. Excel 2007 ve sonrası, LibreOffice, Google Sheets ve
/// telefon Excel'leri açar. Testleri: test/xlsx_yazici_test.dart (2007'nin
/// tanımadığı ad alanı kalmadığını da denetler).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Hücre görünümleri (styles.xml'deki sırayla).
enum XlsxStil { normal, baslik, kalin, bolum, sutun, baglanti }

/// Tıklanabilir bağlantı hücresi (HYPERLINK formülüyle).
class XlsxBaglanti {
  const XlsxBaglanti(this.metin, this.url);
  final String metin;
  final String url;
}

class _Hucre {
  _Hucre(this.deger, this.stil);
  Object? deger;
  XlsxStil stil;
}

/// Tek sayfalık çalışma kitabı. Değerler: String, int, double,
/// [XlsxBaglanti] ya da null (boş hücre).
class XlsxYazici {
  XlsxYazici({String sayfaAdi = 'Rapor'}) : sayfaAdi = _sayfaAdi(sayfaAdi);

  final String sayfaAdi;
  final _satirlar = <List<_Hucre>>[];
  final _genislikler = <int, double>{};

  /// Satır ekler; satırın 0'dan başlayan numarasını döner. Boş liste boş
  /// satırdır.
  int satirEkle(List<Object?> degerler) {
    _satirlar.add([for (final d in degerler) _Hucre(d, XlsxStil.normal)]);
    return _satirlar.length - 1;
  }

  /// [satir]ın ilk [sutunSayisi] hücresine görünüm verir (boşlar da boyanır).
  void stilVer(int satir, int sutunSayisi, XlsxStil stil) {
    final s = _satirlar[satir];
    while (s.length < sutunSayisi) {
      s.add(_Hucre(null, XlsxStil.normal));
    }
    for (var i = 0; i < sutunSayisi; i++) {
      s[i].stil = stil;
    }
  }

  /// Sütun genişliği (karakter cinsinden, Excel'deki gibi).
  void sutunGenisligi(int sutun, double genislik) =>
      _genislikler[sutun] = genislik;

  /// .xlsx dosyasının baytları.
  Uint8List kaydet() {
    final ortakYazilar = <String>[];
    final yaziSirasi = <String, int>{};
    int yaziNo(String y) => yaziSirasi.putIfAbsent(y, () {
          ortakYazilar.add(y);
          return ortakYazilar.length - 1;
        });

    final sayfa = StringBuffer()
      ..write(_xmlBas)
      ..write('<worksheet xmlns="$_ana" xmlns:r="$_iliski">');
    var enGenis = 0;
    for (final s in _satirlar) {
      if (s.length > enGenis) enGenis = s.length;
    }
    final sonHucre = _satirlar.isEmpty || enGenis == 0
        ? 'A1'
        : '${sutunHarfi(enGenis - 1)}${_satirlar.length}';
    sayfa
      ..write('<dimension ref="A1${sonHucre == 'A1' ? '' : ':$sonHucre'}"/>')
      ..write('<sheetViews><sheetView workbookViewId="0"/></sheetViews>')
      ..write('<sheetFormatPr defaultRowHeight="15"/>');
    if (_genislikler.isNotEmpty) {
      sayfa.write('<cols>');
      final sirali = _genislikler.keys.toList()..sort();
      for (final i in sirali) {
        final g = _genislikler[i]!.clamp(1.0, 255.0);
        sayfa.write('<col min="${i + 1}" max="${i + 1}" '
            'width="${g.toStringAsFixed(2)}" customWidth="1"/>');
      }
      sayfa.write('</cols>');
    }
    sayfa.write('<sheetData>');
    for (var r = 0; r < _satirlar.length; r++) {
      final satir = _satirlar[r];
      if (satir.isEmpty) continue; // boş satır: yazılmaz, numara atlanır
      sayfa.write('<row r="${r + 1}">');
      for (var c = 0; c < satir.length; c++) {
        final h = satir[c];
        final ref = '${sutunHarfi(c)}${r + 1}';
        final s = h.stil.index == 0 ? '' : ' s="${h.stil.index}"';
        final d = h.deger;
        if (d == null || (d is String && d.isEmpty)) {
          if (s.isNotEmpty) sayfa.write('<c r="$ref"$s/>');
        } else if (d is int) {
          sayfa.write('<c r="$ref"$s><v>$d</v></c>');
        } else if (d is double && d.isFinite) {
          sayfa.write('<c r="$ref"$s><v>$d</v></c>');
        } else if (d is XlsxBaglanti && _baglantiYazilir(d)) {
          // Formül + hazır sonuç: Excel hesaplamadan da metni gösterir.
          final url = d.url.replaceAll('"', '""');
          final metin = d.metin.replaceAll('"', '""');
          final bs = ' s="${XlsxStil.baglanti.index}"';
          sayfa.write('<c r="$ref"$bs t="str">'
              '<f>${kacis('HYPERLINK("$url","$metin")')}</f>'
              '<v>${kacis(d.metin)}</v></c>');
        } else {
          final y = d is XlsxBaglanti ? d.metin : d.toString();
          sayfa.write('<c r="$ref"$s t="s"><v>${yaziNo(y)}</v></c>');
        }
      }
      sayfa.write('</row>');
    }
    sayfa
      ..write('</sheetData>')
      ..write('<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" '
          'header="0.3" footer="0.3"/>')
      ..write('</worksheet>');

    final sst = StringBuffer()
      ..write(_xmlBas)
      ..write('<sst xmlns="$_ana" count="${ortakYazilar.length}" '
          'uniqueCount="${ortakYazilar.length}">');
    for (final y in ortakYazilar) {
      final bosluk = y != y.trim() || y.contains('\n') ? ' xml:space="preserve"' : '';
      sst.write('<si><t$bosluk>${kacis(y)}</t></si>');
    }
    sst.write('</sst>');

    final arsiv = Archive();
    void ekle(String ad, String icerik) {
      final b = utf8.encode(icerik);
      arsiv.addFile(ArchiveFile(ad, b.length, b));
    }

    ekle('[Content_Types].xml', _icerikTurleri);
    ekle('_rels/.rels', _kokIliskiler);
    ekle('docProps/app.xml', _uygulamaOzellikleri);
    ekle('docProps/core.xml', _belgeOzellikleri());
    ekle('xl/workbook.xml', _calismaKitabi(sayfaAdi));
    ekle('xl/_rels/workbook.xml.rels', _kitapIliskileri);
    ekle('xl/styles.xml', _stiller);
    ekle('xl/sharedStrings.xml', sst.toString());
    ekle('xl/worksheets/sheet1.xml', sayfa.toString());
    final List<int>? bayt = ZipEncoder().encode(arsiv);
    if (bayt == null) throw StateError('Excel dosyası oluşturulamadı');
    return Uint8List.fromList(bayt);
  }

  // ------------------------------------------------------------ yardımcılar

  /// 0 → A, 25 → Z, 26 → AA…
  static String sutunHarfi(int i) {
    var n = i + 1;
    var s = '';
    while (n > 0) {
      final k = (n - 1) % 26;
      s = String.fromCharCode(65 + k) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  /// XML'e güvenli yazı: & < > " kaçırılır, XML'de yasak denetim
  /// karakterleri atılır (sekme ve satır sonu kalır).
  static String kacis(String y) {
    final b = StringBuffer();
    for (final r in y.runes) {
      if (r < 0x20 && r != 0x09 && r != 0x0A && r != 0x0D) continue;
      if (r == 0xFFFE || r == 0xFFFF) continue;
      switch (r) {
        case 0x26:
          b.write('&amp;');
        case 0x3C:
          b.write('&lt;');
        case 0x3E:
          b.write('&gt;');
        case 0x22:
          b.write('&quot;');
        default:
          b.writeCharCode(r);
      }
    }
    return b.toString();
  }

  // Excel'de formül içindeki yazı 255 karakteri geçemez.
  static bool _baglantiYazilir(XlsxBaglanti b) =>
      b.url.isNotEmpty && b.url.length <= 255 && b.metin.length <= 255;

  // Sayfa adı: en fazla 31 karakter, : \ / ? * [ ] olamaz.
  static String _sayfaAdi(String ad) {
    final t = ad.replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ').trim();
    if (t.isEmpty) return 'Rapor';
    return t.length > 31 ? t.substring(0, 31) : t;
  }
}

// ------------------------------------------------------------- sabit parçalar

const _xmlBas = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
const _ana = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _iliski =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _paketIliski =
    'http://schemas.openxmlformats.org/package/2006/relationships';

const _icerikTurleri = '$_xmlBas'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
    '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
    '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>'
    '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
    '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
    '</Types>';

const _kokIliskiler = '$_xmlBas'
    '<Relationships xmlns="$_paketIliski">'
    '<Relationship Id="rId1" Type="$_iliski/officeDocument" Target="xl/workbook.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
    '<Relationship Id="rId3" Type="$_iliski/extended-properties" Target="docProps/app.xml"/>'
    '</Relationships>';

const _uygulamaOzellikleri = '$_xmlBas'
    '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
    '<Application>Microsoft Excel</Application>'
    '<Company>DEPO YÖNETİM SİSTEMİ</Company>'
    '</Properties>';

String _belgeOzellikleri() {
  final t = DateTime.now().toUtc();
  final damga = '${t.toIso8601String().split('.').first}Z';
  return '$_xmlBas'
      '<cp:coreProperties '
      'xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" '
      'xmlns:dcterms="http://purl.org/dc/terms/" '
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
      '<dc:creator>DEPO YÖNETİM SİSTEMİ</dc:creator>'
      '<dcterms:created xsi:type="dcterms:W3CDTF">$damga</dcterms:created>'
      '<dcterms:modified xsi:type="dcterms:W3CDTF">$damga</dcterms:modified>'
      '</cp:coreProperties>';
}

String _calismaKitabi(String sayfaAdi) => '$_xmlBas'
    '<workbook xmlns="$_ana" xmlns:r="$_iliski">'
    '<bookViews><workbookView/></bookViews>'
    '<sheets><sheet name="${XlsxYazici.kacis(sayfaAdi)}" sheetId="1" r:id="rId1"/></sheets>'
    '</workbook>';

const _kitapIliskileri = '$_xmlBas'
    '<Relationships xmlns="$_paketIliski">'
    '<Relationship Id="rId1" Type="$_iliski/worksheet" Target="worksheets/sheet1.xml"/>'
    '<Relationship Id="rId2" Type="$_iliski/styles" Target="styles.xml"/>'
    '<Relationship Id="rId3" Type="$_iliski/sharedStrings" Target="sharedStrings.xml"/>'
    '</Relationships>';

// Yazı tipleri: 0 normal · 1 kalın · 2 kalın 14 pt · 3 bağlantı (mavi, altı
// çizili). Dolgular: 0 yok · 1 gray125 (Excel'in zorunlu ikincisi) · 2 yeşil
// (bölüm) · 3 gri (sütun başlığı). cellXfs sırası [XlsxStil] ile aynı.
const _stiller = '$_xmlBas'
    '<styleSheet xmlns="$_ana">'
    '<fonts count="4">'
    '<font><sz val="11"/><name val="Calibri"/><family val="2"/></font>'
    '<font><b/><sz val="11"/><name val="Calibri"/><family val="2"/></font>'
    '<font><b/><sz val="14"/><name val="Calibri"/><family val="2"/></font>'
    '<font><u/><sz val="11"/><color rgb="FF0563C1"/><name val="Calibri"/><family val="2"/></font>'
    '</fonts>'
    '<fills count="4">'
    '<fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFC8E6C9"/><bgColor indexed="64"/></patternFill></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFE0E0E0"/><bgColor indexed="64"/></patternFill></fill>'
    '</fills>'
    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="6">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
    '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>'
    '<xf numFmtId="0" fontId="1" fillId="3" borderId="0" xfId="0" applyFont="1" applyFill="1"/>'
    '<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
    '</cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
    '</styleSheet>';
