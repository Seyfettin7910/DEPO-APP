part of 'app_database.dart';

/// 1.35.0: Genel sayım (bkz. services/genel_sayim.dart).
///
/// Sayım ekranında "Bitir" denince sonuç `sayimlar` tablosuna yazılır
/// (senkronlanır). Kayıt değiştirilmez, silinmez; Raporlar → "Genel sayım"
/// tarih aralığındaki sayımları birleştirir.
const _sayimTabloSql = '''
CREATE TABLE IF NOT EXISTS sayimlar (
  id TEXT PRIMARY KEY,
  kullanici_id TEXT,
  depo_id TEXT NOT NULL,
  depo_adi TEXT,
  baslangic INTEGER,
  tarih INTEGER NOT NULL,
  olmali INTEGER NOT NULL DEFAULT 0,
  bulunan INTEGER NOT NULL DEFAULT 0,
  eksik INTEGER NOT NULL DEFAULT 0,
  fazla INTEGER NOT NULL DEFAULT 0,
  icerik TEXT,
  updated_at INTEGER NOT NULL,
  dirty INTEGER NOT NULL DEFAULT 1,
  deleted INTEGER NOT NULL DEFAULT 0
)
''';

extension SayimVeritabani on AppDatabase {
  /// Biten sayımı kaydeder.
  Future<void> sayimKaydet({
    required String kullaniciId,
    required String depoId,
    required String depoAdi,
    required DateTime baslangic,
    required SayimIcerigi icerik,
  }) async {
    final db = await _database;
    final simdi = DateTime.now().millisecondsSinceEpoch;
    await db.insert('sayimlar', {
      'id': _uuid.v4(),
      'kullanici_id': kullaniciId,
      'depo_id': depoId,
      'depo_adi': depoAdi,
      'baslangic': baslangic.millisecondsSinceEpoch,
      'tarih': simdi,
      'olmali': icerik.bulunan.length + icerik.eksik.length,
      'bulunan': icerik.bulunan.length,
      'eksik': icerik.eksik.length,
      'fazla': icerik.fazla.length,
      'icerik': icerik.json(),
      'updated_at': simdi,
      'dirty': 1,
      'deleted': 0,
    });
    _notify();
  }

  /// Tarih aralığındaki (Bitir anına göre) sayımlar.
  Future<List<SayimKaydi>> sayimKayitlari({
    DateTime? baslangic,
    DateTime? bitis,
  }) async {
    final db = await _database;
    final kosullar = <String>['s.deleted = 0'];
    final args = <Object?>[];
    if (baslangic != null) {
      kosullar.add('s.tarih >= ?');
      args.add(baslangic.millisecondsSinceEpoch);
    }
    if (bitis != null) {
      kosullar.add('s.tarih <= ?');
      args.add(bitis.millisecondsSinceEpoch);
    }
    final rows = await db.rawQuery('''
      SELECT s.depo_id AS depo_id, COALESCE(d.ad, s.depo_adi) AS depo_adi,
             s.tarih AS tarih, s.icerik AS icerik, k.ad AS kullanici
      FROM sayimlar s
      LEFT JOIN depolar d ON d.id = s.depo_id
      LEFT JOIN kullanicilar k ON k.id = s.kullanici_id
      WHERE ${kosullar.join(' AND ')}
      ORDER BY s.tarih
    ''', args);
    return [
      for (final r in rows)
        SayimKaydi(
          depoId: r['depo_id'] as String,
          depoAdi: (r['depo_adi'] as String?) ?? '-',
          tarih: DateTime.fromMillisecondsSinceEpoch(
              (r['tarih'] as num).toInt()),
          kullanici: r['kullanici'] as String?,
          icerik: SayimIcerigi.coz(r['icerik'] as String?),
        ),
    ];
  }
}
