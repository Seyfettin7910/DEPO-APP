part of 'app_database.dart';

/// Ürün birleştirme (1.30.0): aynı ürün iki kez tanımlanmışsa ("HİKVİSİON
/// 7104…" / "HIKVISION 7104…") biri diğerine katılır.
///
/// - Cihazlar, stok hareketleri ve servis kayıtları kalan ürüne bağlanır.
///   HİÇBİR hareket kaydı silinmez; yalnız bağlı olduğu ürün değişir.
/// - Malzemede stok hareketlerden hesaplandığı için kendiliğinden toplanır.
/// - Kalan üründe barkod / kutu içeriği / kategori boşsa birleşenden alınır.
/// - Birleşen ürün silinmiş işaretlenir ve `birlesti_id` ile kalan ürünü
///   gösterir. İnternetsizken eski ürünle kaydedilmiş cihaz / hareket
///   sonradan gelirse [birlesenleriAktar] onu kalan ürüne aktarır.
/// - Seri no ile takip edilen ürün, miktarla takip edilen malzemeyle
///   birleştirilemez.
class BirlestirmeOzeti {
  const BirlestirmeOzeti(
      {required this.cihaz, required this.hareket, required this.servis});
  final int cihaz;
  final int hareket;
  final int servis;
}

extension UrunBirlestirme on AppDatabase {
  static const _bagliTablolar = [
    'cihazlar',
    'stok_hareketleri',
    'servis_kayitlari',
  ];

  /// Birleştirme onayında gösterilecek sayılar.
  Future<BirlestirmeOzeti> birlestirmeOzeti(String kaynakId) async {
    final db = await _database;
    Future<int> say(String sql) async =>
        Sqflite.firstIntValue(await db.rawQuery(sql, [kaynakId])) ?? 0;
    return BirlestirmeOzeti(
      cihaz: await say(
          'SELECT COUNT(*) FROM cihazlar WHERE urun_id = ? AND deleted = 0'),
      hareket:
          await say('SELECT COUNT(*) FROM stok_hareketleri WHERE urun_id = ?'),
      servis:
          await say('SELECT COUNT(*) FROM servis_kayitlari WHERE urun_id = ?'),
    );
  }

  /// [kaynakId] ürününü [hedefId] ürününe katar (kalan: hedef).
  Future<void> urunleriBirlestir({
    required String kaynakId,
    required String hedefId,
  }) async {
    if (kaynakId == hedefId) throw StateError('Aynı ürün seçildi');
    final db = await _database;
    final simdi = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      Future<Map<String, Object?>?> urun(String id) async {
        final r = await txn.query('urunler',
            where: 'id = ?', whereArgs: [id], limit: 1);
        return r.isEmpty ? null : r.first;
      }

      final k = await urun(kaynakId);
      final h = await urun(hedefId);
      if (k == null || h == null) throw StateError('Ürün bulunamadı');
      if ((k['deleted'] as num) == 1 || (h['deleted'] as num) == 1) {
        throw StateError('Silinmiş ürün birleştirilemez');
      }
      if ((k['seri_takipli'] as num) != (h['seri_takipli'] as num)) {
        throw StateError('Seri no ile takip edilen ürün, miktarla takip '
            'edilen malzemeyle birleştirilemez');
      }

      for (final t in _bagliTablolar) {
        await txn.rawUpdate(
            'UPDATE $t SET urun_id = ?, updated_at = ?, dirty = 1 '
            'WHERE urun_id = ?',
            [hedefId, simdi, kaynakId]);
      }
      // Eski (yalnız yerel) adet tablosu
      await txn.rawUpdate('UPDATE depo_stoklari SET urun_id = ? WHERE urun_id = ?',
          [hedefId, kaynakId]);

      // Kalan üründe boş olan bilgiler birleşenden.
      final hedefGuncel = <String, Object?>{'updated_at': simdi, 'dirty': 1};
      final kaynakGuncel = <String, Object?>{
        'deleted': 1,
        'birlesti_id': hedefId,
        'updated_at': simdi,
        'dirty': 1,
      };
      bool bos(Object? v) => v == null || (v is String && v.trim().isEmpty);
      if (bos(h['barkod']) && !bos(k['barkod'])) {
        hedefGuncel['barkod'] = k['barkod'];
        kaynakGuncel['barkod'] = null; // aynı barkod iki üründe olmasın
      }
      if (h['kutu_icerigi'] == null && k['kutu_icerigi'] != null) {
        hedefGuncel['kutu_icerigi'] = k['kutu_icerigi'];
      }
      if (bos(h['kategori']) && !bos(k['kategori'])) {
        hedefGuncel['kategori'] = k['kategori'];
      }
      await txn.update('urunler', hedefGuncel,
          where: 'id = ?', whereArgs: [hedefId]);
      await txn.update('urunler', kaynakGuncel,
          where: 'id = ?', whereArgs: [kaynakId]);
      // Daha önce birleşenle birleşmiş ürünler de artık hedefi gösterir.
      await txn.rawUpdate(
          'UPDATE urunler SET birlesti_id = ?, updated_at = ?, dirty = 1 '
          'WHERE birlesti_id = ?',
          [hedefId, simdi, kaynakId]);
    });
    _notify();
  }

  /// Birleşmiş (silinmiş) ürüne bağlı kalmış kayıtları kalan ürüne aktarır
  /// (internetsizken eski ürünle kaydedilip sonradan gelenler). Senkrondan
  /// sonra çalışır; aktarılan satır sayısını döner.
  Future<int> birlesenleriAktar() async {
    final db = await _database;
    var toplam = 0;
    // Zincir (A → B → C) için birkaç tur.
    for (var tur = 0; tur < 5; tur++) {
      final simdi = DateTime.now().millisecondsSinceEpoch;
      var n = 0;
      for (final t in _bagliTablolar) {
        n += await db.rawUpdate(
            'UPDATE $t SET urun_id = (SELECT u.birlesti_id FROM urunler u '
            'WHERE u.id = $t.urun_id), updated_at = ?, dirty = 1 '
            'WHERE urun_id IN (SELECT id FROM urunler '
            "WHERE birlesti_id IS NOT NULL AND birlesti_id <> '')",
            [simdi]);
      }
      toplam += n;
      if (n == 0) break;
    }
    if (toplam > 0) _notify();
    return toplam;
  }
}
