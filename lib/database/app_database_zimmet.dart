part of 'app_database.dart';

/// 1.32.0: Belediye zimmeti için Başkanlık onayı (bkz. services/zimmet_onayi.dart).
///
/// * Montaj / kullanım kaydında `zimmet_yeri` (hizmet | kirsal) ve
///   `onay_evrak_sayisi` tutulur (kullanim_kayitlari, silinmez).
/// * Onay olmadan kırsal mahallede kullanma girişimleri `zimmet_girisimleri`
///   tablosuna yazılır (senkronlanır; bildirim ve rapor için). Kayıt
///   değiştirilmez, silinmez.
const _zimmetTabloSql = '''
CREATE TABLE IF NOT EXISTS zimmet_girisimleri (
  id TEXT PRIMARY KEY,
  kullanici_id TEXT,
  tarih INTEGER NOT NULL,
  depo_id TEXT,
  icerik TEXT,
  kullanim_yeri TEXT,
  il TEXT,
  ilce TEXT,
  mahalle TEXT,
  enlem REAL,
  boylam REAL,
  updated_at INTEGER NOT NULL,
  dirty INTEGER NOT NULL DEFAULT 1,
  deleted INTEGER NOT NULL DEFAULT 0
)
''';

extension ZimmetVeritabani on AppDatabase {
  /// Onay olmadan kırsal mahallede kullanma girişimini kaydeder.
  /// [icerik]: "KAMERA (SN123), NVR (SN456)" gibi özet.
  Future<void> zimmetGirisimiKaydet({
    required String kullaniciId,
    String? depoId,
    required String icerik,
    String? kullanimYeri,
    String? il,
    String? ilce,
    String? mahalle,
    double? enlem,
    double? boylam,
  }) async {
    final db = await _database;
    final simdi = DateTime.now().millisecondsSinceEpoch;
    String? bos(String? v) => (v ?? '').trim().isEmpty ? null : v!.trim();
    await db.insert('zimmet_girisimleri', {
      'id': _uuid.v4(),
      'kullanici_id': kullaniciId,
      'tarih': simdi,
      'depo_id': depoId,
      'icerik': icerik,
      'kullanim_yeri': bos(kullanimYeri),
      'il': bos(il),
      'ilce': bos(ilce),
      'mahalle': bos(mahalle),
      'enlem': enlem,
      'boylam': boylam,
      'updated_at': simdi,
      'dirty': 1,
      'deleted': 0,
    });
    _notify();
  }

  /// Kırsal mahallede (Başkanlık onayıyla) kullanılan zimmet ürünleri.
  Future<List<Map<String, Object?>>> zimmetKirsalKullanimlari({
    DateTime? baslangic,
    DateTime? bitis,
  }) async {
    final db = await _database;
    final kosullar = <String>[
      'kk.deleted = 0',
      'sh.deleted = 0',
      "kk.zimmet_yeri = '$zimmetYeriKirsal'",
    ];
    final args = <Object?>[];
    if (baslangic != null) {
      kosullar.add('sh.tarih >= ?');
      args.add(baslangic.millisecondsSinceEpoch);
    }
    if (bitis != null) {
      kosullar.add('sh.tarih <= ?');
      args.add(bitis.millisecondsSinceEpoch);
    }
    return db.rawQuery('''
      SELECT sh.tarih AS tarih, sh.miktar AS miktar, sh.cihaz_id AS cihaz_id,
             c.seri_no AS seri_no, u.ad AS urun_adi, u.birim AS birim,
             u.seri_takipli AS seri_takipli, d.ad AS depo_adi,
             kk.kullanim_yeri AS kullanim_yeri, kk.il AS il, kk.ilce AS ilce,
             kk.mahalle AS mahalle, kk.onay_evrak_sayisi AS evrak,
             k.ad AS kullanici
      FROM kullanim_kayitlari kk
      JOIN stok_hareketleri sh ON sh.id = kk.stok_hareket_id
      LEFT JOIN cihazlar c ON c.id = sh.cihaz_id
      LEFT JOIN urunler u ON u.id = sh.urun_id
      LEFT JOIN depolar d ON d.id = sh.depo_id
      LEFT JOIN kullanicilar k ON k.id = sh.kullanici_id
      WHERE ${kosullar.join(' AND ')}
      ORDER BY sh.tarih DESC
    ''', args);
  }

  /// Onay olmadığı için kaydedilmeyen girişimler.
  Future<List<Map<String, Object?>>> zimmetGirisimleri({
    DateTime? baslangic,
    DateTime? bitis,
  }) async {
    final db = await _database;
    final kosullar = <String>['g.deleted = 0'];
    final args = <Object?>[];
    if (baslangic != null) {
      kosullar.add('g.tarih >= ?');
      args.add(baslangic.millisecondsSinceEpoch);
    }
    if (bitis != null) {
      kosullar.add('g.tarih <= ?');
      args.add(bitis.millisecondsSinceEpoch);
    }
    return db.rawQuery('''
      SELECT g.tarih AS tarih, g.icerik AS icerik, g.kullanim_yeri AS kullanim_yeri,
             g.il AS il, g.ilce AS ilce, g.mahalle AS mahalle,
             d.ad AS depo_adi, k.ad AS kullanici
      FROM zimmet_girisimleri g
      LEFT JOIN depolar d ON d.id = g.depo_id
      LEFT JOIN kullanicilar k ON k.id = g.kullanici_id
      WHERE ${kosullar.join(' AND ')}
      ORDER BY g.tarih DESC
    ''', args);
  }

  /// Bildirim motoru için: [sonrasi]'ndan sonraki girişimler.
  Future<List<Map<String, Object?>>> bildirimZimmetGirisimleri(
      int sonrasi) async {
    final db = await _database;
    return db.rawQuery('''
      SELECT g.id AS id, g.tarih AS tarih, g.kullanici_id AS kullanici_id,
             g.icerik AS icerik, g.kullanim_yeri AS kullanim_yeri,
             g.ilce AS ilce, g.mahalle AS mahalle, k.ad AS kullanici
      FROM zimmet_girisimleri g
      LEFT JOIN kullanicilar k ON k.id = g.kullanici_id
      WHERE g.tarih > ? AND g.deleted = 0
      ORDER BY g.tarih
    ''', [sonrasi]);
  }
}

/// [depoId] Belediye Zimmeti deposu mu? (işlem içinden)
Future<bool> _zimmetDeposuTxn(DatabaseExecutor ex, String? depoId) async {
  if (depoId == null) return false;
  final r = await ex.query('depolar',
      columns: ['ad'], where: 'id = ?', whereArgs: [depoId], limit: 1);
  return r.isNotEmpty && zimmetDeposuMu(r.first['ad'] as String?);
}
