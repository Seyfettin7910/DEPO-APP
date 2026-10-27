/// 1.30.4: Excel (.xlsx) dosyasını kendimiz yazarız.
///
/// Önceki hazır kütüphane, Google Sheets'ten alınmış bir şablon kullanıyordu;
/// içindeki Excel 2010+ eklentileri (x14ac, mc:Ignorable, Mac uzantıları, boş
/// çizim parçası) yüzünden Excel 2007 "okunamayan içerik buldu" diyordu.
///
/// Burada yalnız ilk xlsx standardındaki (ECMA-376, 2006) parçalar yazılır:
/// yazı, sayı, yazı tipi (kalın, boyut, renk, altı çizili), dolgu rengi,
/// kenarlık, kaydırma, sütun genişliği, HYPERLINK bağlantısı, başlık
/// satırını dondurma, yazdırma ayarları (yatay / sayfaya sığdır / her
/// sayfada başlık satırı / alt bilgi). Excel 2007 ve sonrası, LibreOffice,
/// Google Sheets ve telefon Excel'leri açar. Testleri:
/// test/xlsx_yazici_test.dart (2007'nin tanımadığı ad alanı kalmadığını da
/// denetler) ve CI'da tool/xlsx_denetim.py (openpyxl ile).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Hücre biçimi. Renkler "RRGGBB" (ör. 'E0E0E0').
class XlsxBicim {
  const XlsxBicim({
    this.kalin = false,
    this.boyut = 11,
    this.yaziRengi,
    this.altiCizili = false,
    this.dolgu,
    this.kenarlik = false,
    this.altCizgi,
    this.kaydir = false,
  });

  final bool kalin;
  final double boyut;
  final String? yaziRengi;
  final bool altiCizili;

  /// Zemin rengi (düz dolgu); null: yok.
  final String? dolgu;

  /// Dört kenarda ince çizgi (tablo hücresi).
  final bool kenarlik;

  /// Yalnız altta ince çizgi (ayırıcı); rengi.
  final String? altCizgi;

  /// Yazı hücreye sığmazsa alt satıra kayar; dikeyde ortalanır.
  final bool kaydir;

  static const normal = XlsxBicim();

  XlsxBicim baglantiyla() => XlsxBicim(
        kalin: kalin,
        boyut: boyut,
        yaziRengi: '0563C1',
        altiCizili: true,
        dolgu: dolgu,
        kenarlik: kenarlik,
        altCizgi: altCizgi,
        kaydir: kaydir,
      );

  String get _yaziAnahtari => '$kalin|$boyut|$yaziRengi|$altiCizili';
  String get _kenarAnahtari => kenarlik ? 'tum' : (altCizgi ?? '');
  String get _anahtar =>
      '$_yaziAnahtari|$dolgu|$_kenarAnahtari|$kaydir';

  @override
  bool operator ==(Object other) =>
      other is XlsxBicim && other._anahtar == _anahtar;

  @override
  int get hashCode => _anahtar.hashCode;
}

/// Tıklanabilir bağlantı hücresi (HYPERLINK formülüyle).
class XlsxBaglanti {
  const XlsxBaglanti(this.metin, this.url);
  final String metin;
  final String url;
}

class _Hucre {
  _Hucre(this.deger, this.bicim);
  Object? deger;
  XlsxBicim bicim;
}

/// Tek sayfalık çalışma kitabı. Değerler: String, int, double,
/// [XlsxBaglanti] ya da null (boş hücre).
class XlsxYazici {
  XlsxYazici({String sayfaAdi = 'Rapor'}) : sayfaAdi = _sayfaAdi(sayfaAdi);

  final String sayfaAdi;
  final _satirlar = <List<_Hucre>>[];
  final _genislikler = <int, double>{};

  /// Bu satırın üstü (başlıklar + tablo başlığı) kaydırınca sabit kalır.
  int? dondurulanSatir;

  /// Yazdırırken her sayfanın başında tekrarlanan satır (0'dan).
  int? yazdirmaBasligi;

  /// Yazdırma: yatay sayfa.
  bool yatay = false;

  /// Yazdırma: sağ alttaki alt bilgi (yanına "Sayfa x / y" eklenir).
  String? altBilgi;

  /// Satır ekler; satırın 0'dan başlayan numarasını döner. Boş liste boş
  /// satırdır. [bicim] bütün hücrelere uygulanır.
  int satirEkle(List<Object?> degerler, {XlsxBicim bicim = XlsxBicim.normal}) {
    _satirlar.add([for (final d in degerler) _Hucre(d, bicim)]);
    return _satirlar.length - 1;
  }

  /// [satir]ın ilk [sutunSayisi] hücresine biçim verir (boşlar da boyanır).
  void bicimVer(int satir, int sutunSayisi, XlsxBicim bicim) {
    final s = _satirlar[satir];
    while (s.length < sutunSayisi) {
      s.add(_Hucre(null, XlsxBicim.normal));
    }
    for (var i = 0; i < sutunSayisi; i++) {
      s[i].bicim = bicim;
    }
  }

  /// Tek hücreye biçim.
  void hucreBicimi(int satir, int sutun, XlsxBicim bicim) {
    final s = _satirlar[satir];
    while (s.length <= sutun) {
      s.add(_Hucre(null, XlsxBicim.normal));
    }
    s[sutun].bicim = bicim;
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

    // Biçimler → styles.xml sırası (0: normal).
    final bicimler = <XlsxBicim>[XlsxBicim.normal];
    final bicimNo = <XlsxBicim, int>{XlsxBicim.normal: 0};
    int no(XlsxBicim b) => bicimNo.putIfAbsent(b, () {
          bicimler.add(b);
          return bicimler.length - 1;
        });

    final sayfa = StringBuffer()
      ..write(_xmlBas)
      ..write('<worksheet xmlns="$_ana" xmlns:r="$_iliski">')
      ..write('<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>');
    var enGenis = 0;
    for (final s in _satirlar) {
      if (s.length > enGenis) enGenis = s.length;
    }
    final sonHucre = _satirlar.isEmpty || enGenis == 0
        ? 'A1'
        : '${sutunHarfi(enGenis - 1)}${_satirlar.length}';
    sayfa.write(
        '<dimension ref="A1${sonHucre == 'A1' ? '' : ':$sonHucre'}"/>');
    final d = dondurulanSatir;
    if (d != null && d > 0 && d < _satirlar.length) {
      final ust = 'A${d + 1}';
      sayfa.write('<sheetViews><sheetView workbookViewId="0">'
          '<pane ySplit="$d" topLeftCell="$ust" activePane="bottomLeft" '
          'state="frozen"/>'
          '<selection pane="bottomLeft" activeCell="$ust" sqref="$ust"/>'
          '</sheetView></sheetViews>');
    } else {
      sayfa.write('<sheetViews><sheetView workbookViewId="0"/></sheetViews>');
    }
    sayfa.write('<sheetFormatPr defaultRowHeight="15"/>');
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
        final deger = h.deger;
        final baglanti = deger is XlsxBaglanti && _baglantiYazilir(deger);
        final n = no(baglanti ? h.bicim.baglantiyla() : h.bicim);
        final s = n == 0 ? '' : ' s="$n"';
        if (deger == null || (deger is String && deger.isEmpty)) {
          if (s.isNotEmpty) sayfa.write('<c r="$ref"$s/>');
        } else if (deger is int) {
          sayfa.write('<c r="$ref"$s><v>$deger</v></c>');
        } else if (deger is double && deger.isFinite) {
          sayfa.write('<c r="$ref"$s><v>$deger</v></c>');
        } else if (baglanti) {
          // Formül + hazır sonuç: Excel hesaplamadan da metni gösterir.
          final url = deger.url.replaceAll('"', '""');
          final metin = deger.metin.replaceAll('"', '""');
          sayfa.write('<c r="$ref"$s t="str">'
              '<f>${kacis('HYPERLINK("$url","$metin")')}</f>'
              '<v>${kacis(deger.metin)}</v></c>');
        } else {
          final y = deger is XlsxBaglanti ? deger.metin : deger.toString();
          sayfa.write('<c r="$ref"$s t="s"><v>${yaziNo(y)}</v></c>');
        }
      }
      sayfa.write('</row>');
    }
    sayfa
      ..write('</sheetData>')
      ..write('<pageMargins left="0.4" right="0.4" top="0.5" bottom="0.6" '
          'header="0.3" footer="0.3"/>')
      ..write('<pageSetup paperSize="9" '
          'orientation="${yatay ? 'landscape' : 'portrait'}" '
          'fitToWidth="1" fitToHeight="0"/>');
    final ab = altBilgi;
    if (ab != null && ab.isNotEmpty) {
      // &R: sağ, &8: 8 punto, &P / &N: sayfa / toplam sayfa
      sayfa.write('<headerFooter><oddFooter>'
          '${kacis('&R&8${ab.replaceAll('&', '&&')} · Sayfa &P / &N')}'
          '</oddFooter></headerFooter>');
    }
    sayfa.write('</worksheet>');

    final sst = StringBuffer()
      ..write(_xmlBas)
      ..write('<sst xmlns="$_ana" count="${ortakYazilar.length}" '
          'uniqueCount="${ortakYazilar.length}">');
    for (final y in ortakYazilar) {
      final bosluk =
          y != y.trim() || y.contains('\n') ? ' xml:space="preserve"' : '';
      sst.write('<si><t$bosluk>${kacis(y)}</t></si>');
    }
    sst.write('</sst>');

    final yb = yazdirmaBasligi;
    final basliklar = yb != null && yb >= 0 && yb < _satirlar.length
        ? "'${sayfaAdi.replaceAll("'", "''")}'!\$${yb + 1}:\$${yb + 1}"
        : null;

    final arsiv = Archive();
    void ekle(String ad, String icerik) {
      final b = utf8.encode(icerik);
      arsiv.addFile(ArchiveFile(ad, b.length, b));
    }

    ekle('[Content_Types].xml', _icerikTurleri);
    ekle('_rels/.rels', _kokIliskiler);
    ekle('docProps/app.xml', _uygulamaOzellikleri);
    ekle('docProps/core.xml', _belgeOzellikleri());
    ekle('xl/workbook.xml', _calismaKitabi(sayfaAdi, basliklar));
    ekle('xl/_rels/workbook.xml.rels', _kitapIliskileri);
    ekle('xl/styles.xml', _stiller(bicimler));
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

String _calismaKitabi(String sayfaAdi, String? yazdirmaBasliklari) =>
    '$_xmlBas'
    '<workbook xmlns="$_ana" xmlns:r="$_iliski">'
    '<bookViews><workbookView/></bookViews>'
    '<sheets><sheet name="${XlsxYazici.kacis(sayfaAdi)}" sheetId="1" r:id="rId1"/></sheets>'
    '${yazdirmaBasliklari == null ? '' : '<definedNames><definedName name="_xlnm.Print_Titles" localSheetId="0">${XlsxYazici.kacis(yazdirmaBasliklari)}</definedName></definedNames>'}'
    '</workbook>';

const _kitapIliskileri = '$_xmlBas'
    '<Relationships xmlns="$_paketIliski">'
    '<Relationship Id="rId1" Type="$_iliski/worksheet" Target="worksheets/sheet1.xml"/>'
    '<Relationship Id="rId2" Type="$_iliski/styles" Target="styles.xml"/>'
    '<Relationship Id="rId3" Type="$_iliski/sharedStrings" Target="sharedStrings.xml"/>'
    '</Relationships>';

/// styles.xml: kullanılan biçimlerden yazı tipi, dolgu ve kenarlık listeleri
/// çıkarılır; cellXfs sırası [bicimler] ile aynı.
String _stiller(List<XlsxBicim> bicimler) {
  final yazilar = <String>[];
  final dolgular = <String?>[null, 'gray125']; // Excel'in zorunlu ilk ikisi
  final kenarlar = <String>['']; // 0: yok
  int sira<T>(List<T> l, T x) {
    final i = l.indexOf(x);
    if (i >= 0) return i;
    l.add(x);
    return l.length - 1;
  }

  final xfler = StringBuffer();
  for (final b in bicimler) {
    final f = sira(yazilar, b._yaziAnahtari);
    final d = b.dolgu == null ? 0 : sira(dolgular, b.dolgu);
    final k = sira(kenarlar, b._kenarAnahtari);
    xfler.write('<xf numFmtId="0" fontId="$f" fillId="$d" borderId="$k" '
        'xfId="0"');
    if (f != 0) xfler.write(' applyFont="1"');
    if (d != 0) xfler.write(' applyFill="1"');
    if (k != 0) xfler.write(' applyBorder="1"');
    if (b.kaydir) {
      xfler.write(' applyAlignment="1">'
          '<alignment vertical="center" wrapText="1"/></xf>');
    } else {
      xfler.write('/>');
    }
  }

  final s = StringBuffer()
    ..write(_xmlBas)
    ..write('<styleSheet xmlns="$_ana">')
    ..write('<fonts count="${yazilar.length}">');
  for (final y in yazilar) {
    final p = y.split('|'); // kalin|boyut|renk|altiCizili
    final boyut = double.parse(p[1]);
    s.write('<font>');
    if (p[0] == 'true') s.write('<b/>');
    if (p[3] == 'true') s.write('<u/>');
    s.write('<sz val="${boyut == boyut.roundToDouble() ? boyut.round() : boyut}"/>');
    if (p[2] != 'null') s.write('<color rgb="FF${p[2]}"/>');
    s.write('<name val="Calibri"/><family val="2"/></font>');
  }
  s.write('</fonts><fills count="${dolgular.length}">');
  for (var i = 0; i < dolgular.length; i++) {
    if (i == 0) {
      s.write('<fill><patternFill patternType="none"/></fill>');
    } else if (i == 1) {
      s.write('<fill><patternFill patternType="gray125"/></fill>');
    } else {
      s.write('<fill><patternFill patternType="solid">'
          '<fgColor rgb="FF${dolgular[i]}"/><bgColor indexed="64"/>'
          '</patternFill></fill>');
    }
  }
  s.write('</fills><borders count="${kenarlar.length}">');
  for (final k in kenarlar) {
    if (k.isEmpty) {
      s.write('<border><left/><right/><top/><bottom/><diagonal/></border>');
    } else if (k == 'tum') {
      const c = '<color rgb="FF9E9E9E"/>';
      s.write('<border><left style="thin">$c</left><right style="thin">$c'
          '</right><top style="thin">$c</top><bottom style="thin">$c</bottom>'
          '<diagonal/></border>');
    } else {
      s.write('<border><left/><right/><top/><bottom style="thin">'
          '<color rgb="FF$k"/></bottom><diagonal/></border>');
    }
  }
  s
    ..write('</borders>')
    ..write('<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" '
        'borderId="0"/></cellStyleXfs>')
    ..write('<cellXfs count="${bicimler.length}">$xfler</cellXfs>')
    ..write('<cellStyles count="1"><cellStyle name="Normal" xfId="0" '
        'builtinId="0"/></cellStyles>')
    ..write('</styleSheet>');
  return s.toString();
}
