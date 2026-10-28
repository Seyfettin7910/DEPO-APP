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

  // PDF çıktısındaki renkler (pdf paketinin PdfColors değerleri).
  static const _gri700 = '616161';
  static const _gri800 = '424242';
  static const _gri600 = '757575';
  static const _gri400 = 'BDBDBD';
  static const _gri300 = 'E0E0E0'; // tablo başlığı
  static const _gri50 = 'F5F5F5'; // tek satırlar (PDF'te biraz daha açık)
  static const _yesil50 = 'E8F5E9'; // özet kutuları
  static const _yesil100 = 'C8E6C9'; // bölüm başlığı

  static const _baslik = XlsxBicim(kalin: true, boyut: 16);
  static const _ayirici = XlsxBicim(altCizgi: _gri400);
  static const _altBaslikAyirici =
      XlsxBicim(boyut: 9, yaziRengi: _gri700, altCizgi: _gri400);
  // 1.30.6: her özet kutusu ayrı çerçeveli (Seyfettin'in Excel 2007'de
  // çizdiği gibi): etiketin üstü ve yanları, rakamın altı ve yanları.
  static const _ozetEtiket = XlsxBicim(
      boyut: 8, yaziRengi: _gri700, dolgu: _yesil50, kutu: XlsxKutu.ust);
  static const _ozetDeger = XlsxBicim(
      kalin: true, boyut: 14, dolgu: _yesil50, kutu: XlsxKutu.alt);
  static const _bolum = XlsxBicim(kalin: true, boyut: 11, dolgu: _yesil100);
  static const _aciklama = XlsxBicim(boyut: 9, yaziRengi: _gri800);
  static const _kayitYok = XlsxBicim(boyut: 9, yaziRengi: _gri600);
  static const _sutun = XlsxBicim(
      kalin: true, boyut: 10, dolgu: _gri300, kenarlik: true, kaydir: true);
  static const _hucre = XlsxBicim(boyut: 10, kenarlik: true, kaydir: true);
  static const _hucreTek =
      XlsxBicim(boyut: 10, dolgu: _gri50, kenarlik: true, kaydir: true);

  /// Raporun .xlsx baytları (test ve paylaşım için). Düzen PDF çıktısıyla
  /// aynı: başlık, gri alt başlık ve çizgi, yeşil özet kutuları, yeşil bölüm
  /// başlıkları, gri zeminli tablo başlığı, çizgili tablo, bir açık bir
  /// beyaz satırlar. Tek tablolu raporda tablo başlığı kaydırınca sabit
  /// kalır ve yazdırırken her sayfada tekrarlanır.
  static Uint8List olustur(Rapor rapor) {
    final x = XlsxYazici(sayfaAdi: 'Rapor')
      ..yatay = rapor.yatay
      ..altBilgi = 'DEPO YÖNETİM SİSTEMİ';

    var enGenis = rapor.sutunlar.length;
    for (final b in rapor.bolumler) {
      final n = b.sutunlariAl(rapor).length;
      if (n > enGenis) enGenis = n;
    }
    if (enGenis < 1) enGenis = 1;

    // Başlık, alt başlık, ayırıcı çizgi
    x.satirEkle([rapor.baslik], bicim: _baslik);
    final alt = x.satirEkle([rapor.altBaslik], bicim: _altBaslikAyirici);
    for (var c = 1; c < enGenis; c++) {
      x.hucreBicimi(alt, c, _ayirici);
    }
    x.satirEkle([]);

    // Özet kutuları: yan yana, üstte küçük gri etiket, altta büyük değer.
    if (rapor.ozet.isNotEmpty) {
      for (var bas = 0; bas < rapor.ozet.length; bas += enGenis) {
        final parca = rapor.ozet.skip(bas).take(enGenis).toList();
        x.satirEkle([for (final e in parca) e.key], bicim: _ozetEtiket);
        x.satirEkle([
          for (final e in parca) int.tryParse(e.value) ?? e.value,
        ], bicim: _ozetDeger);
      }
      x.satirEkle([]);
    }

    // Bölümler
    final tablolu = rapor.bolumler.where((b) => b.satirlar.isNotEmpty);
    final tekTablo = tablolu.length == 1;
    for (final b in rapor.bolumler) {
      final sutunlar = b.sutunlariAl(rapor);
      if (b.baslik != null) {
        final r = x.satirEkle([b.baslik!]);
        x.bicimVer(r, sutunlar.length, _bolum);
      }
      if (b.aciklama != null) {
        x.satirEkle([b.aciklama!], bicim: _aciklama);
      }
      if (b.satirlar.isEmpty) {
        x.satirEkle(['Kayıt yok'], bicim: _kayitYok);
      } else {
        final r = x.satirEkle(sutunlar, bicim: _sutun);
        if (tekTablo) {
          x
            ..dondurulanSatir = r + 1
            ..yazdirmaBasligi = r;
        }
        for (var i = 0; i < b.satirlar.length; i++) {
          final satir = x.satirEkle([for (final h in b.satirlar[i]) _deger(h)]);
          // Kısa satırlarda da tablo çizgisi tam olsun.
          x.bicimVer(satir, sutunlar.length, i.isOdd ? _hucreTek : _hucre);
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

  static Object? _deger(Object? v) {
    if (v is RaporLink) return XlsxBaglanti(v.metin, v.url);
    if (v is int || v is double) return v;
    return v?.toString() ?? '';
  }
}
