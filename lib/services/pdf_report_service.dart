import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../database/app_database.dart';

/// Kullanım raporunu (hangi ürün, hangi depodan, hangi araca/yere,
/// ne zaman kullanıldı) PDF olarak üretir.
class PdfReportService {
  static final _tarihFormat = DateFormat('dd.MM.yyyy HH:mm');
  static final _baslikTarihFormat = DateFormat('dd MMMM yyyy', 'tr_TR');

  static Future<pw.Document> kullanimRaporuOlustur({
    required List<KullanimRaporSatiri> satirlar,
    String baslik = 'Depo Kullanım Raporu',
    DateTime? baslangic,
    DateTime? bitis,
  }) async {
    final doc = pw.Document();

    final aralikMetni = _aralikMetniOlustur(baslangic, bitis);
    final toplamMiktar = satirlar.fold<int>(0, (t, s) => t + s.miktar);

    // Ürüne göre gruplandırılmış özet (rapor başında hızlı bakış için)
    final urunOzet = <String, int>{};
    for (final s in satirlar) {
      urunOzet[s.urunAdi] = (urunOzet[s.urunAdi] ?? 0) + s.miktar;
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => _sayfaBaslik(baslik, aralikMetni),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'Sayfa ${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          pw.SizedBox(height: 12),
          _ozetKutusu(toplamKayit: satirlar.length, toplamMiktar: toplamMiktar),
          pw.SizedBox(height: 16),
          if (urunOzet.isNotEmpty) ...[
            pw.Text('Ürün Bazlı Özet',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            _urunOzetTablosu(urunOzet),
            pw.SizedBox(height: 20),
          ],
          pw.Text('Kullanım Detayları',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          _detayTablosu(satirlar),
        ],
      ),
    );

    return doc;
  }

  static String _aralikMetniOlustur(DateTime? baslangic, DateTime? bitis) {
    if (baslangic == null && bitis == null) return 'Tüm zamanlar';
    final b = baslangic != null ? _baslikTarihFormat.format(baslangic) : '...';
    final s = bitis != null ? _baslikTarihFormat.format(bitis) : 'bugün';
    return '$b - $s';
  }

  static pw.Widget _sayfaBaslik(String baslik, String aralikMetni) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(baslik,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        pw.Text(aralikMetni,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.SizedBox(height: 8),
        pw.Divider(color: PdfColors.grey400),
      ],
    );
  }

  static pw.Widget _ozetKutusu({required int toplamKayit, required int toplamMiktar}) {
    pw.Widget kutu(String etiket, String deger) => pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(etiket, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                pw.SizedBox(height: 4),
                pw.Text(deger, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
        );

    return pw.Row(
      children: [
        kutu('Toplam Kayıt', '$toplamKayit'),
        pw.SizedBox(width: 10),
        kutu('Toplam Miktar', '$toplamMiktar'),
      ],
    );
  }

  static pw.Widget _urunOzetTablosu(Map<String, int> urunOzet) {
    return pw.TableHelper.fromTextArray(
      headers: ['Ürün', 'Toplam Kullanılan Miktar'],
      data: urunOzet.entries.map((e) => [e.key, '${e.value}']).toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellStyle: const pw.TextStyle(fontSize: 10),
      cellAlignment: pw.Alignment.centerLeft,
      columnWidths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(2)},
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    );
  }

  static pw.Widget _detayTablosu(List<KullanimRaporSatiri> satirlar) {
    return pw.TableHelper.fromTextArray(
      headers: ['Tarih', 'Ürün', 'Seri No', 'Depo', 'Kullanıldığı Yer / Araç', 'Miktar'],
      data: satirlar
          .map((s) => [
                _tarihFormat.format(s.tarih),
                s.urunAdi,
                s.seriNo ?? '-',
                s.depoAdi,
                s.aracPlaka ?? s.kullanimYeri ?? '-',
                '${s.miktar}',
              ])
          .toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignment: pw.Alignment.centerLeft,
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(2.5),
        2: const pw.FlexColumnWidth(2.5),
        3: const pw.FlexColumnWidth(2),
        4: const pw.FlexColumnWidth(2.5),
        5: const pw.FlexColumnWidth(1),
      },
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
    );
  }
}
