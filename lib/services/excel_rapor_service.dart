import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'tarayici.dart';
import 'xlsx_yazici.dart';

import 'rapor/rapor_modeli.dart';

/// Ortak [Rapor] nesnesini Excel (.xlsx) dosyasına döker. PDF çıktısıyla
/// aynı başlık, sütun ve satırları kullanır.
/// Web'de dosya doğrudan iner; telefonda paylaş menüsü açılır.
///
/// 1.30.4: dosya [XlsxYazici] ile yazılır (Excel 2007 ve sonrası açar).
class ExcelRaporService {
  static const _tur =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  /// Raporun .xlsx baytları (test ve paylaşım için).
  static Uint8List olustur(Rapor rapor) {
    final x = XlsxYazici(sayfaAdi: 'Rapor');

    // Başlık
    x.stilVer(x.satirEkle([rapor.baslik]), 1, XlsxStil.baslik);
    x.satirEkle([rapor.altBaslik]);
    x.satirEkle([]);

    // Özet
    if (rapor.ozet.isNotEmpty) {
      for (final e in rapor.ozet) {
        final r = x.satirEkle([e.key, _hucre(int.tryParse(e.value) ?? e.value)]);
        x.stilVer(r, 1, XlsxStil.kalin);
      }
      x.satirEkle([]);
    }

    // Bölümler
    var enGenis = rapor.sutunlar.length;
    for (final b in rapor.bolumler) {
      final sutunlar = b.sutunlariAl(rapor);
      if (sutunlar.length > enGenis) enGenis = sutunlar.length;

      if (b.baslik != null) {
        x.stilVer(x.satirEkle([b.baslik!]), sutunlar.length, XlsxStil.bolum);
      }
      if (b.aciklama != null) x.satirEkle([b.aciklama!]);
      if (b.satirlar.isEmpty) {
        x.satirEkle(['Kayıt yok']);
      } else {
        x.stilVer(x.satirEkle(sutunlar), sutunlar.length, XlsxStil.sutun);
        for (final s in b.satirlar) {
          x.satirEkle([for (final h in s) _hucre(h)]);
        }
      }
      x.satirEkle([]);
    }

    // Sütun genişlikleri: raporun ve bölümlerin en genişi
    for (var i = 0; i < enGenis; i++) {
      var g = i < rapor.genislikler.length ? rapor.genislikler[i] : 12.0;
      for (final b in rapor.bolumler) {
        final bg = b.genislikleriAl(rapor);
        if (i < bg.length && bg[i] > g) g = bg[i];
      }
      x.sutunGenisligi(i, g < 14 ? 14 : g);
    }
    return x.kaydet();
  }

  static Future<void> paylas(Rapor rapor) async {
    final bytes = olustur(rapor);
    final dosyaAdi =
        '${rapor.dosyaOn}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx';

    // Bilgisayar tarayıcısında doğrudan iner; iPhone'da (Safari) Paylaş
    // menüsü açılır.
    if (kIsWeb && !iosTarayici() && dosyaIndir(bytes, dosyaAdi, _tur)) return;

    await Share.shareXFiles(
      [XFile.fromData(bytes, name: dosyaAdi, mimeType: _tur)],
      fileNameOverrides: [dosyaAdi],
      subject: rapor.baslik,
    );
  }

  static Object? _hucre(Object? v) {
    if (v is RaporLink) return XlsxBaglanti(v.metin, v.url);
    if (v is int || v is double) return v;
    return v?.toString() ?? '';
  }
}
