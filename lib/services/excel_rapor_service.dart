import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../database/app_database.dart';

/// Raporları Excel (.xlsx) dosyası olarak üretir.
/// Web'de dosya doğrudan indirilir; telefonda paylaş menüsü açılır
/// (WhatsApp, e-posta, Drive, "Dosyalara kaydet" vb.).
class ExcelRaporService {
  static final _tarih = DateFormat('dd.MM.yyyy HH:mm');
  static final _gun = DateFormat('dd.MM.yyyy');

  static const _durumAdlari = {
    'depoda': 'Depoda',
    'kullanimda': 'Sahada kullanıldı',
    'cikti': 'Çıkış yapıldı',
  };

  static const _tipAdlari = {
    'girisi': 'Giriş',
    'cikis': 'Çıkış',
    'transfer': 'Transfer',
    'kullanim': 'Kullanım',
    'iade': 'İade',
  };

  // ------------------------------------------------------------------
  // Raporlar
  // ------------------------------------------------------------------

  static Future<void> kullanimRaporu(
    List<KullanimRaporSatiri> satirlar, {
    DateTime? baslangic,
    DateTime? bitis,
  }) {
    final basliklar = ['Tarih', 'Seri No', 'Ürün', 'Çıktığı yer',
        'Kullanım yeri / Araç', 'Adet'];
    final veri = [
      for (final s in satirlar)
        [
          _tarih.format(s.tarih),
          s.seriNo ?? '',
          s.urunAdi,
          s.depoAdi,
          s.aracPlaka ?? s.kullanimYeri ?? 'Belirtilmedi',
          s.miktar,
        ],
    ];
    return _olusturVePaylas(
      sayfaAdi: 'Kullanım',
      baslik: 'Kullanım Raporu${_aralik(baslangic, bitis)}',
      basliklar: basliklar,
      satirlar: veri,
      genislikler: [18, 22, 30, 22, 32, 8],
      dosyaOn: 'kullanim_raporu',
    );
  }

  static Future<void> cihazListesi(List<Map<String, Object?>> rows) {
    final basliklar = ['Seri No', 'Ürün', 'Kategori', 'Durum', 'Konum',
        'Konum türü', 'Kullanım yeri', 'Son değişiklik'];
    final veri = [
      for (final r in rows)
        [
          r['seri_no'] ?? '',
          r['urun_adi'] ?? '',
          r['kategori'] ?? '',
          _durumAdlari[r['durum']] ?? (r['durum'] ?? ''),
          r['depo_adi'] ?? '',
          r['depo_adi'] == null ? '' : (r['depo_tur'] == 'arac' ? 'Araç' : 'Depo'),
          r['kullanim_yeri'] ?? '',
          r['guncelleme'] == null
              ? ''
              : _tarih.format(DateTime.fromMillisecondsSinceEpoch(
                  (r['guncelleme'] as num).toInt())),
        ],
    ];
    return _olusturVePaylas(
      sayfaAdi: 'Cihazlar',
      baslik: 'Cihaz Listesi (${_gun.format(DateTime.now())})',
      basliklar: basliklar,
      satirlar: veri,
      genislikler: [22, 30, 18, 18, 24, 12, 30, 18],
      dosyaOn: 'cihaz_listesi',
    );
  }

  static Future<void> hareketRaporu(
    List<Map<String, Object?>> rows, {
    DateTime? baslangic,
    DateTime? bitis,
  }) {
    final basliklar = ['Tarih', 'İşlem', 'Seri No', 'Ürün', 'Nereden',
        'Nereye', 'Kullanım yeri', 'Kullanıcı', 'Not'];
    final veri = [
      for (final r in rows)
        [
          _tarih.format(DateTime.fromMillisecondsSinceEpoch(
              (r['tarih'] as num).toInt())),
          _tipAdlari[r['tip']] ?? (r['tip'] ?? ''),
          r['seri_no'] ?? '',
          r['urun_adi'] ?? '',
          r['kaynak'] ?? '',
          r['hedef'] ?? '',
          r['kullanim_yeri'] ?? '',
          r['kullanici'] ?? '',
          r['not_'] ?? '',
        ],
    ];
    return _olusturVePaylas(
      sayfaAdi: 'Hareketler',
      baslik: 'Hareket Geçmişi${_aralik(baslangic, bitis)}',
      basliklar: basliklar,
      satirlar: veri,
      genislikler: [18, 12, 22, 30, 22, 22, 28, 18, 30],
      dosyaOn: 'hareket_gecmisi',
    );
  }

  // ------------------------------------------------------------------
  // Ortak
  // ------------------------------------------------------------------

  static String _aralik(DateTime? bas, DateTime? bit) {
    if (bas == null && bit == null) return '';
    return ' (${bas == null ? '...' : _gun.format(bas)} - '
        '${bit == null ? '...' : _gun.format(bit)})';
  }

  static CellValue _hucre(Object? v) {
    if (v is int) return IntCellValue(v);
    if (v is double) return DoubleCellValue(v);
    return TextCellValue(v?.toString() ?? '');
  }

  static Future<void> _olusturVePaylas({
    required String sayfaAdi,
    required String baslik,
    required List<String> basliklar,
    required List<List<Object?>> satirlar,
    required List<double> genislikler,
    required String dosyaOn,
  }) async {
    final excel = Excel.createExcel();
    final varsayilan = excel.getDefaultSheet();
    if (varsayilan != null && varsayilan != sayfaAdi) {
      excel.rename(varsayilan, sayfaAdi);
    }
    final sayfa = excel[sayfaAdi];

    // 1. satır: rapor başlığı, 2. satır boş, 3. satır sütun başlıkları
    sayfa.appendRow([TextCellValue(baslik)]);
    sayfa.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
        .cellStyle = CellStyle(bold: true, fontSize: 14);
    sayfa.appendRow([TextCellValue('')]);
    sayfa.appendRow([for (final b in basliklar) TextCellValue(b)]);
    final baslikStili = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#D9EAD3'),
    );
    for (var i = 0; i < basliklar.length; i++) {
      sayfa.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 2))
          .cellStyle = baslikStili;
    }

    for (final satir in satirlar) {
      sayfa.appendRow([for (final v in satir) _hucre(v)]);
    }
    sayfa.appendRow([TextCellValue('')]);
    sayfa.appendRow([TextCellValue('Toplam kayıt: ${satirlar.length}')]);

    for (var i = 0; i < genislikler.length; i++) {
      sayfa.setColumnWidth(i, genislikler[i]);
    }

    final dosyaAdi =
        '${dosyaOn}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx';

    if (kIsWeb) {
      // Tarayıcıda doğrudan indirir.
      excel.save(fileName: dosyaAdi);
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
      subject: baslik,
    );
  }
}
