import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:share_plus/share_plus.dart';
import 'tarayici.dart';

import 'rapor/rapor_modeli.dart';

/// Ortak [Rapor] nesnesini PDF'e döker. Excel çıktısıyla aynı başlık,
/// sütun ve satırları kullanır. Türkçe karakterler (ş, ğ, ı, İ...) için
/// uygulamaya gömülü DejaVu Sans yazı tipi kullanılır (internet gerekmez).
class PdfReportService {
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

  static Future<pw.Document> olustur(Rapor rapor) async {
    final tema = await _temaYukle();
    final doc = pw.Document(theme: tema, title: rapor.baslik);
    final format = rapor.yatay ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;

    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => _ustBilgi(rapor),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 6),
          child: pw.Text(
            'DEPO YÖNETİM SİSTEMİ · Sayfa ${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          if (rapor.ozet.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            _ozet(rapor),
            pw.SizedBox(height: 12),
          ],
          for (final b in rapor.bolumler) ..._bolum(rapor, b),
        ],
      ),
    );
    return doc;
  }

  /// PDF'i oluşturur ve sistemin yazdır / PDF olarak kaydet / paylaş
  /// penceresini açar (web'de tarayıcının yazdırma penceresi).
  static Future<void> paylas(Rapor rapor) async {
    final doc = await olustur(rapor);
    final bytes = await doc.save();
    final ad =
        '${rapor.dosyaOn}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';
    // iPhone'da (Safari) yazdırma penceresi yerine Paylaş menüsü:
    // WhatsApp, e-posta, Dosyalar'a kaydet…
    if (kIsWeb && iosTarayici()) {
      await Share.shareXFiles(
        [XFile.fromData(bytes, name: ad, mimeType: 'application/pdf')],
        fileNameOverrides: [ad],
        subject: rapor.baslik,
      );
      return;
    }
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: ad,
      format: rapor.yatay ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
    );
  }

  static pw.Widget _ustBilgi(Rapor r) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(r.baslik,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text(r.altBaslik,
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.SizedBox(height: 6),
          pw.Divider(color: PdfColors.grey400, height: 1),
        ],
      );

  static pw.Widget _ozet(Rapor r) => pw.Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final e in r.ozet)
            pw.Container(
              width: 110,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.green50,
                borderRadius: pw.BorderRadius.circular(5),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(e.key,
                      style: const pw.TextStyle(
                          fontSize: 8, color: PdfColors.grey700)),
                  pw.SizedBox(height: 3),
                  pw.Text(e.value,
                      style: pw.TextStyle(
                          fontSize: 14, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
        ],
      );

  static List<pw.Widget> _bolum(Rapor r, RaporBolumu b) {
    final sutunlar = b.sutunlariAl(r);
    final genislik = b.genislikleriAl(r);
    return [
      if (b.baslik != null) ...[
        pw.SizedBox(height: 8),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          color: PdfColors.green100,
          child: pw.Text(b.baslik!,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        ),
      ],
      if (b.aciklama != null)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 3, bottom: 2),
          child: pw.Text(b.aciklama!,
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800)),
        ),
      pw.SizedBox(height: 4),
      if (b.satirlar.isEmpty)
        pw.Text('Kayıt yok',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600))
      else
        pw.TableHelper.fromTextArray(
          headers: sutunlar,
          data: [
            for (final s in b.satirlar)
              [for (final h in s) h?.toString() ?? ''],
          ],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellAlignment: pw.Alignment.centerLeft,
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey50),
          columnWidths: {
            for (var i = 0; i < sutunlar.length; i++)
              i: pw.FlexColumnWidth(i < genislik.length ? genislik[i] : 10),
          },
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        ),
      pw.SizedBox(height: 6),
    ];
  }
}
