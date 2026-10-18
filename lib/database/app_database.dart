import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

const _uuid = Uuid();

const _createTablesSql = '''
CREATE TABLE depolar (
  id TEXT PRIMARY KEY,
  ad TEXT NOT NULL,
  konum TEXT,
  tur TEXT NOT NULL DEFAULT 'sabit',
  updated_at INTEGER NOT NULL,
  dirty INTEGER NOT NULL DEFAULT 1,
  deleted INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE urunler (
  id TEXT PRIMARY KEY,
  ad TEXT NOT NULL,
  barkod TEXT,
  birim TEXT NOT NULL DEFAULT 'adet',
  kategori TEXT,
  min_stok_seviyesi INTEGER NOT NULL DEFAULT 0,
  seri_takipli INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  dirty INTEGER NOT NULL DEFAULT 1,
  deleted INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE araclar (
  id TEXT PRIMARY KEY,
  plaka TEXT NOT NULL,
  ad TEXT,
  aciklama TEXT,
  updated_at INTEGER NOT NULL,
  dirty INTEGER NOT NULL DEFAULT 1,
  deleted INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE kullanicilar (
  id TEXT PRIMARY KEY,
  ad TEXT NOT NULL,
  email TEXT NOT NULL,
  rol TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  dirty INTEGER NOT NULL DEFAULT 1,
  deleted INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE depo_stoklari (
  id TEXT PRIMARY KEY,
  depo_id TEXT NOT NULL,
  urun_id TEXT NOT NULL,
  miktar INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  dirty INTEGER NOT NULL DEFAULT 1,
  deleted INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE stok_hareketleri (
  id TEXT PRIMARY KEY,
  urun_id TEXT NOT NULL,
  depo_id TEXT NOT NULL,
  hedef_depo_id TEXT,
  tip TEXT NOT NULL,
  miktar INTEGER NOT NULL,
  kullanici_id TEXT NOT NULL,
  tarih INTEGER NOT NULL,
  not_ TEXT,
  cihaz_id TEXT,
  updated_at INTEGER NOT NULL,
  dirty INTEGER NOT NULL DEFAULT 1,
  deleted INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE kullanim_kayitlari (
  id TEXT PRIMARY KEY,
  stok_hareket_id TEXT NOT NULL,
  arac_id TEXT,
  kullanim_yeri TEXT,
  not_ TEXT,
  updated_at INTEGER NOT NULL,
  dirty INTEGER NOT NULL DEFAULT 1,
  deleted INTEGER NOT NULL DEFAULT 0
);
''';

const _syncMetaSql = '''
CREATE TABLE sync_meta (
  tablo TEXT PRIMARY KEY,
  son_cekim INTEGER NOT NULL DEFAULT 0
)
''';

class DepoOzet {
  final int urunCesidi;
  final int toplamMiktar;
  const DepoOzet({required this.urunCesidi, required this.toplamMiktar});
}

class HareketSatiri {
  final String urunAdi;
  final String birim;
  final HareketTipi tip;
  final int miktar; // bu depo açısından işaretli
  final DateTime tarih;
  final String? karsiDepoAdi;
  final String? aracPlaka;
  final String? kullanimYeri;
  final String? not_;
  final String? seriNo;
  final String? kullaniciAdi;

  const HareketSatiri({
    required this.urunAdi,
    required this.birim,
    required this.tip,
    required this.miktar,
    required this.tarih,
    this.karsiDepoAdi,
    this.aracPlaka,
    this.kullanimYeri,
    this.not_,
    this.seriNo,
    this.kullaniciAdi,
  });
}

/// Seri numaralı cihaz tablosu (şema sürümü 2'de eklendi).
const _cihazlarTabloSql = '''
CREATE TABLE cihazlar (
  id TEXT PRIMARY KEY,
  urun_id TEXT NOT NULL,
  seri_no TEXT NOT NULL UNIQUE,
  depo_id TEXT,
  durum TEXT NOT NULL,
  arac_id TEXT,
  kullanim_yeri TEXT,
  updated_at INTEGER NOT NULL,
  dirty INTEGER NOT NULL DEFAULT 1,
  deleted INTEGER NOT NULL DEFAULT 0
)
''';

class CihazBilgi {
  final Cihaz cihaz;
  final String urunAdi;
  final String? depoAdi;
  final String? aracPlaka;
  final bool depoArac; // bulunduğu depo bir araç (seyyar depo) mu

  const CihazBilgi({
    required this.cihaz,
    required this.urunAdi,
    this.depoAdi,
    this.aracPlaka,
    this.depoArac = false,
  });

  factory CihazBilgi.fromRow(Map<String, Object?> r) => CihazBilgi(
        cihaz: Cihaz.fromMap(r),
        urunAdi: r['urun_adi'] as String,
        depoAdi: r['depo_adi'] as String?,
        aracPlaka: r['arac_plaka'] as String?,
        depoArac: r['depo_tur'] == 'arac',
      );
}

class CihazHareketSatiri {
  final HareketTipi tip;
  final DateTime tarih;
  final String? depoAdi;
  final String? hedefDepoAdi;
  final String? aracPlaka;
  final String? kullanimYeri;
  final String? not_;
  final String? kullaniciAdi;
  final String? depoId; // hareketin çıkış (kaynak) deposu
  final String? hedefDepoId;

  const CihazHareketSatiri({
    required this.tip,
    required this.tarih,
    this.depoId,
    this.hedefDepoId,
    this.depoAdi,
    this.hedefDepoAdi,
    this.aracPlaka,
    this.kullanimYeri,
    this.not_,
    this.kullaniciAdi,
  });
}

class KullanimRaporSatiri {
  final String urunAdi;
  final String depoAdi;
  final String? aracPlaka;
  final String? kullanimYeri;
  final int miktar;
  final DateTime tarih;
  final String? seriNo;

  KullanimRaporSatiri({
    required this.urunAdi,
    required this.depoAdi,
    this.aracPlaka,
    this.kullanimYeri,
    required this.miktar,
    required this.tarih,
    this.seriNo,
  });
}

/// sqflite tabanlı yerel veritabanı. Drift'in aksine kod üretimi
/// (build_runner) gerektirmez — bulut IDE'lerde (FlutLab vb.) veya
/// build_runner çalıştırma imkanı olmayan ortamlarda sorunsuz derlenir.
///
/// Reaktif listeler için basit bir "değişiklik oldu" yayın akışı
/// kullanılır: her yazma işleminden sonra `_notify()` çağrılır, ilgili
/// stream'ler bunu dinleyip veriyi yeniden okur.
class AppDatabase {
  Database? _db;
  final _changes = StreamController<void>.broadcast();

  Future<Database> get _database async {
    if (_db != null) return _db!;
    // Web'de dosya sistemi yok; veritabanı adıyla IndexedDB'de tutulur.
    final path = kIsWeb
        ? 'depo_app.sqlite'
        : p.join(await getDatabasesPath(), 'depo_app.sqlite');
    _db = await openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        for (final stmt in _createTablesSql.split(';')) {
          final trimmed = stmt.trim();
          if (trimmed.isNotEmpty) await db.execute(trimmed);
        }
        await db.execute(_cihazlarTabloSql);
        await db.execute(_syncMetaSql);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // 1.1.x -> 1.2.0: her şey seri numarasıyla takip edilir.
          // Eski adet kayıtları silinmez ama artık sayımlara dahil edilmez.
          await db.execute(
              'ALTER TABLE urunler ADD COLUMN seri_takipli INTEGER NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE stok_hareketleri ADD COLUMN cihaz_id TEXT');
          await db.execute(_cihazlarTabloSql);
          await db.execute('UPDATE urunler SET seri_takipli = 1');
        }
        if (oldVersion < 3) {
          // 1.3.0: sunucu senkronizasyonu. Eski kayıtların hepsi dirty=1 olduğu
          // için (henüz hiç gönderilmedi) giriş yapınca sunucuya yüklenir.
          await db.execute(_syncMetaSql);
          await db.execute('UPDATE cihazlar SET dirty = 1');
        }
        if (oldVersion < 4) {
          // 1.4.0: araçlar seyyar depo olarak depolar tablosunda tutulur.
          await db.execute(
              "ALTER TABLE depolar ADD COLUMN tur TEXT NOT NULL DEFAULT 'sabit'");
        }
      },
    );
    return _db!;
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  /// İlk veriyi hemen gönderir, sonra her veritabanı değişikliğinde
  /// sorguyu yeniden çalıştırıp yeni veriyi yayınlar.
  Stream<T> _watch<T>(Future<T> Function() query) {
    late StreamController<T> controller;
    StreamSubscription<void>? sub;

    Future<void> yenile() async {
      try {
        final veri = await query();
        if (!controller.isClosed) controller.add(veri);
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
      }
    }

    controller = StreamController<T>(
      onListen: () {
        sub = _changes.stream.listen((_) => yenile());
        yenile();
      },
      onCancel: () async {
        await sub?.cancel();
      },
    );
    return controller.stream;
  }

  Future<void> close() async {
    await _db?.close();
    await _changes.close();
  }

  // ---------------------------------------------------------------------
  // Depolar
  // ---------------------------------------------------------------------
  Future<List<Depo>> tumDepolar() async {
    final db = await _database;
    final rows = await db.query('depolar',
        where: 'deleted = 0', orderBy: "CASE tur WHEN 'arac' THEN 1 ELSE 0 END, ad COLLATE NOCASE");
    return rows.map(Depo.fromMap).toList();
  }

  Stream<List<Depo>> depolarStream() => _watch(tumDepolar);

  String _normDepoAdi(String ad, DepoTuru tur) {
    final t = ad.trim().replaceAll(RegExp(r'\s+'), ' ');
    return tur == DepoTuru.arac ? t.toUpperCase() : t;
  }

  Future<void> _adCakismasiniDenetle(
      DatabaseExecutor db, String ad, DepoTuru tur, String? haricId) async {
    final rows = await db.query('depolar',
        columns: ['id', 'ad'],
        where: 'deleted = 0 AND tur = ?',
        whereArgs: [tur.name]);
    for (final r in rows) {
      if (r['id'] != haricId &&
          (r['ad'] as String).toLowerCase() == ad.toLowerCase()) {
        throw StateError(tur == DepoTuru.arac
            ? 'Bu plaka zaten kayıtlı'
            : 'Bu isimde bir depo zaten var');
      }
    }
  }

  /// Sabit depo veya seyyar depo (araç) ekler. Araçta [ad] plakadır.
  Future<String> depoEkle({
    required String ad,
    String? konum,
    DepoTuru tur = DepoTuru.sabit,
  }) async {
    final db = await _database;
    final temiz = _normDepoAdi(ad, tur);
    if (temiz.isEmpty) throw StateError('Ad boş olamaz');
    await _adCakismasiniDenetle(db, temiz, tur, null);
    final depo = Depo(
        id: _uuid.v4(),
        ad: temiz,
        konum: konum,
        tur: tur,
        updatedAt: DateTime.now());
    await db.insert('depolar', depo.toMap());
    _notify();
    return depo.id;
  }

  Future<void> depoGuncelle({
    required String id,
    required String ad,
    String? konum,
  }) async {
    final db = await _database;
    final rows = await db.query('depolar', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) throw StateError('Kayıt bulunamadı');
    final mevcut = Depo.fromMap(rows.first);
    final temiz = _normDepoAdi(ad, mevcut.tur);
    if (temiz.isEmpty) throw StateError('Ad boş olamaz');
    await _adCakismasiniDenetle(db, temiz, mevcut.tur, id);
    await db.update(
      'depolar',
      {
        'ad': temiz,
        'konum': konum,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _notify();
  }

  /// İçinde cihaz bulunan depo/araç silinemez.
  Future<void> depoSil(String id) async {
    final db = await _database;
    final icindeki = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM cihazlar WHERE depo_id = ? AND durum = 'depoda' AND deleted = 0",
            [id])) ??
        0;
    if (icindeki > 0) {
      throw StateError(
          'İçinde $icindeki cihaz var. Önce cihazları başka yere transfer edin.');
    }
    await db.update(
      'depolar',
      {
        'deleted': 1,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _notify();
  }

  // ---------------------------------------------------------------------
  // Ürünler
  // ---------------------------------------------------------------------
  Future<List<Urun>> tumUrunler() async {
    final db = await _database;
    final rows = await db.query('urunler', where: 'deleted = 0', orderBy: 'ad');
    return rows.map(Urun.fromMap).toList();
  }

  Stream<List<Urun>> urunlerStream() => _watch(tumUrunler);

  Future<Urun?> barkodIleUrunBul(String barkod) async {
    final db = await _database;
    final rows = await db.query('urunler', where: 'barkod = ?', whereArgs: [barkod], limit: 1);
    if (rows.isEmpty) return null;
    return Urun.fromMap(rows.first);
  }

  /// Tüm ürünler (modeller) seri numarasıyla takip edilir; adetler
  /// depodaki cihaz sayısından otomatik hesaplanır.
  Future<String> urunEkle({
    required String ad,
    String? barkod,
    String birim = 'adet',
    String? kategori,
    int minStokSeviyesi = 0,
  }) async {
    final db = await _database;
    final urun = Urun(
      id: _uuid.v4(),
      ad: ad,
      barkod: barkod,
      birim: birim,
      kategori: kategori,
      minStokSeviyesi: minStokSeviyesi,
      seriTakipli: true,
      updatedAt: DateTime.now(),
    );
    await db.insert('urunler', urun.toMap());
    _notify();
    return urun.id;
  }

  Future<void> urunGuncelle({
    required String id,
    required String ad,
    String? barkod,
    required String birim,
    String? kategori,
    required int minStokSeviyesi,
  }) async {
    final db = await _database;
    final n = await db.update(
      'urunler',
      {
        'ad': ad,
        'barkod': barkod,
        'birim': birim,
        'kategori': kategori,
        'min_stok_seviyesi': minStokSeviyesi,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (n == 0) throw StateError('Ürün bulunamadı');
    _notify();
  }

  /// "Bu ürün / araç hangi depoda ne zaman nereye kullanıldı" raporu.
  Future<List<KullanimRaporSatiri>> kullanimRaporu({
    String? urunId,
    String? aracId,
    DateTime? baslangic,
    DateTime? bitis,
  }) async {
    final db = await _database;
    final kosullar = <String>['1=1'];
    final args = <Object?>[];

    if (urunId != null) {
      kosullar.add('sh.urun_id = ?');
      args.add(urunId);
    }
    if (aracId != null) {
      kosullar.add('kk.arac_id = ?');
      args.add(aracId);
    }
    if (baslangic != null) {
      kosullar.add('sh.tarih >= ?');
      args.add(baslangic.millisecondsSinceEpoch);
    }
    if (bitis != null) {
      kosullar.add('sh.tarih <= ?');
      args.add(bitis.millisecondsSinceEpoch);
    }

    final rows = await db.rawQuery('''
      SELECT
        sh.tarih as tarih,
        sh.miktar as miktar,
        u.ad as urun_adi,
        d.ad as depo_adi,
        a.plaka as arac_plaka,
        kk.kullanim_yeri as kullanim_yeri,
        c.seri_no as seri_no
      FROM kullanim_kayitlari kk
      JOIN stok_hareketleri sh ON sh.id = kk.stok_hareket_id
      JOIN urunler u ON u.id = sh.urun_id
      JOIN depolar d ON d.id = sh.depo_id
      LEFT JOIN araclar a ON a.id = kk.arac_id
      LEFT JOIN cihazlar c ON c.id = sh.cihaz_id
      WHERE ${kosullar.join(' AND ')}
      ORDER BY sh.tarih DESC
    ''', args);

    return rows
        .map((r) => KullanimRaporSatiri(
              urunAdi: r['urun_adi'] as String,
              depoAdi: r['depo_adi'] as String,
              aracPlaka: r['arac_plaka'] as String?,
              kullanimYeri: r['kullanim_yeri'] as String?,
              seriNo: r['seri_no'] as String?,
              miktar: r['miktar'] as int,
              tarih: DateTime.fromMillisecondsSinceEpoch(r['tarih'] as int),
            ))
        .toList();
  }

  // ---------------------------------------------------------------------
  // Excel raporları için ham listeler
  // ---------------------------------------------------------------------

  /// Cihazlar: seri no, ürün, kategori, şu anki konum ve durum.
  /// [urunId] verilirse yalnızca o ürünün cihazları.
  Future<List<Map<String, Object?>>> cihazListesiRaporu({String? urunId}) async {
    final db = await _database;
    return db.rawQuery('''
      SELECT c.seri_no AS seri_no, c.urun_id AS urun_id, u.ad AS urun_adi,
             u.kategori AS kategori, c.durum AS durum, d.ad AS depo_adi,
             d.tur AS depo_tur, c.kullanim_yeri AS kullanim_yeri,
             c.updated_at AS guncelleme
      FROM cihazlar c
      JOIN urunler u ON u.id = c.urun_id
      LEFT JOIN depolar d ON d.id = c.depo_id
      WHERE c.deleted = 0 ${urunId == null ? '' : 'AND c.urun_id = ?'}
      ORDER BY u.ad COLLATE NOCASE, d.ad COLLATE NOCASE, c.seri_no
    ''', [if (urunId != null) urunId]);
  }

  /// Seri numaralı tüm hareketler (giriş, transfer, kullanım, iade, çıkış).
  Future<List<Map<String, Object?>>> hareketRaporu({
    DateTime? baslangic,
    DateTime? bitis,
  }) async {
    final db = await _database;
    final kosullar = <String>['sh.deleted = 0', 'sh.cihaz_id IS NOT NULL'];
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
      SELECT sh.tarih AS tarih, sh.tip AS tip, c.seri_no AS seri_no,
             u.ad AS urun_adi, d.ad AS kaynak, hd.ad AS hedef,
             kk.kullanim_yeri AS kullanim_yeri, k.ad AS kullanici,
             sh.not_ AS not_
      FROM stok_hareketleri sh
      JOIN urunler u ON u.id = sh.urun_id
      LEFT JOIN cihazlar c ON c.id = sh.cihaz_id
      LEFT JOIN depolar d ON d.id = sh.depo_id
      LEFT JOIN depolar hd ON hd.id = sh.hedef_depo_id
      LEFT JOIN kullanim_kayitlari kk ON kk.stok_hareket_id = sh.id
      LEFT JOIN kullanicilar k ON k.id = sh.kullanici_id
      WHERE ${kosullar.join(' AND ')}
      ORDER BY sh.tarih DESC
    ''', args);
  }

  // ---------------------------------------------------------------------
  // Stok özetleri ve hareket geçmişi
  // ---------------------------------------------------------------------
  Future<Map<String, DepoOzet>> depoOzetleri() async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT depo_id,
             COUNT(DISTINCT urun_id) AS cesit,
             COUNT(*) AS toplam
      FROM cihazlar
      WHERE durum = 'depoda' AND deleted = 0 AND depo_id IS NOT NULL
      GROUP BY depo_id
    ''');
    return {
      for (final r in rows)
        r['depo_id'] as String: DepoOzet(
          urunCesidi: (r['cesit'] as num?)?.toInt() ?? 0,
          toplamMiktar: (r['toplam'] as num?)?.toInt() ?? 0,
        ),
    };
  }

  Stream<Map<String, DepoOzet>> depoOzetleriStream() => _watch(depoOzetleri);

  Future<Map<String, int>> urunToplamStoklari() async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT urun_id, COUNT(*) AS toplam
      FROM cihazlar
      WHERE durum = 'depoda' AND deleted = 0
      GROUP BY urun_id
    ''');
    return {
      for (final r in rows)
        r['urun_id'] as String: (r['toplam'] as num?)?.toInt() ?? 0,
    };
  }

  Stream<Map<String, int>> urunToplamStoklariStream() =>
      _watch(urunToplamStoklari);

  /// Bir depoya giren/çıkan/transfer edilen/kullanılan tüm hareketler.
  /// Miktar bu depo açısından işaretlidir (+ giriş, - çıkış).
  Future<List<HareketSatiri>> depoHareketleri(String depoId,
      {int limit = 200}) async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT sh.tip AS tip, sh.miktar AS miktar, sh.tarih AS tarih,
             sh.not_ AS not_, sh.depo_id AS depo_id,
             u.ad AS urun_adi, u.birim AS birim,
             d.ad AS depo_adi, hd.ad AS hedef_depo_adi,
             a.plaka AS arac_plaka, kk.kullanim_yeri AS kullanim_yeri,
             c.seri_no AS seri_no, k.ad AS kullanici_adi
      FROM stok_hareketleri sh
      JOIN urunler u ON u.id = sh.urun_id
      JOIN depolar d ON d.id = sh.depo_id
      LEFT JOIN depolar hd ON hd.id = sh.hedef_depo_id
      LEFT JOIN kullanim_kayitlari kk ON kk.stok_hareket_id = sh.id
      LEFT JOIN araclar a ON a.id = kk.arac_id
      LEFT JOIN cihazlar c ON c.id = sh.cihaz_id
      LEFT JOIN kullanicilar k ON k.id = sh.kullanici_id
      WHERE sh.deleted = 0 AND sh.cihaz_id IS NOT NULL
        AND (sh.depo_id = ? OR sh.hedef_depo_id = ?)
      ORDER BY sh.tarih DESC
      LIMIT ?
    ''', [depoId, depoId, limit]);

    return rows.map((r) {
      final tip = HareketTipi.values.firstWhere((t) => t.name == r['tip']);
      final miktar = (r['miktar'] as num).toInt();
      var isaretli = 0;
      String? karsiDepo;
      switch (tip) {
        case HareketTipi.girisi:
          isaretli = miktar;
          break;
        case HareketTipi.cikis:
          isaretli = -miktar;
          break;
        case HareketTipi.kullanim:
        case HareketTipi.iade:
        case HareketTipi.transfer:
          if (tip == HareketTipi.kullanim && r['hedef_depo_adi'] == null) {
            isaretli = -miktar; // eski (hedefsiz) kullanım kaydı
            break;
          }
          if (r['depo_id'] == depoId) {
            isaretli = -miktar;
            karsiDepo = r['hedef_depo_adi'] as String?;
          } else {
            isaretli = miktar;
            karsiDepo = r['depo_adi'] as String?;
          }
          break;
      }
      return HareketSatiri(
        urunAdi: r['urun_adi'] as String,
        birim: (r['birim'] as String?) ?? 'adet',
        tip: tip,
        miktar: isaretli,
        tarih: DateTime.fromMillisecondsSinceEpoch((r['tarih'] as num).toInt()),
        karsiDepoAdi: karsiDepo,
        aracPlaka: r['arac_plaka'] as String?,
        kullanimYeri: r['kullanim_yeri'] as String?,
        not_: r['not_'] as String?,
        seriNo: r['seri_no'] as String?,
        kullaniciAdi: r['kullanici_adi'] as String?,
      );
    }).toList();
  }

  Stream<List<HareketSatiri>> depoHareketleriStream(String depoId) =>
      _watch(() => depoHareketleri(depoId));

  // ---------------------------------------------------------------------
  // Seri numaralı cihazlar
  // ---------------------------------------------------------------------
  String _normSeri(String s) => s.trim().toUpperCase();

  static const _cihazBilgiSelect = '''
      SELECT c.id AS id, c.urun_id AS urun_id, c.seri_no AS seri_no,
             c.depo_id AS depo_id, c.durum AS durum, c.arac_id AS arac_id,
             c.kullanim_yeri AS kullanim_yeri, c.updated_at AS updated_at,
             c.dirty AS dirty, c.deleted AS deleted,
             u.ad AS urun_adi, d.ad AS depo_adi, d.tur AS depo_tur,
             a.plaka AS arac_plaka
      FROM cihazlar c
      JOIN urunler u ON u.id = c.urun_id
      LEFT JOIN depolar d ON d.id = c.depo_id
      LEFT JOIN araclar a ON a.id = c.arac_id
  ''';

  /// Okutulan/yazılan seri numarasına ait cihazı bulur (büyük-küçük harf duyarsız).
  Future<Cihaz?> seriNoIleCihazBul(String seriNo) async {
    final db = await _database;
    final rows = await db.query('cihazlar',
        where: 'seri_no = ? AND deleted = 0',
        whereArgs: [_normSeri(seriNo)],
        limit: 1);
    if (rows.isEmpty) return null;
    return Cihaz.fromMap(rows.first);
  }

  Future<CihazBilgi?> cihazBilgi(String cihazId) async {
    final db = await _database;
    final rows =
        await db.rawQuery('$_cihazBilgiSelect WHERE c.id = ? LIMIT 1', [cihazId]);
    if (rows.isEmpty) return null;
    return CihazBilgi.fromRow(rows.first);
  }

  Stream<CihazBilgi?> cihazBilgiStream(String cihazId) =>
      _watch(() => cihazBilgi(cihazId));

  /// Bir depoda şu anda bulunan cihazlar.
  Future<List<CihazBilgi>> depoCihazlari(String depoId) async {
    final db = await _database;
    final rows = await db.rawQuery(
        '$_cihazBilgiSelect WHERE c.depo_id = ? AND c.durum = ? AND c.deleted = 0 '
        'ORDER BY u.ad, c.seri_no',
        [depoId, CihazDurumu.depoda.name]);
    return rows.map(CihazBilgi.fromRow).toList();
  }

  Stream<List<CihazBilgi>> depoCihazlariStream(String depoId) =>
      _watch(() => depoCihazlari(depoId));

  /// Bir cihazın tüm geçmişi (en yeni üstte).
  Future<List<CihazHareketSatiri>> cihazGecmisi(String cihazId) async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT sh.tip AS tip, sh.tarih AS tarih, sh.not_ AS not_,
             sh.depo_id AS depo_id, sh.hedef_depo_id AS hedef_depo_id,
             d.ad AS depo_adi, hd.ad AS hedef_depo_adi,
             a.plaka AS arac_plaka, kk.kullanim_yeri AS kullanim_yeri,
             k.ad AS kullanici_adi
      FROM stok_hareketleri sh
      LEFT JOIN kullanicilar k ON k.id = sh.kullanici_id
      LEFT JOIN depolar d ON d.id = sh.depo_id
      LEFT JOIN depolar hd ON hd.id = sh.hedef_depo_id
      LEFT JOIN kullanim_kayitlari kk ON kk.stok_hareket_id = sh.id
      LEFT JOIN araclar a ON a.id = kk.arac_id
      WHERE sh.cihaz_id = ? AND sh.deleted = 0
      ORDER BY sh.tarih DESC
    ''', [cihazId]);

    return rows
        .map((r) => CihazHareketSatiri(
              tip: HareketTipi.values.firstWhere((t) => t.name == r['tip']),
              tarih: DateTime.fromMillisecondsSinceEpoch((r['tarih'] as num).toInt()),
              depoId: r['depo_id'] as String?,
              hedefDepoId: r['hedef_depo_id'] as String?,
              depoAdi: r['depo_adi'] as String?,
              hedefDepoAdi: r['hedef_depo_adi'] as String?,
              aracPlaka: r['arac_plaka'] as String?,
              kullanimYeri: r['kullanim_yeri'] as String?,
              not_: r['not_'] as String?,
              kullaniciAdi: r['kullanici_adi'] as String?,
            ))
        .toList();
  }

  Stream<List<CihazHareketSatiri>> cihazGecmisiStream(String cihazId) =>
      _watch(() => cihazGecmisi(cihazId));

  /// Bir veya birden çok cihazı seri numarasıyla depoya alır (yeni kayıt ya da
  /// daha önce çıkmış/kullanıma verilmiş cihazın iadesi). Hepsi tek işlemdir:
  /// biri hatalıysa hiçbiri kaydedilmez.
  Future<void> cihazlariGirisYap({
    required String urunId,
    required String depoId,
    required List<String> seriNolar,
    required String kullaniciId,
    String? not_,
  }) async {
    if (seriNolar.every((x) => _normSeri(x).isEmpty)) {
      throw StateError('Hiç seri numarası eklenmedi');
    }
    final db = await _database;

    await db.transaction((txn) async {
      final urunRows = await txn.query('urunler',
          columns: ['id'], where: 'id = ?', whereArgs: [urunId], limit: 1);
      if (urunRows.isEmpty) throw StateError('Ürün bulunamadı');

      final simdi = DateTime.now();
      final gorulen = <String>{};

      for (final ham in seriNolar) {
        final seri = _normSeri(ham);
        if (seri.isEmpty || !gorulen.add(seri)) continue;

        final rows = await txn.query('cihazlar',
            where: 'seri_no = ?', whereArgs: [seri], limit: 1);
        String cihazId;

        if (rows.isEmpty) {
          cihazId = _uuid.v4();
          await txn.insert(
            'cihazlar',
            Cihaz(
              id: cihazId,
              urunId: urunId,
              seriNo: seri,
              depoId: depoId,
              durum: CihazDurumu.depoda,
              updatedAt: simdi,
            ).toMap(),
          );
        } else {
          final mevcut = Cihaz.fromMap(rows.first);
          if (mevcut.durum == CihazDurumu.depoda && !mevcut.deleted) {
            throw StateError('$seri zaten depoda kayıtlı');
          }
          if (mevcut.urunId != urunId) {
            throw StateError('$seri başka bir modele ait');
          }
          cihazId = mevcut.id;
          await txn.update(
            'cihazlar',
            {
              'depo_id': depoId,
              'durum': CihazDurumu.depoda.name,
              'arac_id': null,
              'kullanim_yeri': null,
              'deleted': 0,
              'updated_at': simdi.millisecondsSinceEpoch,
              'dirty': 1,
            },
            where: 'id = ?',
            whereArgs: [cihazId],
          );
        }

        await txn.insert(
          'stok_hareketleri',
          StokHareketi(
            id: _uuid.v4(),
            urunId: urunId,
            depoId: depoId,
            tip: HareketTipi.girisi,
            miktar: 1,
            kullaniciId: kullaniciId,
            tarih: simdi,
            not_: not_,
            cihazId: cihazId,
            updatedAt: simdi,
          ).toMap(),
        );
      }
    });

    _notify();
  }

  /// Okutulan seri numarasının cihaz bilgisini (model, depo, araç) getirir.
  Future<CihazBilgi?> seriNoIleCihazBilgi(String seriNo) async {
    final db = await _database;
    final rows = await db.rawQuery(
        '$_cihazBilgiSelect WHERE c.seri_no = ? AND c.deleted = 0 LIMIT 1',
        [_normSeri(seriNo)]);
    if (rows.isEmpty) return null;
    return CihazBilgi.fromRow(rows.first);
  }

  /// Seri no, model adı, depo adı, araç plakası veya kullanım yeri ile arar.
  /// Tam eşleşen seri numarası listenin başına gelir.
  Future<List<CihazBilgi>> cihazAra(String sorgu, {int limit = 60}) async {
    final q = sorgu.trim();
    if (q.isEmpty) return [];
    final db = await _database;
    final temiz = q.replaceAll('%', '').replaceAll('_', '');
    final like = '%$temiz%';
    final rows = await db.rawQuery(
        '$_cihazBilgiSelect WHERE c.deleted = 0 AND ('
        'c.seri_no LIKE ? OR u.ad LIKE ? OR d.ad LIKE ? OR '
        'a.plaka LIKE ? OR c.kullanim_yeri LIKE ?) '
        'ORDER BY (c.seri_no = ?) DESC, u.ad, c.seri_no LIMIT ?',
        [like, like, like, like, like, _normSeri(q), limit]);
    return rows.map(CihazBilgi.fromRow).toList();
  }

  Stream<List<CihazBilgi>> cihazAraStream(String sorgu) =>
      _watch(() => cihazAra(sorgu));

  /// Bir depodaki model bazlı adetler (yalnızca depoda duran cihazlar).
  Future<Map<String, int>> depoUrunSayilari(String depoId) async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT urun_id, COUNT(*) AS toplam
      FROM cihazlar
      WHERE depo_id = ? AND durum = 'depoda' AND deleted = 0
      GROUP BY urun_id
    ''', [depoId]);
    return {
      for (final r in rows)
        r['urun_id'] as String: (r['toplam'] as num?)?.toInt() ?? 0,
    };
  }

  Stream<Map<String, int>> depoUrunSayilariStream(String depoId) =>
      _watch(() => depoUrunSayilari(depoId));

  Future<void> _cihazHareketiTxn(
    Transaction txn, {
    required String cihazId,
    required HareketTipi tip,
    required String kullaniciId,
    String? hedefDepoId,
    String? aracId,
    String? kullanimYeri,
    String? not_,
  }) async {
    final rows = await txn.query('cihazlar',
        where: 'id = ?', whereArgs: [cihazId], limit: 1);
    if (rows.isEmpty) throw StateError('Cihaz bulunamadı');
    final c = Cihaz.fromMap(rows.first);

    if (c.durum != CihazDurumu.depoda || c.depoId == null) {
      throw StateError('${c.seriNo} şu an depoda değil, bu işlem yapılamaz');
    }
    final kaynakDepo = c.depoId!;
    final simdi = DateTime.now();
    final hareketId = _uuid.v4();

    // Hedefsiz "kullanım" = cihaz sahada kullanıldı: bulunduğu depo/araçtan
    // düşer, hiçbir stokta görünmez, nerede kullanıldığı kaydedilir.
    final sahada = tip == HareketTipi.kullanim && hedefDepoId == null;

    var guncelle = <String, Object?>{};
    switch (tip) {
      case HareketTipi.cikis:
        guncelle = {
          'depo_id': null,
          'durum': CihazDurumu.cikti.name,
          'arac_id': null,
          'kullanim_yeri': null,
        };
        break;
      // "Kullanıma ver" de transfer gibi çalışır: cihaz seçilen depoya veya
      // araca (seyyar depo) geçer; kayıt rapor için "kullanım" olarak tutulur.
      case HareketTipi.kullanim:
      case HareketTipi.iade:
      case HareketTipi.transfer:
        if (sahada) {
          guncelle = {
            'depo_id': null,
            'durum': CihazDurumu.kullanimda.name,
            'arac_id': null,
            'kullanim_yeri': (kullanimYeri == null || kullanimYeri.trim().isEmpty)
                ? 'Belirtilmedi'
                : kullanimYeri.trim(),
          };
          break;
        }
        if (hedefDepoId == null) throw StateError('Hedef depo veya araç seçin');
        if (hedefDepoId == kaynakDepo) {
          throw StateError('${c.seriNo} zaten orada');
        }
        guncelle = {
          'depo_id': hedefDepoId,
          'durum': CihazDurumu.depoda.name,
          'arac_id': null,
          'kullanim_yeri': null,
        };
        break;
      case HareketTipi.girisi:
        break;
    }

    await txn.update(
      'cihazlar',
      {
        ...guncelle,
        'updated_at': simdi.millisecondsSinceEpoch,
        'dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [cihazId],
    );

    await txn.insert(
      'stok_hareketleri',
      StokHareketi(
        id: hareketId,
        urunId: c.urunId,
        depoId: kaynakDepo,
        hedefDepoId: hedefDepoId,
        tip: tip,
        miktar: 1,
        kullaniciId: kullaniciId,
        tarih: simdi,
        not_: not_,
        cihazId: cihazId,
        updatedAt: simdi,
      ).toMap(),
    );

    if (sahada) {
      await txn.insert(
        'kullanim_kayitlari',
        KullanimKaydi(
          id: _uuid.v4(),
          stokHareketId: hareketId,
          aracId: null,
          kullanimYeri: guncelle['kullanim_yeri'] as String?,
          not_: not_,
          updatedAt: simdi,
        ).toMap(),
      );
    }
  }

  /// Depodaki bir veya birden çok cihaz için çıkış, transfer veya kullanıma
  /// verme kaydeder. Hepsi tek işlemdir: biri hatalıysa hiçbiri kaydedilmez.
  /// (Depoya alma / iade için [cihazlariGirisYap] kullanılır.)
  Future<void> cihazlariTopluHareketKaydet({
    required List<String> cihazIdleri,
    required HareketTipi tip,
    required String kullaniciId,
    String? hedefDepoId,
    String? aracId,
    String? kullanimYeri,
    String? not_,
  }) async {
    if (tip == HareketTipi.girisi) {
      throw ArgumentError('Depoya alma için cihazlariGirisYap kullanın');
    }
    if (cihazIdleri.isEmpty) throw StateError('Hiç cihaz seçilmedi');
    final db = await _database;

    await db.transaction((txn) async {
      for (final id in cihazIdleri.toSet()) {
        await _cihazHareketiTxn(
          txn,
          cihazId: id,
          tip: tip,
          kullaniciId: kullaniciId,
          hedefDepoId: hedefDepoId,
          aracId: aracId,
          kullanimYeri: kullanimYeri,
          not_: not_,
        );
      }
    });

    _notify();
  }

  // ---------------------------------------------------------------------
  // Senkronizasyon yardımcıları
  // ---------------------------------------------------------------------

  /// Senkronize edilen tablolar ve sunucuyla paylaşılan sütunlar
  /// (dirty yalnızca yerelde tutulur). Sıra: bağımlılığı olmayanlar önce.
  static const senkronKolonlari = <String, List<String>>{
    'depolar': ['id', 'ad', 'konum', 'tur', 'updated_at', 'deleted'],
    'urunler': [
      'id', 'ad', 'barkod', 'birim', 'kategori', 'min_stok_seviyesi',
      'seri_takipli', 'updated_at', 'deleted'
    ],
    'araclar': ['id', 'plaka', 'ad', 'aciklama', 'updated_at', 'deleted'],
    'kullanicilar': ['id', 'ad', 'email', 'rol', 'updated_at', 'deleted'],
    'cihazlar': [
      'id', 'urun_id', 'seri_no', 'depo_id', 'durum', 'arac_id',
      'kullanim_yeri', 'updated_at', 'deleted'
    ],
    'stok_hareketleri': [
      'id', 'urun_id', 'depo_id', 'hedef_depo_id', 'tip', 'miktar',
      'kullanici_id', 'tarih', 'not_', 'cihaz_id', 'updated_at', 'deleted'
    ],
    'kullanim_kayitlari': [
      'id', 'stok_hareket_id', 'arac_id', 'kullanim_yeri', 'not_',
      'updated_at', 'deleted'
    ],
  };

  /// Yerelde olup sunucuya henüz gönderilmemiş kayıt sayısı.
  Future<int> bekleyenSayisi() async {
    final db = await _database;
    var toplam = 0;
    for (final tablo in senkronKolonlari.keys) {
      toplam += Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM $tablo WHERE dirty = 1')) ??
          0;
    }
    return toplam;
  }

  Future<List<Map<String, Object?>>> kirliSatirlar(String tablo,
      {int limit = 200}) async {
    final db = await _database;
    return db.query(tablo, where: 'dirty = 1', limit: limit);
  }

  /// Kayıt sunucuya gönderildi. Gönderim sırasında kayıt yeniden
  /// değiştirildiyse (updated_at farklı) dirty olarak kalır.
  Future<void> senkronEdildi(String tablo, String id, int updatedAt) async {
    final db = await _database;
    await db.update(tablo, {'dirty': 0},
        where: 'id = ? AND updated_at = ?', whereArgs: [id, updatedAt]);
  }

  Future<int> sonCekim(String tablo) async {
    final db = await _database;
    final rows = await db.query('sync_meta',
        where: 'tablo = ?', whereArgs: [tablo], limit: 1);
    return rows.isEmpty ? 0 : (rows.first['son_cekim'] as num).toInt();
  }

  Future<void> sonCekimYaz(String tablo, int deger) async {
    final db = await _database;
    await db.insert('sync_meta', {'tablo': tablo, 'son_cekim': deger},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Sunucudan gelen satırları yerele uygular. Son yazan kazanır:
  /// yerelde bekleyen ve daha yeni bir değişiklik varsa ona dokunulmaz.
  /// Döndürdüğü değer: uygulanan satır sayısı. Seri numarası çakışmaları
  /// [cakismalar] listesine yazılır.
  Future<int> uzaktanUygula(
    String tablo,
    List<Map<String, dynamic>> satirlar,
    List<String> cakismalar,
  ) async {
    final kolonlar = senkronKolonlari[tablo]!;
    final db = await _database;
    var uygulanan = 0;

    await db.transaction((txn) async {
      for (final r in satirlar) {
        final id = r['id'] as String;
        final uzakGuncelleme = (r['updated_at'] as num).toInt();
        final map = <String, Object?>{for (final k in kolonlar) k: r[k]};
        map['dirty'] = 0;
        if (tablo == 'depolar' && map['tur'] == null) map['tur'] = 'sabit';

        final mevcut = await txn.query(tablo,
            columns: ['updated_at', 'dirty'],
            where: 'id = ?',
            whereArgs: [id],
            limit: 1);

        if (mevcut.isNotEmpty) {
          final yerelGuncelleme = (mevcut.first['updated_at'] as num).toInt();
          final yerelKirli = (mevcut.first['dirty'] as num).toInt() == 1;
          if (yerelKirli && yerelGuncelleme > uzakGuncelleme) continue;
          if (!yerelKirli && yerelGuncelleme >= uzakGuncelleme) continue;
          await txn.update(tablo, map, where: 'id = ?', whereArgs: [id]);
          uygulanan++;
        } else {
          if (tablo == 'cihazlar') {
            final ayniSeri = await txn.query('cihazlar',
                columns: ['id'],
                where: 'seri_no = ?',
                whereArgs: [r['seri_no']],
                limit: 1);
            if (ayniSeri.isNotEmpty) {
              cakismalar.add('${r['seri_no']}');
              continue;
            }
          }
          await txn.insert(tablo, map);
          uygulanan++;
        }
      }
    });

    if (uygulanan > 0) _notify();
    return uygulanan;
  }

  /// Giriş yapan kullanıcının yerel kaydı yoksa oluşturur (ad: e-postanın
  /// @ öncesi). Böylece hareket geçmişinde "kim yaptı" görünür.
  Future<void> kullaniciGarantiEt(String id, String email) async {
    final db = await _database;
    final kayitli = await db.query('kullanicilar',
        columns: ['id'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (kayitli.isNotEmpty) return;
    await db.insert(
      'kullanicilar',
      Kullanici(
        id: id,
        ad: email.contains('@') ? email.split('@').first : email,
        email: email,
        rol: KullaniciRol.sahaKullanicisi,
        updatedAt: DateTime.now(),
      ).toMap(),
    );
    _notify();
  }

  /// Yerel değişiklik olduğunda tetiklenir (senkron servisi dinler).
  Stream<void> get degisiklikler => _changes.stream;
}
