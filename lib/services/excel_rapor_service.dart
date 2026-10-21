import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'tarayici.dart';

import 'rapor/rapor_modeli.dart';

/// Ortak [Rapor] nesnesini Excel (.xlsx) dosyasına döker. PDF çıktısıyla
/// aynı başlık, sütun ve satırları kullanır.
/// Web'de dosya doğrudan iner; telefonda paylaş menüsü açılır.
class ExcelRaporService {
  static Future<void> paylas(Rapor rapor) async {
    final excel = Excel.createExcel();
    const sayfaAdi = 'Rapor';
    final varsayilan = excel.getDefaultSheet();
    if (varsayilan != null && varsayilan != sayfaAdi) {
      excel.rename(varsayilan, sayfaAdi);
    }
    final sayfa = excel[sayfaAdi];

    var satir = 0;
    int ekle(List<CellValue?> hucreler) {
      sayfa.appendRow(hucreler.isEmpty ? [TextCellValue('')] : hucreler);
      return satir++;
    }

    void stil(int r, int sutunSayisi, CellStyle s) {
      for (var c = 0; c < sutunSayisi; c++) {
        sayfa
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
            .cellStyle = s;
      }
    }

    final baslikStili = CellStyle(bold: true, fontSize: 14);
    final kalin = CellStyle(bold: true);
    final bolumStili = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#C8E6C9'),
    );
    final sutunStili = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#E0E0E0'),
    );

    // Başlık
    stil(ekle([TextCellValue(rapor.baslik)]), 1, baslikStili);
    ekle([TextCellValue(rapor.altBaslik)]);
    ekle([]);

    // Özet
    if (rapor.ozet.isNotEmpty) {
      for (final e in rapor.ozet) {
        final r = ekle([TextCellValue(e.key), _hucre(int.tryParse(e.value) ?? e.value)]);
        stil(r, 1, kalin);
      }
      ekle([]);
    }

    // Bölümler
    var enGenis = rapor.sutunlar.length;
    for (final b in rapor.bolumler) {
      final sutunlar = b.sutunlariAl(rapor);
      if (sutunlar.length > enGenis) enGenis = sutunlar.length;

      if (b.baslik != null) {
        stil(ekle([TextCellValue(b.baslik!)]), sutunlar.length, bolumStili);
      }
      if (b.aciklama != null) ekle([TextCellValue(b.aciklama!)]);
      if (b.satirlar.isEmpty) {
        ekle([TextCellValue('Kayıt yok')]);
      } else {
        stil(ekle([for (final s in sutunlar) TextCellValue(s)]),
            sutunlar.length, sutunStili);
        for (final s in b.satirlar) {
          ekle([for (final h in s) _hucre(h)]);
        }
      }
      ekle([]);
    }

    // Sütun genişlikleri: raporun ve bölümlerin en genişi
    for (var i = 0; i < enGenis; i++) {
      var g = i < rapor.genislikler.length ? rapor.genislikler[i] : 12.0;
      for (final b in rapor.bolumler) {
        final bg = b.genislikleriAl(rapor);
        if (i < bg.length && bg[i] > g) g = bg[i];
      }
      sayfa.setColumnWidth(i, g < 14 ? 14 : g);
    }

    final dosyaAdi =
        '${rapor.dosyaOn}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx';

    // iPhone'da (Safari) indirme yerine Paylaş menüsü açılır.
    if (kIsWeb && !iosTarayici()) {
      excel.save(fileName: dosyaAdi); // tarayıcıda indirir
      return;
    }

    final bytes = excel.encode();
    if (bytes == null) throw StateError('Excel dosyası oluşturulamadı');
    await Share.shareXFiles(
      [
        XFile.fromData(
          Uint8List.fromList(bytes),
          name: dosyaAdi,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ],
      fileNameOverrides: [dosyaAdi],
      subject: rapor.baslik,
    );
  }

  static CellValue _hucre(Object? v) {
    if (v is RaporLink) {
      final url = v.url.replaceAll('"', '');
      final metin = v.metin.replaceAll('"', "'");
      return FormulaCellValue('HYPERLINK("$url","$metin")');
    }
    if (v is int) return IntCellValue(v);
    if (v is double) return DoubleCellValue(v);
    return TextCellValue(v?.toString() ?? '');
  }
}
