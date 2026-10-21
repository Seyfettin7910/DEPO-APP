import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:http/http.dart' as http;

import '../database/app_database.dart';
import 'bolge_adi.dart';

/// İl / ilçe / mahalle (köy) bilgisi.
class Adres {
  const Adres({this.il, this.ilce, this.mahalle});

  final String? il;
  final String? ilce;
  final String? mahalle;

  bool get bos =>
      (il ?? '').isEmpty && (ilce ?? '').isEmpty && (mahalle ?? '').isEmpty;

  /// "Kayalar Mah., Merkez / Kırşehir" biçiminde kısa metin.
  String get ozet {
    final bolge = [
      if ((ilce ?? '').isNotEmpty) ilce,
      if ((il ?? '').isNotEmpty) il,
    ].join(' / ');
    return [
      if ((mahalle ?? '').isNotEmpty) mahalle,
      if (bolge.isNotEmpty) bolge,
    ].join(', ');
  }
}

/// GPS koordinatından il / ilçe / mahalle bulur (OpenStreetMap Nominatim).
/// Kullanım kuralı gereği saniyede en fazla 1 istek gönderilir.
class AdresServisi {
  static DateTime _sonIstek = DateTime.fromMillisecondsSinceEpoch(0);

  /// İnternet/sunucu hatasında null; başarılı ama adres yoksa boş [Adres].
  static Future<Adres?> konumdanAdres(double enlem, double boylam) async {
    final bekle =
        1100 - DateTime.now().difference(_sonIstek).inMilliseconds;
    if (bekle > 0) await Future.delayed(Duration(milliseconds: bekle));
    _sonIstek = DateTime.now();
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': enlem.toStringAsFixed(6),
        'lon': boylam.toStringAsFixed(6),
        'zoom': '18',
        'addressdetails': '1',
        'accept-language': 'tr',
      });
      final r = await http.get(uri,
          headers: kIsWeb
              ? const {}
              : const {'User-Agent': 'DepoTakip/1.14 (belediye depo takip)'})
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return null;
      final govde = jsonDecode(r.body);
      if (govde is! Map || govde['address'] is! Map) return const Adres();
      final a = Map<String, dynamic>.from(govde['address'] as Map);

      String? ilk(List<String> anahtarlar) {
        for (final k in anahtarlar) {
          final v = a[k];
          // 1.29.1: otomatik dolan her şey büyük harf.
          if (v is String && v.trim().isNotEmpty) return trBuyuk(v.trim());
        }
        return null;
      }

      final il = ilk(['province', 'state', 'city']);
      final ilce = ilk(
          ['town', 'county', 'city_district', 'district', 'municipality', 'city']);
      final mahalle = ilk(
          ['neighbourhood', 'suburb', 'quarter', 'village', 'hamlet', 'residential']);
      return Adres(il: il, ilce: ilce == il ? null : ilce, mahalle: mahalle);
    } catch (e) {
      debugPrint('Adres bulunamadı: $e');
      return null;
    }
  }
}

/// Konumu kayıtlı ama il/ilçe/mahallesi henüz bulunmamış ya da "Nerede
/// kullanıldı?"sı boş bırakılmış (internetsiz) montajları internet gelince
/// arka planda tamamlar. Yer adı: önce 15 m içindeki eski montajın adı, yoksa
/// "İLÇE MAHALLE"; o da bulunamazsa koordinat.
class AdresTamamlayici {
  static bool _calisiyor = false;

  static Future<void> calistir(AppDatabase db, {int enFazla = 15}) async {
    if (_calisiyor) return;
    _calisiyor = true;
    try {
      final eksikler = await db.adresiEksikKullanimlar(limit: enFazla);
      for (final r in eksikler) {
        final id = r['id'] as String;
        final enlem = (r['enlem'] as num).toDouble();
        final boylam = (r['boylam'] as num).toDouble();
        final yerBos = ((r['kullanim_yeri'] as String?) ?? '').trim().isEmpty;
        String? ilce = r['ilce'] as String?;
        String? mahalle = r['mahalle'] as String?;
        // Yer adı boşsa önce yakındaki eski montajın adı (internetsiz).
        final hassasiyet = (r['konum_hassasiyet'] as num?)?.toDouble();
        if (yerBos && hassasiyet != null && hassasiyet <= 15) {
          final yakin = await db.yakindakiKullanimYerleri(enlem, boylam);
          if (yakin.isNotEmpty) {
            await db.kullanimYeriTamamla(id, yakin.first);
            if (ilce != null || mahalle != null) continue;
          }
        }
        if (ilce == null && mahalle == null) {
          final adres = await AdresServisi.konumdanAdres(enlem, boylam);
          if (adres == null) break; // internet yok: sonra tekrar denenir
          await db.kullanimAdresiTamamla(id, adres.il, adres.ilce, adres.mahalle);
          ilce = adres.ilce;
          mahalle = adres.mahalle;
        }
        if (yerBos) {
          final yer = yerMetni(ilce, mahalle);
          await db.kullanimYeriTamamla(
              id,
              yer.isNotEmpty
                  ? yer
                  : '${enlem.toStringAsFixed(5)}, ${boylam.toStringAsFixed(5)}');
        }
      }
    } catch (e) {
      debugPrint('Adres tamamlama hatası: $e');
    } finally {
      _calisiyor = false;
    }
  }
}
