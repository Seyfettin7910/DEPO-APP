part of 'app_database.dart';

/// Miktarla takip edilen malzeme (kablo, adaptör…) işlemleri.
///
/// Malzeme hareketleri seri numaralı cihazlarla aynı `stok_hareketleri`
/// tablosuna, `cihaz_id` boş ve `miktar` dolu olarak yazılır (silinmez,
/// değiştirilmez). Bir deponun / aracın malzeme stoğu bu hareketlerden
/// hesaplanır: giriş (+), çıkan (−), gelen (+).
enum MalzemeIslemi {
  giris,
  yukle,
  transfer,
  iade,
  kullanim;

  String get baslik => switch (this) {
        MalzemeIslemi.giris => 'Malzeme girişi',
        MalzemeIslemi.yukle => 'Malzeme Araca Yükle',
        MalzemeIslemi.transfer => 'Malzeme transferi',
        MalzemeIslemi.iade => 'Malzeme iadesi',
        MalzemeIslemi.kullanim => 'Malzeme Montaj / Kullanıldı',
      };

  HareketTipi get tip => switch (this) {
        MalzemeIslemi.giris => HareketTipi.girisi,
        MalzemeIslemi.yukle => HareketTipi.kullanim,
        MalzemeIslemi.transfer => HareketTipi.transfer,
        MalzemeIslemi.iade => HareketTipi.iade,
        MalzemeIslemi.kullanim => HareketTipi.kullanim,
      };

  /// Bir depodan / araçtan düşülen işlem mi (girişte kaynak yok)?
  bool get kaynakli => this != MalzemeIslemi.giris;

  /// Hedef depo / araç seçilen işlem mi?
  bool get hedefli =>
      this != MalzemeIslemi.kullanim;
}

/// Stokta hesaba katılan hareket türleri (servis / silme kayıtları hariç).
const _malzemeTipleri =
    "('girisi','transfer','kullanim','iade','cikis','hurda')";

class MalzemeStok {
  const MalzemeStok(this.urun, this.miktar);
  final Urun urun;
  final int miktar;
}

/// Montajdaki tutanak durumu ve kim / ne zaman.
class TutanakBilgi {
  const TutanakBilgi({
    required this.kullanimKaydiId,
    this.durum,
    this.tarih,
    this.kullaniciAdi,
  });

  final String kullanimKaydiId;
  final String? durum;
  final DateTime? tarih;
  final String? kullaniciAdi;
}

extension MalzemeVeritabani on AppDatabase {
  // --------------------------- stok kodu: 266'lı EAN-13 (1.30.2 / 1.30.3)
  // Kural: her malzemenin tek kimliği stok kodu; fabrika barkodu kullanılmaz.

  /// Veritabanında olmayan yeni 266'lı stok kodu.
  Future<String> benzersizKurumBarkodu() async {
    for (var i = 0; i < 20; i++) {
      final k = kurumBarkoduUret();
      if (await barkodIleUrunBul(k) == null) return k;
    }
    throw StateError('Stok kodu üretilemedi, tekrar deneyin');
  }

  /// Malzemeye stok kodu yazar; yazılan kodu döner. [fabrikaninYerine]:
  /// fabrika barkodu varsa onun yerine (zaten stok kodu varsa dokunulmaz).
  Future<String> malzemeyeKurumKoduVer(String urunId,
      {bool fabrikaninYerine = false}) async {
    final db = await _database;
    final r = await db.query('urunler',
        columns: ['barkod', 'seri_takipli'],
        where: 'id = ? AND deleted = 0',
        whereArgs: [urunId],
        limit: 1);
    if (r.isEmpty || (r.first['seri_takipli'] as num) != 0) {
      throw StateError('Malzeme bulunamadı');
    }
    final mevcut = ((r.first['barkod'] as String?) ?? '').trim();
    if (kurumBarkoduMu(mevcut)) throw StateError('Bu malzemenin zaten stok kodu var');
    if (mevcut.isNotEmpty && !fabrikaninYerine) {
      throw StateError('Bu malzemenin barkodu var');
    }
    final k = await benzersizKurumBarkodu();
    await db.rawUpdate(
        'UPDATE urunler SET barkod = ?, updated_at = ?, dirty = 1 WHERE id = ?',
        [k, DateTime.now().millisecondsSinceEpoch, urunId]);
    _notify();
    return k;
  }

  /// Stok kodu durumu: (barkodsuz, fabrika barkodlu) malzeme sayısı.
  Future<(int, int)> stokKoduSayilari() async {
    final db = await _database;
    final rows = await db.rawQuery(
        'SELECT barkod FROM urunler WHERE deleted = 0 AND seri_takipli = 0');
    var bos = 0, fabrika = 0;
    for (final r in rows) {
      final b = ((r['barkod'] as String?) ?? '').trim();
      if (b.isEmpty) {
        bos++;
      } else if (!kurumBarkoduMu(b)) {
        fabrika++;
      }
    }
    return (bos, fabrika);
  }

  /// Malzemelere toplu stok kodu: barkodsuzlara; [fabrikaninYerine] ise
  /// fabrika barkodlulara da (stok kodu olanlara dokunulmaz). Verilen sayı.
  Future<int> malzemelereStokKoduVer({bool fabrikaninYerine = false}) async {
    final db = await _database;
    final rows = await db.rawQuery(
        'SELECT id, barkod FROM urunler WHERE deleted = 0 AND seri_takipli = 0');
    var n = 0;
    for (final r in rows) {
      final b = ((r['barkod'] as String?) ?? '').trim();
      if (kurumBarkoduMu(b) || (b.isNotEmpty && !fabrikaninYerine)) continue;
      try {
        await malzemeyeKurumKoduVer(r['id'] as String,
            fabrikaninYerine: fabrikaninYerine);
        n++;
      } catch (_) {}
    }
    return n;
  }

  /// Miktarlı ürünlerin stoğu: urunId -> (depoId -> miktar).
  Future<Map<String, Map<String, int>>> malzemeStoklari() async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT urun_id, depo_id, SUM(m) AS m FROM (
        SELECT sh.urun_id AS urun_id, sh.depo_id AS depo_id,
               CASE WHEN sh.tip = 'girisi' THEN sh.miktar ELSE -sh.miktar END AS m
          FROM stok_hareketleri sh JOIN urunler u ON u.id = sh.urun_id
         WHERE sh.deleted = 0 AND sh.cihaz_id IS NULL AND u.seri_takipli = 0
           AND sh.tip IN $_malzemeTipleri
        UNION ALL
        SELECT sh.urun_id, sh.hedef_depo_id, sh.miktar
          FROM stok_hareketleri sh JOIN urunler u ON u.id = sh.urun_id
         WHERE sh.deleted = 0 AND sh.cihaz_id IS NULL AND u.seri_takipli = 0
           AND sh.tip IN $_malzemeTipleri AND sh.tip <> 'girisi'
           AND sh.hedef_depo_id IS NOT NULL
      ) GROUP BY urun_id, depo_id
    ''');
    final sonuc = <String, Map<String, int>>{};
    for (final r in rows) {
      final depo = r['depo_id'] as String?;
      if (depo == null) continue;
      (sonuc[r['urun_id'] as String] ??= {})[depo] =
          (r['m'] as num?)?.toInt() ?? 0;
    }
    return sonuc;
  }

  Stream<Map<String, Map<String, int>>> malzemeStoklariStream() =>
      _watch(malzemeStoklari);

  /// Bir depodaki / araçtaki malzemeler (miktarı olanlar, ada göre).
  Future<List<MalzemeStok>> depoMalzemeleri(String depoId) async {
    final stok = await malzemeStoklari();
    final liste = <MalzemeStok>[
      for (final u in await tumUrunler())
        if (u.miktarli && (stok[u.id]?[depoId] ?? 0) > 0)
          MalzemeStok(u, stok[u.id]![depoId]!),
    ];
    liste.sort(
        (a, b) => a.urun.ad.toLowerCase().compareTo(b.urun.ad.toLowerCase()));
    return liste;
  }

  Future<int> _malzemeMiktariTxn(
      DatabaseExecutor ex, String urunId, String depoId) async {
    final r = await ex.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN tip = 'girisi' AND depo_id = ? THEN miktar ELSE 0 END), 0)
      - COALESCE(SUM(CASE WHEN tip <> 'girisi' AND depo_id = ? THEN miktar ELSE 0 END), 0)
      + COALESCE(SUM(CASE WHEN tip <> 'girisi' AND hedef_depo_id = ? THEN miktar ELSE 0 END), 0)
        AS m
      FROM stok_hareketleri
      WHERE urun_id = ? AND cihaz_id IS NULL AND deleted = 0
        AND tip IN $_malzemeTipleri
    ''', [depoId, depoId, depoId, urunId]);
    return (r.first['m'] as num?)?.toInt() ?? 0;
  }

  /// Malzeme girişi, araca yükleme, transfer, iade veya montaj / kullanım.
  /// Hepsi tek işlemdir: biri hatalıysa hiçbiri kaydedilmez.
  Future<void> malzemeHareketiKaydet({
    required MalzemeIslemi islem,
    String? kaynakDepoId,
    String? hedefDepoId,
    required Map<String, int> miktarlar,
    required String kullaniciId,
    String? not_,
    String? kullanimYeri,
    // Montajda (cihazsız malzeme kullanımı) konum ve bölge
    double? enlem,
    double? boylam,
    double? konumHassasiyet,
    String? il,
    String? ilce,
    String? mahalle,
  }) async {
    final db = await _database;
    await db.transaction((txn) => _malzemeHareketiTxn(
          txn,
          islem: islem,
          kaynakDepoId: kaynakDepoId,
          hedefDepoId: hedefDepoId,
          miktarlar: miktarlar,
          kullaniciId: kullaniciId,
          not_: not_,
          kullanimYeri: kullanimYeri,
          enlem: enlem,
          boylam: boylam,
          konumHassasiyet: konumHassasiyet,
          il: il,
          ilce: ilce,
          mahalle: mahalle,
        ));
    _notify();
  }

  Future<void> _malzemeHareketiTxn(
    Transaction txn, {
    required MalzemeIslemi islem,
    String? kaynakDepoId,
    String? hedefDepoId,
    required Map<String, int> miktarlar,
    required String kullaniciId,
    String? not_,
    String? kullanimYeri,
    double? enlem,
    double? boylam,
    double? konumHassasiyet,
    String? il,
    String? ilce,
    String? mahalle,
  }) async {
    final kalemler = {
      for (final e in miktarlar.entries)
        if (e.value > 0) e.key: e.value
    };
    if (kalemler.isEmpty) throw StateError('Miktar girilmedi');
    if (islem.kaynakli && kaynakDepoId == null) {
      throw StateError('Nereden alınacağını seçin');
    }
    if (islem.hedefli && hedefDepoId == null) {
      throw StateError(islem == MalzemeIslemi.giris
          ? 'Hangi depo / araca girileceğini seçin'
          : 'Nereye gideceğini seçin');
    }
    if (islem.kaynakli && islem.hedefli && kaynakDepoId == hedefDepoId) {
      throw StateError('Nereden ve nereye aynı olamaz');
    }
    final yer = (kullanimYeri ?? '').trim();
    // Konum varsa yer boş bırakılabilir (internet gelince konumdan dolar).
    if (islem == MalzemeIslemi.kullanim && yer.isEmpty && enlem == null) {
      throw StateError('Nerede kullanıldığını yazın');
    }
    final simdi = DateTime.now();

    for (final e in kalemler.entries) {
      final r = await txn.query('urunler',
          where: 'id = ? AND deleted = 0', whereArgs: [e.key], limit: 1);
      if (r.isEmpty) throw StateError('Malzeme bulunamadı');
      final urun = Urun.fromMap(r.first);
      if (!urun.miktarli) {
        throw StateError('${urun.ad} seri numarasıyla takip ediliyor; '
            'seri no okutarak işlem yapın');
      }
      if (islem.kaynakli) {
        final mevcut = await _malzemeMiktariTxn(txn, urun.id, kaynakDepoId!);
        if (e.value > mevcut) {
          throw StateError('${urun.ad}: burada ${urun.miktarMetni(mevcut)} '
              'var, ${urun.miktarMetni(e.value)} düşülemez');
        }
      }
      final hareketId = _uuid.v4();
      await txn.insert(
        'stok_hareketleri',
        StokHareketi(
          id: hareketId,
          urunId: urun.id,
          depoId: islem.kaynakli ? kaynakDepoId! : hedefDepoId!,
          hedefDepoId: islem.kaynakli && islem.hedefli ? hedefDepoId : null,
          tip: islem.tip,
          miktar: e.value,
          kullaniciId: kullaniciId,
          tarih: simdi,
          not_: (not_ ?? '').trim().isEmpty ? null : not_!.trim(),
          updatedAt: simdi,
        ).toMap(),
      );
      if (islem == MalzemeIslemi.kullanim) {
        await txn.insert(
          'kullanim_kayitlari',
          KullanimKaydi(
            id: _uuid.v4(),
            stokHareketId: hareketId,
            kullanimYeri: yer.isEmpty ? null : yer,
            not_: (not_ ?? '').trim().isEmpty ? null : not_!.trim(),
            enlem: enlem,
            boylam: boylam,
            konumHassasiyet: konumHassasiyet,
            il: il,
            ilce: ilce,
            mahalle: mahalle,
            updatedAt: simdi,
          ).toMap(),
        );
      }
    }
  }

  /// Ürünün takip türü değiştirilebilir mi (hiç cihazı / hareketi yoksa)?
  Future<bool> takipTuruDegisebilir(String urunId) async {
    final db = await _database;
    final n = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT (SELECT COUNT(*) FROM cihazlar WHERE urun_id = ?) + '
            '(SELECT COUNT(*) FROM stok_hareketleri WHERE urun_id = ?)',
            [urunId, urunId])) ??
        0;
    return n == 0;
  }

  /// Kullanılmamış ürünün takip türünü (seri no / miktar) ve birimini değiştirir.
  Future<void> takipTuruDegistir(String urunId,
      {required bool seriTakipli, required String birim}) async {
    if (!await takipTuruDegisebilir(urunId)) {
      throw StateError('Bu ürünün kaydı / hareketi var; takip türü '
          'değiştirilemez');
    }
    final db = await _database;
    await db.update(
      'urunler',
      {
        'seri_takipli': seriTakipli ? 1 : 0,
        'birim': seriTakipli ? 'adet' : birim,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [urunId],
    );
    _notify();
  }

  // -------------------------------------------------------------------
  // Montaj tutanağı
  // -------------------------------------------------------------------

  /// Montajlı cihazın son montaj kaydındaki tutanak durumu (montajlı
  /// değilse null).
  Future<TutanakBilgi?> cihazTutanagi(String cihazId) async {
    final db = await _database;
    final r = await db.rawQuery('''
      SELECT kk.id AS id, kk.tutanak AS tutanak,
             kk.tutanak_tarihi AS tarih, k.ad AS kullanici
        FROM kullanim_kayitlari kk
        JOIN stok_hareketleri sh ON sh.id = kk.stok_hareket_id
        JOIN cihazlar c ON c.id = sh.cihaz_id
        LEFT JOIN kullanicilar k ON k.id = kk.tutanak_kullanici_id
       WHERE sh.cihaz_id = ? AND sh.deleted = 0 AND kk.deleted = 0
         AND c.durum = 'kullanimda'
       ORDER BY sh.tarih DESC LIMIT 1
    ''', [cihazId]);
    if (r.isEmpty) return null;
    final x = r.first;
    return TutanakBilgi(
      kullanimKaydiId: x['id'] as String,
      durum: x['tutanak'] as String?,
      tarih: x['tarih'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch((x['tarih'] as num).toInt()),
      kullaniciAdi: x['kullanici'] as String?,
    );
  }

  Stream<TutanakBilgi?> cihazTutanagiStream(String cihazId) =>
      _watch(() => cihazTutanagi(cihazId));

  /// Tutanak durumunu günceller (ör. "Alınacak" → "Alındı").
  Future<void> tutanakGuncelle(String cihazId,
      {required String tutanak, required String kullaniciId}) async {
    if (!tutanakSecenekleri.contains(tutanak)) {
      throw ArgumentError('Geçersiz tutanak durumu');
    }
    final t = await cihazTutanagi(cihazId);
    if (t == null) throw StateError('Cihaz şu an montajlı değil');
    final db = await _database;
    final simdi = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'kullanim_kayitlari',
      {
        'tutanak': tutanak,
        'tutanak_tarihi': simdi,
        'tutanak_kullanici_id': kullaniciId,
        'updated_at': simdi,
        'dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [t.kullanimKaydiId],
    );
    _notify();
  }
}
