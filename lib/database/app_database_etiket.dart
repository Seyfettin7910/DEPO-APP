part of 'app_database.dart';

/// Kurum etiketi tabloları (şema sürümü 11). Hepsi sunucuyla senkronize
/// edilir; etiket geçmişi (etiket_hareketleri) silinemez.
const _etiketTabloSql = [
  '''
CREATE TABLE IF NOT EXISTS kurum_kodlari (
  id TEXT PRIMARY KEY,
  kod TEXT NOT NULL,
  ad TEXT,
  aktif INTEGER NOT NULL DEFAULT 1,
  sira INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  dirty INTEGER NOT NULL DEFAULT 1,
  deleted INTEGER NOT NULL DEFAULT 0
)''',
  '''
CREATE TABLE IF NOT EXISTS kurum_ayarlari (
  id TEXT PRIMARY KEY,
  deger TEXT,
  updated_at INTEGER NOT NULL,
  dirty INTEGER NOT NULL DEFAULT 1,
  deleted INTEGER NOT NULL DEFAULT 0
)''',
  '''
CREATE TABLE IF NOT EXISTS etiketler (
  id TEXT PRIMARY KEY,
  cihaz_id TEXT NOT NULL,
  kod TEXT NOT NULL UNIQUE,
  kurum_kodu_id TEXT,
  surum INTEGER NOT NULL DEFAULT 1,
  durum TEXT NOT NULL,
  seri_nosuz INTEGER NOT NULL DEFAULT 0,
  olusturma INTEGER NOT NULL,
  kullanici_id TEXT,
  updated_at INTEGER NOT NULL,
  dirty INTEGER NOT NULL DEFAULT 1,
  deleted INTEGER NOT NULL DEFAULT 0
)''',
  'CREATE INDEX IF NOT EXISTS etiketler_cihaz_idx ON etiketler (cihaz_id)',
  'CREATE INDEX IF NOT EXISTS etiketler_durum_idx ON etiketler (durum)',
  '''
CREATE TABLE IF NOT EXISTS etiket_hareketleri (
  id TEXT PRIMARY KEY,
  etiket_id TEXT NOT NULL,
  cihaz_id TEXT NOT NULL,
  islem TEXT NOT NULL,
  surum INTEGER,
  aciklama TEXT,
  kullanici_id TEXT,
  tarih INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  dirty INTEGER NOT NULL DEFAULT 1,
  deleted INTEGER NOT NULL DEFAULT 0
)''',
  'CREATE INDEX IF NOT EXISTS etiket_hareketleri_cihaz_idx ON etiket_hareketleri (cihaz_id)',
  'CREATE INDEX IF NOT EXISTS etiket_hareketleri_tarih_idx ON etiket_hareketleri (tarih)',
];

const _etiketBilgiSelect = '''
  SELECT e.id AS e_id, e.cihaz_id AS cihaz_id, e.kod AS kod, e.surum AS surum,
         e.durum AS e_durum, e.seri_nosuz AS seri_nosuz,
         e.olusturma AS olusturma, e.kurum_kodu_id AS kurum_kodu_id,
         c.seri_no AS seri_no, u.ad AS urun_adi, d.ad AS depo_adi
  FROM etiketler e
  JOIN cihazlar c ON c.id = e.cihaz_id
  JOIN urunler u ON u.id = c.urun_id
  LEFT JOIN depolar d ON d.id = c.depo_id
''';

/// Yapıştırma doğrulamasının sonucu.
class EtiketDogrulamaSonucu {
  const EtiketDogrulamaSonucu({
    required this.eslesti,
    required this.beklenenSeri,
    required this.okunanSeri,
  });

  final bool eslesti;
  final String beklenenSeri;
  final String okunanSeri;
}

extension EtiketVeritabani on AppDatabase {
  // ---------------------------------------------------------------------
  // Kurum kodları
  // ---------------------------------------------------------------------

  Future<List<KurumKodu>> kurumKodlari({bool sadeceAktif = false}) async {
    final db = await _database;
    final rows = await db.query('kurum_kodlari',
        where: sadeceAktif ? 'deleted = 0 AND aktif = 1' : 'deleted = 0',
        orderBy: 'aktif DESC, sira, kod');
    return rows.map(KurumKodu.fromMap).toList();
  }

  Stream<List<KurumKodu>> kurumKodlariStream() => _watch(kurumKodlari);

  /// Yeni kurum kodu ekler veya mevcut olanı günceller. Kodun kendisi
  /// değişse bile daha önce üretilmiş etiket kodları değişmez.
  Future<void> kurumKoduKaydet({
    String? id,
    required String kod,
    required String ad,
    bool aktif = true,
  }) async {
    final duzgun = EtiketKodu.kurumKoduDuzenle(kod);
    if (duzgun == null) {
      throw StateError('Kurum kodu yalnızca harf, rakam ve tire içerebilir '
          '(en fazla 16 karakter, ör. BLD veya BLD-BIM)');
    }
    final db = await _database;
    final ayni = await db.query('kurum_kodlari',
        columns: ['id'],
        where: 'kod = ? AND deleted = 0 AND id != ?',
        whereArgs: [duzgun, id ?? '']);
    if (ayni.isNotEmpty) throw StateError('$duzgun zaten tanımlı');
    final simdi = DateTime.now().millisecondsSinceEpoch;
    if (id == null) {
      final sira = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM kurum_kodlari')) ??
          0;
      await db.insert('kurum_kodlari', {
        'id': _uuid.v4(),
        'kod': duzgun,
        'ad': ad.trim(),
        'aktif': aktif ? 1 : 0,
        'sira': sira,
        'updated_at': simdi,
        'dirty': 1,
        'deleted': 0,
      });
    } else {
      await db.update(
          'kurum_kodlari',
          {
            'kod': duzgun,
            'ad': ad.trim(),
            'aktif': aktif ? 1 : 0,
            'updated_at': simdi,
            'dirty': 1,
          },
          where: 'id = ?',
          whereArgs: [id]);
    }
    _notify();
  }

  // ---------------------------------------------------------------------
  // Kurum ayarları (herkeste aynı)
  // ---------------------------------------------------------------------

  Future<Map<String, String>> kurumAyarlari() async {
    final db = await _database;
    final rows = await db.query('kurum_ayarlari', where: 'deleted = 0');
    return {for (final r in rows) r['id'] as String: (r['deger'] as String?) ?? ''};
  }

  Stream<Map<String, String>> kurumAyarlariStream() => _watch(kurumAyarlari);

  Future<void> kurumAyariYaz(String ad, String deger) async {
    final db = await _database;
    await db.insert(
      'kurum_ayarlari',
      {
        'id': ad,
        'deger': deger,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'dirty': 1,
        'deleted': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notify();
  }

  Future<EtiketAyarlari> etiketAyarlari() async =>
      EtiketAyarlari.fromMap(await kurumAyarlari());

  // ---------------------------------------------------------------------
  // Kod üretimi
  // ---------------------------------------------------------------------

  Future<String> _kurumKoduMetniTxn(DatabaseExecutor ex, String kurumKoduId) async {
    final rows = await ex.query('kurum_kodlari',
        columns: ['kod'], where: 'id = ? AND deleted = 0', whereArgs: [kurumKoduId]);
    if (rows.isEmpty) throw StateError('Kurum kodu bulunamadı');
    return rows.first['kod'] as String;
  }

  Future<bool> _kodKullanimdaTxn(DatabaseExecutor ex, String kod) async {
    final e = await ex.query('etiketler',
        columns: ['id'], where: 'kod = ?', whereArgs: [kod], limit: 1);
    if (e.isNotEmpty) return true;
    final c = await ex.query('cihazlar',
        columns: ['id'], where: 'seri_no = ?', whereArgs: [kod], limit: 1);
    return c.isNotEmpty;
  }

  Future<String> _benzersizKodTxn(DatabaseExecutor ex, String kurumKodu,
      [Set<String> ayrica = const {}]) async {
    for (var i = 0; i < 50; i++) {
      final kod = EtiketKodu.uret(kurumKodu);
      if (ayrica.contains(kod)) continue;
      if (!await _kodKullanimdaTxn(ex, kod)) return kod;
    }
    throw StateError('Benzersiz kod üretilemedi, tekrar deneyin');
  }

  /// Seri numarası olmayan ürünler için kod üretir; bu kodlar cihazın seri
  /// numarası olarak da kullanılır (henüz kaydedilmez).
  Future<List<String>> seriNosuzKodlarUret(String kurumKoduId, int adet) async {
    final db = await _database;
    final kurum = await _kurumKoduMetniTxn(db, kurumKoduId);
    final sonuc = <String>{};
    while (sonuc.length < adet) {
      sonuc.add(await _benzersizKodTxn(db, kurum, sonuc));
    }
    return sonuc.toList();
  }

  Future<void> _etiketIslemiTxn(
    DatabaseExecutor ex, {
    required String etiketId,
    required String cihazId,
    required EtiketIslemi islem,
    int? surum,
    String? aciklama,
    required String kullaniciId,
    required DateTime zaman,
  }) async {
    final ms = zaman.millisecondsSinceEpoch;
    await ex.insert('etiket_hareketleri', {
      'id': _uuid.v4(),
      'etiket_id': etiketId,
      'cihaz_id': cihazId,
      'islem': islem.name,
      'surum': surum,
      'aciklama': aciklama,
      'kullanici_id': kullaniciId,
      'tarih': ms,
      'updated_at': ms,
      'dirty': 1,
      'deleted': 0,
    });
  }

  /// Cihaza kurum etiketi kodu üretir (cihazın etiketi zaten varsa null).
  /// [sabitKod]: seri nosuz üründe seri no olarak kullanılan kod.
  Future<String?> _etiketUretTxn(
    DatabaseExecutor ex, {
    required String cihazId,
    required String kurumKoduId,
    required bool kuyruga,
    required String kullaniciId,
    required DateTime zaman,
    String? sabitKod,
  }) async {
    final var_ = await ex.query('etiketler',
        columns: ['id'],
        where: 'cihaz_id = ? AND deleted = 0',
        whereArgs: [cihazId],
        limit: 1);
    if (var_.isNotEmpty) return null;

    final String kod;
    if (sabitKod != null) {
      final e = await ex.query('etiketler',
          columns: ['id'], where: 'kod = ?', whereArgs: [sabitKod], limit: 1);
      if (e.isNotEmpty) throw StateError('$sabitKod kodu başka bir etikette kayıtlı');
      kod = sabitKod;
    } else {
      kod = await _benzersizKodTxn(ex, await _kurumKoduMetniTxn(ex, kurumKoduId));
    }
    final id = _uuid.v4();
    final ms = zaman.millisecondsSinceEpoch;
    await ex.insert('etiketler', {
      'id': id,
      'cihaz_id': cihazId,
      'kod': kod,
      'kurum_kodu_id': kurumKoduId,
      'surum': 1,
      'durum': (kuyruga ? EtiketDurumu.kuyrukta : EtiketDurumu.kayitli).name,
      'seri_nosuz': sabitKod != null ? 1 : 0,
      'olusturma': ms,
      'kullanici_id': kullaniciId,
      'updated_at': ms,
      'dirty': 1,
      'deleted': 0,
    });
    await _etiketIslemiTxn(ex,
        etiketId: id,
        cihazId: cihazId,
        islem: EtiketIslemi.uretildi,
        surum: 1,
        aciklama: kod,
        kullaniciId: kullaniciId,
        zaman: zaman);
    if (kuyruga) {
      await _etiketIslemiTxn(ex,
          etiketId: id,
          cihazId: cihazId,
          islem: EtiketIslemi.kuyruga,
          surum: 1,
          kullaniciId: kullaniciId,
          zaman: zaman);
    }
    return id;
  }

  /// Mevcut cihazlara (etiketi olmayanlara) kod üretir. Üretilen sayıyı döner.
  Future<int> etiketUret({
    required List<String> cihazIdleri,
    required String kurumKoduId,
    required bool kuyruga,
    required String kullaniciId,
  }) async {
    final db = await _database;
    var adet = 0;
    await db.transaction((txn) async {
      final zaman = DateTime.now();
      for (final id in cihazIdleri.toSet()) {
        final e = await _etiketUretTxn(txn,
            cihazId: id,
            kurumKoduId: kurumKoduId,
            kuyruga: kuyruga,
            kullaniciId: kullaniciId,
            zaman: zaman);
        if (e != null) adet++;
      }
    });
    _notify();
    return adet;
  }

  Future<Map<String, Object?>> _etiketTxn(DatabaseExecutor ex, String etiketId) async {
    final rows = await ex.query('etiketler',
        where: 'id = ? AND deleted = 0', whereArgs: [etiketId], limit: 1);
    if (rows.isEmpty) throw StateError('Etiket bulunamadı');
    return rows.first;
  }

  Future<void> _etiketDurumYazTxn(DatabaseExecutor ex, String etiketId,
      EtiketDurumu durum, DateTime zaman, {int? surum}) async {
    await ex.update(
      'etiketler',
      {
        'durum': durum.name,
        if (surum != null) 'surum': surum,
        'updated_at': zaman.millisecondsSinceEpoch,
        'dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [etiketId],
    );
  }

  /// Kodu olan ama basılmamış etiketleri basım kuyruğuna alır.
  Future<int> kuyrugaAl({
    required List<String> etiketIdleri,
    required String kullaniciId,
  }) async {
    final db = await _database;
    var adet = 0;
    await db.transaction((txn) async {
      final zaman = DateTime.now();
      for (final id in etiketIdleri.toSet()) {
        final e = await _etiketTxn(txn, id);
        if (e['durum'] != EtiketDurumu.kayitli.name) continue;
        await _etiketDurumYazTxn(txn, id, EtiketDurumu.kuyrukta, zaman);
        await _etiketIslemiTxn(txn,
            etiketId: id,
            cihazId: e['cihaz_id'] as String,
            islem: EtiketIslemi.kuyruga,
            surum: (e['surum'] as num).toInt(),
            kullaniciId: kullaniciId,
            zaman: zaman);
        adet++;
      }
    });
    _notify();
    return adet;
  }

  /// Etiket yıprandıysa vb.: kod aynı kalır, sürüm artar, etiket yeniden
  /// basım kuyruğuna girer (eski etiket artık geçersizdir).
  Future<void> yenidenBas({
    required String etiketId,
    required String kullaniciId,
    String? sebep,
  }) async {
    final db = await _database;
    await db.transaction((txn) async {
      final e = await _etiketTxn(txn, etiketId);
      final zaman = DateTime.now();
      final durum = etiketDurumuCoz(e['durum']);
      if (durum == EtiketDurumu.kayitli) {
        // Hiç basılmamış: sürüm artmaz, yalnızca kuyruğa girer.
        await _etiketDurumYazTxn(txn, etiketId, EtiketDurumu.kuyrukta, zaman);
        await _etiketIslemiTxn(txn,
            etiketId: etiketId,
            cihazId: e['cihaz_id'] as String,
            islem: EtiketIslemi.kuyruga,
            surum: (e['surum'] as num).toInt(),
            kullaniciId: kullaniciId,
            zaman: zaman);
        return;
      }
      if (durum == EtiketDurumu.kuyrukta) return;
      final surum = (e['surum'] as num).toInt() + 1;
      await _etiketDurumYazTxn(txn, etiketId, EtiketDurumu.kuyrukta, zaman,
          surum: surum);
      await _etiketIslemiTxn(txn,
          etiketId: etiketId,
          cihazId: e['cihaz_id'] as String,
          islem: EtiketIslemi.yenidenBasim,
          surum: surum,
          aciklama: sebep,
          kullaniciId: kullaniciId,
          zaman: zaman);
    });
    _notify();
  }

  /// Bilgisayardan basılan ve düzgün çıkan etiketler.
  Future<void> basildiIsaretle({
    required List<String> etiketIdleri,
    required String kullaniciId,
  }) async {
    final db = await _database;
    await db.transaction((txn) async {
      final zaman = DateTime.now();
      for (final id in etiketIdleri.toSet()) {
        final e = await _etiketTxn(txn, id);
        if (e['durum'] != EtiketDurumu.kuyrukta.name) continue;
        final surum = (e['surum'] as num).toInt();
        await _etiketDurumYazTxn(txn, id, EtiketDurumu.basildi, zaman);
        await _etiketIslemiTxn(txn,
            etiketId: id,
            cihazId: e['cihaz_id'] as String,
            islem: EtiketIslemi.basildi,
            surum: surum,
            aciklama: surum > 1 ? 'Sürüm $surum' : null,
            kullaniciId: kullaniciId,
            zaman: zaman);
      }
    });
    _notify();
  }

  /// Yapıştırma doğrulaması: etiketin ait olduğu cihazın seri numarası ile
  /// cihazın üzerinden okutulan seri numarası karşılaştırılır.
  /// Seri nosuz üründe etiketin okutulması yeterlidir ([okunanSeri] boş).
  Future<EtiketDogrulamaSonucu> etiketDogrula({
    required String etiketId,
    required String okunanSeri,
    required String kullaniciId,
  }) async {
    final db = await _database;
    late EtiketDogrulamaSonucu sonuc;
    await db.transaction((txn) async {
      final e = await _etiketTxn(txn, etiketId);
      final cihazId = e['cihaz_id'] as String;
      final c = await _cihazTxn(txn, cihazId);
      final seriNosuz = ((e['seri_nosuz'] as num?) ?? 0).toInt() == 1;
      final okunan = _normSeri(okunanSeri);
      final eslesti = seriNosuz || okunan == c.seriNo;
      sonuc = EtiketDogrulamaSonucu(
          eslesti: eslesti, beklenenSeri: c.seriNo, okunanSeri: okunan);
      final zaman = DateTime.now();
      final surum = (e['surum'] as num).toInt();
      await _etiketDurumYazTxn(txn, etiketId,
          eslesti ? EtiketDurumu.dogrulandi : EtiketDurumu.uyusmazlik, zaman);
      await _etiketIslemiTxn(txn,
          etiketId: etiketId,
          cihazId: cihazId,
          islem: eslesti ? EtiketIslemi.dogrulandi : EtiketIslemi.uyusmazlik,
          surum: surum,
          aciklama: eslesti
              ? (seriNosuz ? 'Seri nosuz ürün' : null)
              : 'Etiket ${c.seriNo} cihazına ait; okutulan cihaz: $okunan',
          kullaniciId: kullaniciId,
          zaman: zaman);
    });
    _notify();
    return sonuc;
  }

  // ---------------------------------------------------------------------
  // Sorgular
  // ---------------------------------------------------------------------

  /// Okutulan kurum etiketini (karekod veya kod) bulur.
  Future<EtiketBilgi?> etiketBul(String hamKod) async {
    final okuma = EtiketKodu.coz(hamKod);
    final kod = okuma?.kod ?? _normSeri(hamKod);
    final db = await _database;
    final rows = await db.rawQuery(
        '$_etiketBilgiSelect WHERE e.kod = ? AND e.deleted = 0 LIMIT 1', [kod]);
    if (rows.isEmpty) return null;
    return EtiketBilgi.fromRow(rows.first);
  }

  Future<EtiketBilgi?> cihazEtiketi(String cihazId) async {
    final db = await _database;
    final rows = await db.rawQuery(
        '$_etiketBilgiSelect WHERE e.cihaz_id = ? AND e.deleted = 0 '
        'ORDER BY e.olusturma LIMIT 1',
        [cihazId]);
    if (rows.isEmpty) return null;
    return EtiketBilgi.fromRow(rows.first);
  }

  Stream<EtiketBilgi?> cihazEtiketiStream(String cihazId) =>
      _watch(() => cihazEtiketi(cihazId));

  Future<List<EtiketHareketSatiri>> etiketGecmisi(String cihazId) async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT h.islem AS islem, h.tarih AS tarih, h.aciklama AS aciklama,
             h.surum AS surum, k.ad AS kullanici
      FROM etiket_hareketleri h
      LEFT JOIN kullanicilar k ON k.id = h.kullanici_id
      WHERE h.cihaz_id = ? AND h.deleted = 0
      ORDER BY h.tarih DESC
    ''', [cihazId]);
    return [
      for (final r in rows)
        EtiketHareketSatiri(
          islem: etiketIslemiCoz(r['islem']),
          tarih: DateTime.fromMillisecondsSinceEpoch((r['tarih'] as num).toInt()),
          aciklama: r['aciklama'] as String?,
          kullaniciAdi: r['kullanici'] as String?,
        ),
    ];
  }

  Stream<List<EtiketHareketSatiri>> etiketGecmisiStream(String cihazId) =>
      _watch(() => etiketGecmisi(cihazId));

  /// Belirli durumdaki etiketler (silinmiş / çıkmış cihazlarınki hariç).
  Future<List<EtiketBilgi>> etiketListesi(EtiketDurumu durum) async {
    final db = await _database;
    final rows = await db.rawQuery(
        '$_etiketBilgiSelect WHERE e.durum = ? AND e.deleted = 0 '
        'AND c.deleted = 0 ORDER BY u.ad, d.ad, e.olusturma, e.kod',
        [durum.name]);
    return rows.map(EtiketBilgi.fromRow).toList();
  }

  Stream<List<EtiketBilgi>> etiketListesiStream(EtiketDurumu durum) =>
      _watch(() => etiketListesi(durum));

  Future<Map<EtiketDurumu, int>> etiketSayilari() async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT e.durum AS durum, COUNT(*) AS adet
      FROM etiketler e JOIN cihazlar c ON c.id = e.cihaz_id
      WHERE e.deleted = 0 AND c.deleted = 0
      GROUP BY e.durum
    ''');
    return {
      for (final r in rows)
        etiketDurumuCoz(r['durum']): (r['adet'] as num).toInt(),
    };
  }

  Stream<Map<EtiketDurumu, int>> etiketSayilariStream() => _watch(etiketSayilari);

  /// Depoda duran ve henüz kurum kodu olmayan cihazlar.
  Future<List<CihazBilgi>> etiketsizCihazlar() async {
    final db = await _database;
    final rows = await db.rawQuery(
        "${AppDatabase._cihazBilgiSelect} WHERE c.deleted = 0 AND c.durum = 'depoda' "
        'AND NOT EXISTS (SELECT 1 FROM etiketler x WHERE x.cihaz_id = c.id '
        'AND x.deleted = 0) '
        'ORDER BY d.ad, u.ad, c.seri_no');
    return rows.map(CihazBilgi.fromRow).toList();
  }

  Stream<List<CihazBilgi>> etiketsizCihazlarStream() => _watch(etiketsizCihazlar);

  /// Okutulan değer bir kurum etiketiyse cihazın seri numarasına çevirir;
  /// değilse büyük harfli haliyle döndürür.
  Future<String> seriyeCevir(String deger) async {
    final normal = _normSeri(deger);
    final okuma = EtiketKodu.coz(deger);
    if (okuma == null) {
      // Seri no zaten kayıtlıysa olduğu gibi kalsın.
      return normal;
    }
    final e = await etiketBul(okuma.kod);
    return e?.seriNo ?? normal;
  }

  /// Engel ayarı açıkken doğrulanmamış etiketli cihazın taşınamama sebebi.
  Future<String?> _etiketEngeliTxn(DatabaseExecutor ex, Cihaz c) async {
    final ayar = await ex.query('kurum_ayarlari',
        where: 'deleted = 0 AND id IN (?, ?)',
        whereArgs: [EtiketAyarlari.dogrulamaAnahtari, EtiketAyarlari.engelAnahtari]);
    final a = EtiketAyarlari.fromMap(
        {for (final r in ayar) r['id'] as String: (r['deger'] as String?) ?? ''});
    if (!a.engelEtkin) return null;
    final e = await ex.query('etiketler',
        columns: ['durum', 'kod'],
        where: 'cihaz_id = ? AND deleted = 0',
        whereArgs: [c.id],
        orderBy: 'olusturma',
        limit: 1);
    if (e.isEmpty) return null;
    final durum = etiketDurumuCoz(e.first['durum']);
    if (durum == EtiketDurumu.basildi) {
      return '${c.seriNo}: kurum etiketi (${e.first['kod']}) henüz doğrulanmadı. '
          'Önce Etiketler → Etiket doğrula ile etiketi doğrulayın.';
    }
    if (durum == EtiketDurumu.uyusmazlik) {
      return '${c.seriNo}: kurum etiketinde uyuşmazlık var (${e.first['kod']}). '
          'Etiketi kontrol edip yeniden doğrulayın.';
    }
    return null;
  }

  /// Arayüzde işlemden önce gösterilecek engel mesajı (yoksa null).
  Future<String?> etiketEngeli(String cihazId) async {
    final db = await _database;
    final rows = await db.query('cihazlar',
        where: 'id = ?', whereArgs: [cihazId], limit: 1);
    if (rows.isEmpty) return null;
    return _etiketEngeliTxn(db, Cihaz.fromMap(rows.first));
  }

  /// Etiket durumu raporu.
  Future<List<Map<String, Object?>>> etiketDurumRaporu() async {
    final db = await _database;
    return db.rawQuery('''
      SELECT e.kod AS kod, e.durum AS durum, e.surum AS surum,
             e.seri_nosuz AS seri_nosuz, e.olusturma AS olusturma,
             c.seri_no AS seri_no, c.durum AS cihaz_durum,
             c.servis_durumu AS servis_durumu, u.ad AS urun_adi,
             d.ad AS depo_adi, d.tur AS depo_tur, kk.kod AS kurum_kodu,
             (SELECT MAX(h.tarih) FROM etiket_hareketleri h
                WHERE h.etiket_id = e.id) AS son_islem,
             (SELECT k.ad FROM etiket_hareketleri h
                LEFT JOIN kullanicilar k ON k.id = h.kullanici_id
                WHERE h.etiket_id = e.id ORDER BY h.tarih DESC LIMIT 1) AS son_kullanici,
             (SELECT h.aciklama FROM etiket_hareketleri h
                WHERE h.etiket_id = e.id AND h.islem = 'uyusmazlik'
                ORDER BY h.tarih DESC LIMIT 1) AS uyusmazlik
      FROM etiketler e
      JOIN cihazlar c ON c.id = e.cihaz_id
      JOIN urunler u ON u.id = c.urun_id
      LEFT JOIN depolar d ON d.id = c.depo_id
      LEFT JOIN kurum_kodlari kk ON kk.id = e.kurum_kodu_id
      WHERE e.deleted = 0 AND c.deleted = 0
      ORDER BY u.ad, e.kod
    ''');
  }

  /// Bildirim motoru için: basım isteği ve uyuşmazlık olayları.
  Future<List<Map<String, Object?>>> bildirimEtiketHareketleri(int sonrasi) async {
    final db = await _database;
    return db.rawQuery('''
      SELECT h.id AS id, h.islem AS islem, h.tarih AS tarih,
             h.aciklama AS aciklama, h.kullanici_id AS kullanici_id,
             e.kod AS kod, c.seri_no AS seri_no, u.ad AS urun_adi,
             d.ad AS depo_adi, k.ad AS kullanici
      FROM etiket_hareketleri h
      JOIN etiketler e ON e.id = h.etiket_id
      JOIN cihazlar c ON c.id = h.cihaz_id
      JOIN urunler u ON u.id = c.urun_id
      LEFT JOIN depolar d ON d.id = c.depo_id
      LEFT JOIN kullanicilar k ON k.id = h.kullanici_id
      WHERE h.tarih > ? AND h.deleted = 0
        AND h.islem IN ('kuyruga', 'yenidenBasim', 'uyusmazlik')
      ORDER BY h.tarih
    ''', [sonrasi]);
  }
}
