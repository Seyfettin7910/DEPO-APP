import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../database/etiket_modelleri.dart';
import 'etiket_kodu.dart';
import 'etiket_sablonu.dart';

/// Etiketlerin gerçek ölçüde (mm) PDF'i. Yazdırırken "Gerçek boyut / %100"
/// seçilmeli (sayfaya sığdır kapalı), yoksa etiketler kayar.
class EtiketPdf {
  EtiketPdf._();

  static pw.ThemeData? _tema;

  static Future<pw.ThemeData> _temaYukle() async {
    if (_tema != null) return _tema!;
    final normal = pw.Font.ttf(
        await rootBundle.load('assets/fonts/DejaVuSansCondensed.ttf'));
    final kalin = pw.Font.ttf(
        await rootBundle.load('assets/fonts/DejaVuSansCondensed-Bold.ttf'));
    _tema = pw.ThemeData.withFont(base: normal, bold: kalin);
    return _tema!;
  }

  static final _gun = DateFormat('dd.MM.yyyy');

  static PdfPageFormat sayfaFormati(EtiketSablonu s) => s.rulo
      ? PdfPageFormat(s.etiketGenislik * PdfPageFormat.mm,
          s.etiketYukseklik * PdfPageFormat.mm, marginAll: 0)
      : PdfPageFormat(s.sayfaGenislik * PdfPageFormat.mm,
          s.sayfaYukseklik * PdfPageFormat.mm, marginAll: 0);

  /// Sayfadaki [i]. etiketin sol üst köşesi (mm).
  static (double, double) _konum(EtiketSablonu s, int i) {
    if (s.rulo) return (s.kaydirX, s.kaydirY);
    final sutun = i % s.sutun;
    final satir = i ~/ s.sutun;
    return (
      s.solKenar + s.kaydirX + sutun * (s.etiketGenislik + s.yatayAra),
      s.ustKenar + s.kaydirY + satir * (s.etiketYukseklik + s.dikeyAra),
    );
  }

  /// Etiketleri yerleştirir. [baslangic]: ilk sayfada atlanacak etiket sayısı
  /// (yarım kalmış A4 sayfasını kullanmak için).
  static Future<Uint8List> olustur(
    List<EtiketBilgi> etiketler,
    EtiketSablonu s, {
    int baslangic = 0,
  }) async {
    final tema = await _temaYukle();
    final doc = pw.Document(theme: tema, title: 'Kurum etiketleri');
    final format = sayfaFormati(s);
    final adet = s.sayfadakiEtiket;
    final atla = s.rulo ? 0 : baslangic.clamp(0, adet - 1);

    // Yerleşim sırası: ilk sayfada [atla] boşluk, sonra etiketler.
    final yerler = <EtiketBilgi?>[
      for (var i = 0; i < atla; i++) null,
      ...etiketler,
    ];
    for (var bas = 0; bas < yerler.length; bas += adet) {
      final sayfa = yerler.sublist(bas, math.min(bas + adet, yerler.length));
      doc.addPage(pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(fit: pw.StackFit.expand, children: [
          for (var i = 0; i < sayfa.length; i++)
            if (sayfa[i] != null)
              _yerlestir(s, i, _etiket(s, sayfa[i]!)),
        ]),
      ));
    }
    return doc.save();
  }

  static pw.Widget _yerlestir(EtiketSablonu s, int i, pw.Widget icerik) {
    final (x, y) = _konum(s, i);
    return pw.Positioned(
      left: x * PdfPageFormat.mm,
      top: y * PdfPageFormat.mm,
      child: pw.SizedBox(
        width: s.etiketGenislik * PdfPageFormat.mm,
        height: s.etiketYukseklik * PdfPageFormat.mm,
        child: icerik,
      ),
    );
  }

  /// Tek etiketin içeriği; ölçüye göre sadeleşir.
  static pw.Widget _etiket(EtiketSablonu s, EtiketBilgi e) {
    const mm = PdfPageFormat.mm;
    final g = s.etiketGenislik;
    final y = s.etiketYukseklik;
    final bosluk = math.min(2.0, y * 0.07);
    final ic = y - 2 * bosluk;
    final kucuk = y < 22 || g < 35;
    final cizgi = s.cizgiBarkod && g >= 45 && y >= 28;
    final kurum = s.kurumAdi.trim().isNotEmpty && y >= 30;

    final temel = (y * 0.24).clamp(5.0, 11.0);
    final kodStil = pw.TextStyle(fontSize: temel, fontWeight: pw.FontWeight.bold);
    final urunStil = pw.TextStyle(fontSize: temel * 0.8);
    final ufakStil = pw.TextStyle(fontSize: math.max(4.5, temel * 0.62),
        color: PdfColors.grey800);

    final karekod = EtiketKodu.karekodIcerigi(e.kod, e.surum, e.seriNo);
    final barkodY = cizgi ? math.max(5.0, y * 0.2) : 0.0;
    final ustY = kurum ? temel * 0.62 / mm * 1.35 : 0.0;
    final qr = math.min(ic - barkodY - ustY - (cizgi ? 1 : 0), g * 0.42);

    pw.Widget karekodW(double boyut) => pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(
              errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium),
          data: karekod,
          width: boyut * mm,
          height: boyut * mm,
          drawText: false,
        );

    if (kucuk) {
      final q = math.min(ic, g * 0.45);
      return pw.Padding(
        padding: pw.EdgeInsets.all(bosluk * mm),
        child: pw.Row(children: [
          karekodW(q),
          pw.SizedBox(width: 1 * mm),
          pw.Expanded(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(e.kod, style: kodStil, maxLines: 2),
                if (y >= 16)
                  pw.Text(e.urunAdi, style: ufakStil, maxLines: 1),
              ],
            ),
          ),
        ]),
      );
    }

    final altSatir = [
      if (!e.seriNosuz) 'SN ${e.seriNo}',
      _gun.format(e.olusturma),
      if (e.surum > 1) 'S${e.surum}',
    ].join(' · ');

    return pw.Padding(
      padding: pw.EdgeInsets.all(bosluk * mm),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (kurum)
            pw.Text(s.kurumAdi.trim(), style: ufakStil, maxLines: 1),
          pw.Expanded(
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                karekodW(qr),
                pw.SizedBox(width: 1.5 * mm),
                pw.Expanded(
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(e.kod, style: kodStil, maxLines: 1),
                      pw.SizedBox(height: 0.6 * mm),
                      pw.Text(e.urunAdi, style: urunStil, maxLines: 2),
                      pw.SizedBox(height: 0.6 * mm),
                      pw.Text(altSatir, style: ufakStil, maxLines: 2),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (cizgi) ...[
            pw.SizedBox(height: 1 * mm),
            pw.BarcodeWidget(
              barcode: pw.Barcode.code128(),
              data: e.kod,
              width: (g - 2 * bosluk) * mm,
              height: barkodY * mm,
              drawText: false,
            ),
          ],
        ],
      ),
    );
  }

  /// Hizalama test sayfası: her etiketin yeri ince çerçeve ve sıra numarası
  /// ile basılır. Düz kağıda basılıp etiket kağıdının üstüne tutulur;
  /// kayma varsa şablondaki "kaydır" değerleri düzeltilir.
  static Future<Uint8List> hizalamaTesti(EtiketSablonu s) async {
    final tema = await _temaYukle();
    final doc = pw.Document(theme: tema, title: 'Hizalama testi');
    final adet = s.sayfadakiEtiket;
    doc.addPage(pw.Page(
      pageFormat: sayfaFormati(s),
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Stack(fit: pw.StackFit.expand, children: [
        for (var i = 0; i < adet; i++)
          _yerlestir(
            s,
            i,
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.red, width: 0.4),
              ),
              alignment: pw.Alignment.center,
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(
                    s.rulo ? 'Test' : '${i ~/ s.sutun + 1}. satır · ${i % s.sutun + 1}. sütun',
                    style: const pw.TextStyle(fontSize: 6, color: PdfColors.red),
                  ),
                  pw.Text(
                    '${s.etiketGenislik}×${s.etiketYukseklik} mm',
                    style: const pw.TextStyle(fontSize: 5, color: PdfColors.grey700),
                  ),
                ],
              ),
            ),
          ),
      ]),
    ));
    return doc.save();
  }

  /// Şablonu denemek için örnek etiketlerle dolu bir sayfa.
  static Future<Uint8List> ornek(EtiketSablonu s) {
    final ornek = EtiketBilgi(
      id: 'ornek',
      cihazId: 'ornek',
      kod: 'BLD-BIM-7K3Q9X2M',
      surum: 1,
      durum: EtiketDurumu.kuyrukta,
      seriNosuz: false,
      olusturma: DateTime.now(),
      seriNo: 'GA8346562',
      urunAdi: 'NVR 16 Kanal',
    );
    return olustur(List.filled(s.sayfadakiEtiket, ornek), s);
  }
}
