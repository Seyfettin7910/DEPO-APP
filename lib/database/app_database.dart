import 'dart:math' as math;
import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../services/etiket/etiket_kodu.dart';
import 'etiket_modelleri.dart';
import 'models.dart';
import '../services/bolge_adi.dart' show trBuyuk;

export 'etiket_modelleri.dart';

part 'app_database_etiket.dart';
part 'app_database_malzeme.dart';
part 'app_database_birlestir.dart';

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
  kutu_icerigi INTEGER,
  birlesti_id TEXT,
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
  sebep TEXT,
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
  enlem REAL,
  boylam REAL,
  konum_hassasiyet REAL,
  il TEXT,
  ilce TEXT,
  mahalle TEXT,
  tutanak TEXT,
  tutanak_tarihi INTEGER,
  tutanak_kullanici_id TEXT,
  updated_at INTEGER NOT NULL,
  dirty INTEGER NOT NULL DEFAULT 1,
  deleted INTEGER NOT NULL DEFAULT 0
);
''';

/// Bildirimler ve "bildirim yapıldı" işaretleri: yalnızca bu cihazda
/// tutulur, sunucuyla senkronize edilmez (şema sürümü 10).
const _bildirimTabloSql = [
  '''
CREATE TABLE IF NOT EXISTS bildirimler (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tur TEXT NOT NULL,
  baslik TEXT NOT NULL,
  govde TEXT NOT NULL,
  hedef TEXT,
  tarih INTEGER NOT NULL,
  okundu INTEGER NOT NULL DEFAULT 0
)''',
  '''
CREATE TABLE IF NOT EXISTS bildirim_gorulen (
  anahtar TEXT PRIMARY KEY,
  tarih INTEGER NOT NULL
)''',
];

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
  final String? sebep;

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
    this.sebep,
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
  alim_tarihi INTEGER,
  firma TEXT,
  ihale TEXT,
  garanti_bitis INTEGER,
  servis_durumu TEXT,
  updated_at INTEGER NOT NULL,
  dirty INTEGER NOT NULL DEFAULT 1,
  deleted INTEGER NOT NULL DEFAULT 0
)
''';

/// Arıza / servis dosyaları (şema sürümü 9'da eklendi).
const _servisTabloSql = '''
CREATE TABLE servis_kayitlari (
  id TEXT PRIMARY KEY,
  cihaz_id TEXT NOT NULL,
  urun_id TEXT NOT NULL,
  acilis_tarihi INTEGER NOT NULL,
  ariza_aciklama TEXT,
  karar TEXT NOT NULL,
  onarim_yeri TEXT,
  firma TEXT,
  gonderim_tarihi INTEGER,
  donus_tarihi INTEGER,
  sonuc TEXT,
  sonuc_aciklama TEXT,
  yeni_seri_no TEXT,
  kapanis TEXT,
  kapanis_tarihi INTEGER,
  kullanici_id TEXT,
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

  /// Kurum etiketi (varsa).
  final String? etiketKodu;
  final EtiketDurumu? etiketDurumu;

  /// Montajdaki tutanak durumu (yalnızca cihaz montajlıyken anlamlı).
  final String? tutanak;

  const CihazBilgi({
    required this.cihaz,
    required this.urunAdi,
    this.depoAdi,
    this.aracPlaka,
    this.depoArac = false,
    this.etiketKodu,
    this.etiketDurumu,
    this.tutanak,
  });

  /// Basılmış ama yapıştırma doğrulaması yapılmamış (veya uyuşmazlık var).
  bool get etiketDogrulanmadi =>
      etiketDurumu == EtiketDurumu.basildi ||
      etiketDurumu == EtiketDurumu.uyusmazlik;

  factory CihazBilgi.fromRow(Map<String, Object?> r) => CihazBilgi(
        cihaz: Cihaz.fromMap(r),
        urunAdi: r['urun_adi'] as String,
        depoAdi: r['depo_adi'] as String?,
        aracPlaka: r['arac_plaka'] as String?,
        depoArac: r['depo_tur'] == 'arac',
        etiketKodu: r['etiket_kodu'] as String?,
        etiketDurumu: r['etiket_durumu'] == null
            ? null
            : etiketDurumuCoz(r['etiket_durumu']),
        tutanak: r['tutanak'] as String?,
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
  final String? sebep;
  final double? enlem;
  final double? boylam;
  final String? il;
  final String? ilce;
  final String? mahalle;
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
    this.sebep,
    this.enlem,
    this.boylam,
    this.il,
    this.ilce,
    this.mahalle,
  });
}

/// Minimum adedin altına inmiş (veya eşit) ürün. Hesap, depolar ve araçlardaki
/// (seyyar depo) kullanılmamış toplam adede göre yapılır.
class KritikStok {
  const KritikStok({
    required this.urunId,
    required this.urunAdi,
    this.kategori,
    required this.minStok,
    required this.depoda,
    required this.aracta,
    this.birim,
  });

  final String urunId;
  final String urunAdi;
  final String? kategori;
  final int minStok;

  /// Miktarlı malzemede birim (metre, paket…); seri numaralı üründe null.
  final String? birim;
  final int depoda;
  final int aracta;

  /// Depolar + araçlar.
  int get toplam => depoda + aracta;

  /// Minimumun üstüne çıkmak için gereken adet.
  int get eksik => minStok - toplam + 1;

  String get durum => toplam == 0
      ? 'Tükendi'
      : (toplam < minStok ? 'Kritik' : 'Sınırda');
}

class KullanimRaporSatiri {
  final String urunAdi;
  final String depoAdi;
  final String? aracPlaka;
  final String? kullanimYeri;
  final int miktar;
  final DateTime tarih;
  final String? seriNo;
  final double? enlem;
  final double? boylam;
  final String? il;
  final String? ilce;
  final String? mahalle;
  final String? tutanak;
  final String birim;

  /// Seri numarasız malzeme kullanımı (kablo, adaptör…).
  bool get malzeme => seriNo == null;

  KullanimRaporSatiri({
    required this.urunAdi,
    required this.depoAdi,
    this.aracPlaka,
    this.kullanimYeri,
    required this.miktar,
    required this.tarih,
    this.seriNo,
    this.enlem,
    this.boylam,
    this.il,
    this.ilce,
    this.mahalle,
    this.tutanak,
    this.birim = 'adet',
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
  Future<Database>? _acilis;
  final _changes = StreamController<void>.broadcast();

  /// Veritabanı bağlantısı. Kapanmışsa (ör. Android'de arka plan görevi
  /// aynı bağlantıyı kapattıysa) kendiliğinden yeniden açılır.
  Future<Database> get _database {
    final db = _db;
    if (db != null && db.isOpen) return Future.value(db);
    final yeniden = db != null;
    return _acilis ??= _ac().then((d) {
      // Kapanıp yeniden açıldıysa açık ekranlar verilerini tazelesin.
      if (yeniden) Future.microtask(_notify);
      return d;
    }).whenComplete(() => _acilis = null);
  }

  Future<Database> _ac() async {
    // Web'de dosya sistemi yok; veritabanı adıyla IndexedDB'de tutulur.
    final path = kIsWeb
        ? 'depo_app.sqlite'
        : p.join(await getDatabasesPath(), 'depo_app.sqlite');
    _db = await openDatabase(
      path,
      version: 14,
      onCreate: (db, version) async {
        for (final stmt in _createTablesSql.split(';')) {
          final trimmed = stmt.trim();
          if (trimmed.isNotEmpty) await db.execute(trimmed);
        }
        await db.execute(_cihazlarTabloSql);
        await db.execute(_servisTabloSql);
        await db.execute(_syncMetaSql);
        for (final t in _bildirimTabloSql) {
          await db.execute(t);
        }
        for (final t in _etiketTabloSql) {
          await db.execute(t);
        }
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
        if (oldVersion >= 2 && oldVersion < 5) {
          // 1.11.0: alım / garanti bilgileri. (v2'den önce cihazlar tablosu
          // yeni oluşturulduğu için bu sütunlar zaten içinde gelir.)
          await db.execute('ALTER TABLE cihazlar ADD COLUMN alim_tarihi INTEGER');
          await db.execute('ALTER TABLE cihazlar ADD COLUMN firma TEXT');
          await db.execute('ALTER TABLE cihazlar ADD COLUMN ihale TEXT');
          await db.execute('ALTER TABLE cihazlar ADD COLUMN garanti_bitis INTEGER');
        }
        if (oldVersion < 6) {
          // 1.12.0: depoya geri almada sebep (Arıza, Değişim...)
          await db.execute('ALTER TABLE stok_hareketleri ADD COLUMN sebep TEXT');
        }
        if (oldVersion < 7) {
          // 1.13.0: sahada kullanım anındaki GPS konumu
          await db.execute('ALTER TABLE kullanim_kayitlari ADD COLUMN enlem REAL');
          await db.execute('ALTER TABLE kullanim_kayitlari ADD COLUMN boylam REAL');
          await db.execute(
              'ALTER TABLE kullanim_kayitlari ADD COLUMN konum_hassasiyet REAL');
        }
        if (oldVersion < 8) {
          // 1.14.0: kurulum noktasının il / ilçe / mahalle (köy) bilgisi
          await db.execute('ALTER TABLE kullanim_kayitlari ADD COLUMN il TEXT');
          await db.execute('ALTER TABLE kullanim_kayitlari ADD COLUMN ilce TEXT');
          await db.execute('ALTER TABLE kullanim_kayitlari ADD COLUMN mahalle TEXT');
        }
        if (oldVersion >= 2 && oldVersion < 9) {
          // 1.17.0: arızalı / serviste / hurda durumu
          await db.execute('ALTER TABLE cihazlar ADD COLUMN servis_durumu TEXT');
        }
        if (oldVersion < 9) {
          await db.execute(_servisTabloSql);
        }
        if (oldVersion < 10) {
          // 1.19.0: bildirimler (yalnızca yerel)
          for (final t in _bildirimTabloSql) {
            await db.execute(t);
          }
        }
        if (oldVersion < 11) {
          // 1.22.0: kurum etiketi (barkod / karekod)
          for (final t in _etiketTabloSql) {
            await db.execute(t);
          }
        }
        if (oldVersion < 12) {
          // 1.24.0: montaj tutanağı (alındı / alınacak / kurum içi)
          await db.execute('ALTER TABLE kullanim_kayitlari ADD COLUMN tutanak TEXT');
          await db.execute(
              'ALTER TABLE kullanim_kayitlari ADD COLUMN tutanak_tarihi INTEGER');
          await db.execute(
              'ALTER TABLE kullanim_kayitlari ADD COLUMN tutanak_kullanici_id TEXT');
        }
        if (oldVersion < 13) {
          // 1.27.0: malzemenin bir kutu / topunda kaç birim var (305 m gibi)
          await db.execute('ALTER TABLE urunler ADD COLUMN kutu_icerigi INTEGER');
        }
        if (oldVersion < 14) {
          // 1.30.0: ürün birleştirme (birleşen ürün → kalan ürün)
          await db.execute('ALTER TABLE urunler ADD COLUMN birlesti_id TEXT');
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
    final malzeme = (await malzemeStoklari())
        .values
        .where((m) => (m[id] ?? 0) > 0)
        .length;
    if (malzeme > 0) {
      throw StateError('İçinde $malzeme çeşit malzeme var. Önce malzemeleri '
          'başka yere transfer edin.');
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
    final rows = await db.query('urunler',
        where: 'UPPER(barkod) = UPPER(?) AND deleted = 0',
        whereArgs: [barkod.trim()],
        limit: 1);
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
    // false: seri numarasız, miktarla takip edilen malzeme (kablo, adaptör…)
    bool seriTakipli = true,
    // Malzemenin bir kutusunda / topunda kaç birim var (ör. 305 metre).
    int? kutuIcerigi,
  }) async {
    final db = await _database;
    final urun = Urun(
      id: _uuid.v4(),
      ad: ad,
      barkod: barkod,
      birim: seriTakipli ? 'adet' : birim,
      kategori: kategori,
      minStokSeviyesi: minStokSeviyesi,
      seriTakipli: seriTakipli,
      kutuIcerigi: seriTakipli ? null : kutuIcerigi,
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
    int? kutuIcerigi,
  }) async {
    final db = await _database;
    final n = await db.update(
      'urunler',
      {
        'kutu_icerigi': kutuIcerigi,
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
    final kosullar = <String>['sh.deleted = 0', 'kk.deleted = 0'];
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
        c.seri_no as seri_no,
        kk.enlem as enlem,
        kk.boylam as boylam,
        kk.il as il,
        kk.ilce as ilce,
        kk.mahalle as mahalle,
        kk.tutanak as tutanak,
        u.birim as birim
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
              tutanak: r['tutanak'] as String?,
              birim: (r['birim'] as String?) ?? 'adet',
              urunAdi: r['urun_adi'] as String,
              depoAdi: r['depo_adi'] as String,
              aracPlaka: r['arac_plaka'] as String?,
              kullanimYeri: r['kullanim_yeri'] as String?,
              seriNo: r['seri_no'] as String?,
              enlem: (r['enlem'] as num?)?.toDouble(),
              boylam: (r['boylam'] as num?)?.toDouble(),
              il: r['il'] as String?,
              ilce: r['ilce'] as String?,
              mahalle: r['mahalle'] as String?,
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
             c.alim_tarihi AS alim_tarihi, c.firma AS firma,
             c.ihale AS ihale, c.garanti_bitis AS garanti_bitis,
             c.servis_durumu AS servis_durumu,
             c.updated_at AS guncelleme,
             (SELECT kk.enlem || ',' || kk.boylam FROM kullanim_kayitlari kk
                JOIN stok_hareketleri sh ON sh.id = kk.stok_hareket_id
               WHERE sh.cihaz_id = c.id AND kk.enlem IS NOT NULL
               ORDER BY sh.tarih DESC LIMIT 1) AS son_konum
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
    final kosullar = <String>[
      'sh.deleted = 0',
      "(sh.cihaz_id IS NOT NULL OR sh.tip = 'silme' OR u.seri_takipli = 0)",
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
      SELECT sh.tarih AS tarih, sh.tip AS tip, c.seri_no AS seri_no,
             u.ad AS urun_adi, d.ad AS kaynak, hd.ad AS hedef,
             kk.kullanim_yeri AS kullanim_yeri, k.ad AS kullanici,
             sh.not_ AS not_, sh.sebep AS sebep, sh.miktar AS miktar,
             u.birim AS birim, u.seri_takipli AS seri_takipli
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
        AND servis_durumu IS NULL
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

  /// Ürün başına depolar + araçlardaki toplam: seri numaralı üründe sağlam
  /// cihaz adedi, miktarlı malzemede miktar (metre, paket…).
  Future<Map<String, int>> urunToplamStoklari() async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT urun_id, COUNT(*) AS toplam
      FROM cihazlar
      WHERE durum = 'depoda' AND deleted = 0 AND servis_durumu IS NULL
      GROUP BY urun_id
    ''');
    final sonuc = {
      for (final r in rows)
        r['urun_id'] as String: (r['toplam'] as num?)?.toInt() ?? 0,
    };
    final depolar = {for (final d in await tumDepolar()) d.id};
    for (final e in (await malzemeStoklari()).entries) {
      sonuc[e.key] = e.value.entries
          .where((x) => depolar.contains(x.key))
          .fold<int>(0, (t, x) => t + x.value);
    }
    return sonuc;
  }

  /// Minimum adet tanımlı ve depolar + araçlardaki (arızalılar hariç) toplamı minimuma eşit /
  /// altında olan ürünler (en kritik üstte).
  Future<List<KritikStok>> kritikStoklar() async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT u.id AS id, u.ad AS ad, u.kategori AS kategori,
             u.min_stok_seviyesi AS min_stok,
             SUM(CASE WHEN c.id IS NOT NULL AND d.tur = 'sabit' THEN 1 ELSE 0 END)
               AS depoda,
             SUM(CASE WHEN c.id IS NOT NULL AND d.tur = 'arac' THEN 1 ELSE 0 END)
               AS aracta
      FROM urunler u
      LEFT JOIN cihazlar c
             ON c.urun_id = u.id AND c.deleted = 0 AND c.durum = 'depoda'
                AND c.servis_durumu IS NULL
      LEFT JOIN depolar d ON d.id = c.depo_id AND d.deleted = 0
      WHERE u.deleted = 0 AND u.min_stok_seviyesi > 0 AND u.seri_takipli = 1
      GROUP BY u.id
      HAVING (depoda + aracta) <= u.min_stok_seviyesi
    ''');
    final liste = [
      for (final r in rows)
        KritikStok(
          urunId: r['id'] as String,
          urunAdi: r['ad'] as String,
          kategori: r['kategori'] as String?,
          minStok: (r['min_stok'] as num).toInt(),
          depoda: (r['depoda'] as num?)?.toInt() ?? 0,
          aracta: (r['aracta'] as num?)?.toInt() ?? 0,
        ),
    ];
    // Miktarlı malzemeler: depolar + araçlardaki toplam miktar.
    final malzemeler = (await tumUrunler())
        .where((u) => u.miktarli && u.minStokSeviyesi > 0)
        .toList();
    if (malzemeler.isNotEmpty) {
      final stok = await malzemeStoklari();
      final turler = {for (final d in await tumDepolar()) d.id: d.tur};
      for (final u in malzemeler) {
        var depoda = 0, aracta = 0;
        for (final e in (stok[u.id] ?? const <String, int>{}).entries) {
          final tur = turler[e.key];
          if (tur == null || e.value <= 0) continue;
          if (tur == DepoTuru.arac) {
            aracta += e.value;
          } else {
            depoda += e.value;
          }
        }
        if (depoda + aracta <= u.minStokSeviyesi) {
          liste.add(KritikStok(
            urunId: u.id,
            urunAdi: u.ad,
            kategori: u.kategori,
            minStok: u.minStokSeviyesi,
            depoda: depoda,
            aracta: aracta,
            birim: u.birim,
          ));
        }
      }
    }
    liste.sort((a, b) {
      final c = (a.toplam / a.minStok).compareTo(b.toplam / b.minStok);
      return c != 0
          ? c
          : a.urunAdi.toLowerCase().compareTo(b.urunAdi.toLowerCase());
    });
    return liste;
  }

  Stream<List<KritikStok>> kritikStoklarStream() => _watch(kritikStoklar);

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
             c.seri_no AS seri_no, k.ad AS kullanici_adi, sh.sebep AS sebep
      FROM stok_hareketleri sh
      JOIN urunler u ON u.id = sh.urun_id
      JOIN depolar d ON d.id = sh.depo_id
      LEFT JOIN depolar hd ON hd.id = sh.hedef_depo_id
      LEFT JOIN kullanim_kayitlari kk ON kk.stok_hareket_id = sh.id
      LEFT JOIN araclar a ON a.id = kk.arac_id
      LEFT JOIN cihazlar c ON c.id = sh.cihaz_id
      LEFT JOIN kullanicilar k ON k.id = sh.kullanici_id
      WHERE sh.deleted = 0
        AND (sh.cihaz_id IS NOT NULL OR u.seri_takipli = 0)
        AND (sh.depo_id = ? OR sh.hedef_depo_id = ?)
      ORDER BY sh.tarih DESC
      LIMIT ?
    ''', [depoId, depoId, limit]);

    return rows.map((r) {
      final tip = hareketTipiCoz(r['tip']);
      final miktar = (r['miktar'] as num).toInt();
      var isaretli = 0;
      String? karsiDepo;
      switch (tip) {
        case HareketTipi.girisi:
          isaretli = miktar;
          break;
        case HareketTipi.cikis:
        case HareketTipi.silme:
        case HareketTipi.hurda:
          isaretli = -miktar;
          break;
        case HareketTipi.servis:
          // Servis adımları stoğu değiştirmez (miktar 0); onarım sonrası başka
          // depoya konduysa transfer gibi, değişimde eski cihaz düşer.
          if (r['hedef_depo_adi'] != null && miktar > 0) {
            if (r['depo_id'] == depoId) {
              isaretli = -miktar;
              karsiDepo = r['hedef_depo_adi'] as String?;
            } else {
              isaretli = miktar;
              karsiDepo = r['depo_adi'] as String?;
            }
          } else {
            isaretli = -miktar;
          }
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
        sebep: r['sebep'] as String?,
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
             c.alim_tarihi AS alim_tarihi, c.firma AS firma, c.ihale AS ihale,
             c.garanti_bitis AS garanti_bitis, c.servis_durumu AS servis_durumu,
             c.dirty AS dirty, c.deleted AS deleted,
             u.ad AS urun_adi, d.ad AS depo_adi, d.tur AS depo_tur,
             a.plaka AS arac_plaka,
             e.kod AS etiket_kodu, e.durum AS etiket_durumu,
             CASE WHEN c.durum = 'kullanimda' THEN
               (SELECT kk.tutanak FROM kullanim_kayitlari kk
                  JOIN stok_hareketleri sh ON sh.id = kk.stok_hareket_id
                 WHERE sh.cihaz_id = c.id AND sh.deleted = 0
                 ORDER BY sh.tarih DESC LIMIT 1)
             END AS tutanak
      FROM cihazlar c
      JOIN urunler u ON u.id = c.urun_id
      LEFT JOIN depolar d ON d.id = c.depo_id
      LEFT JOIN araclar a ON a.id = c.arac_id
      LEFT JOIN etiketler e ON e.id = (SELECT x.id FROM etiketler x
        WHERE x.cihaz_id = c.id AND x.deleted = 0 ORDER BY x.olusturma LIMIT 1)
  ''';

  /// Okutulan/yazılan seri numarasına ait cihazı bulur (büyük-küçük harf duyarsız).
  Future<Cihaz?> seriNoIleCihazBul(String seriNo) async {
    final db = await _database;
    final rows = await db.query('cihazlar',
        where: 'seri_no = ? COLLATE NOCASE AND deleted = 0',
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
             k.ad AS kullanici_adi, sh.sebep AS sebep,
             kk.enlem AS enlem, kk.boylam AS boylam,
             kk.il AS il, kk.ilce AS ilce, kk.mahalle AS mahalle
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
              tip: hareketTipiCoz(r['tip']),
              tarih: DateTime.fromMillisecondsSinceEpoch((r['tarih'] as num).toInt()),
              depoId: r['depo_id'] as String?,
              hedefDepoId: r['hedef_depo_id'] as String?,
              depoAdi: r['depo_adi'] as String?,
              hedefDepoAdi: r['hedef_depo_adi'] as String?,
              aracPlaka: r['arac_plaka'] as String?,
              kullanimYeri: r['kullanim_yeri'] as String?,
              not_: r['not_'] as String?,
              kullaniciAdi: r['kullanici_adi'] as String?,
              sebep: r['sebep'] as String?,
              enlem: (r['enlem'] as num?)?.toDouble(),
              boylam: (r['boylam'] as num?)?.toDouble(),
              il: r['il'] as String?,
              ilce: r['ilce'] as String?,
              mahalle: r['mahalle'] as String?,
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
    AlimBilgisi? alim,
    String? sebep,
    // Kurum etiketi: seçilmişse her cihaza kod üretilir.
    String? kurumKoduId,
    bool etiketKuyruga = false,
    // Seri numarası olmayan ürünler: kurum kodu seri no olarak kullanılır.
    Set<String> seriNosuz = const {},
  }) async {
    {
      final u = await (await _database).query('urunler',
          columns: ['seri_takipli', 'ad'], where: 'id = ?', whereArgs: [urunId],
          limit: 1);
      if (u.isNotEmpty && (u.first['seri_takipli'] as num?)?.toInt() == 0) {
        throw StateError('${u.first['ad']} miktarla takip edilen bir malzeme; '
            'seri no ile değil "Malzeme girişi" ile girilir');
      }
    }
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
        final cihazId = await _girisTxn(txn,
            urunId: urunId,
            depoId: depoId,
            seri: seri,
            kullaniciId: kullaniciId,
            not_: not_,
            alim: alim,
            sebep: sebep,
            zaman: simdi);
        final seriNosuzMu = seriNosuz.contains(seri);
        if (kurumKoduId != null || seriNosuzMu) {
          if (kurumKoduId == null) {
            throw StateError('Seri nosuz ürün için kurum kodu seçin');
          }
          await _etiketUretTxn(txn,
              cihazId: cihazId,
              kurumKoduId: kurumKoduId,
              kuyruga: etiketKuyruga,
              kullaniciId: kullaniciId,
              zaman: simdi,
              sabitKod: seriNosuzMu ? seri : null);
        }
      }
    });

    _notify();
  }

  /// Tek bir seri numarasının depoya girişi (yeni kayıt veya geri alma).
  /// Cihazın id'sini döndürür.
  Future<String> _girisTxn(
    Transaction txn, {
    required String urunId,
    required String depoId,
    required String seri,
    required String kullaniciId,
    String? not_,
    AlimBilgisi? alim,
    String? sebep,
    required DateTime zaman,
  }) async {
    final rows = await txn.query('cihazlar',
        where: 'seri_no = ? COLLATE NOCASE', whereArgs: [seri], limit: 1);
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
          alimTarihi: alim?.alimTarihi,
          firma: alim?.firmaVeyaNull,
          ihale: alim?.ihaleVeyaNull,
          garantiBitis: alim?.garantiBitis,
          updatedAt: zaman,
        ).toMap(),
      );
    } else {
      final mevcut = Cihaz.fromMap(rows.first);
      if (mevcut.durum == CihazDurumu.depoda && !mevcut.deleted) {
        throw StateError('$seri zaten depoda kayıtlı');
      }
      if (!mevcut.deleted &&
          (mevcut.servisDurumu == ServisDurumu.hurda ||
              mevcut.servisDurumu == ServisDurumu.degistirildi)) {
        throw StateError('$seri ${mevcut.servisDurumu!.etiket.toLowerCase()}; '
            'tekrar giriş yapılamaz');
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
          'servis_durumu': null,
          'deleted': 0,
          'updated_at': zaman.millisecondsSinceEpoch,
          'dirty': 1,
          // Yeniden girişte yalnızca doldurulan alım bilgileri yazılır.
          if (alim != null)
            for (final e in alim.kolonlar().entries)
              if (e.value != null) e.key: e.value,
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
        tarih: zaman,
        not_: not_,
        sebep: sebep,
        cihazId: cihazId,
        updatedAt: zaman,
      ).toMap(),
    );
    return cihazId;
  }

  // ---------------------------------------------------------------------
  // Arıza / servis / hurda
  // ---------------------------------------------------------------------

  Future<Cihaz> _cihazTxn(Transaction txn, String cihazId) async {
    final rows = await txn.query('cihazlar',
        where: 'id = ?', whereArgs: [cihazId], limit: 1);
    if (rows.isEmpty) throw StateError('Cihaz bulunamadı');
    return Cihaz.fromMap(rows.first);
  }

  Future<void> _cihazGuncelleTxn(Transaction txn, String cihazId,
      Map<String, Object?> degerler, DateTime zaman) async {
    await txn.update(
      'cihazlar',
      {
        ...degerler,
        'updated_at': zaman.millisecondsSinceEpoch,
        'dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [cihazId],
    );
  }

  /// Servis adımını hareket geçmişine yazar (hareketler hiç silinmez).
  Future<void> _servisHareketiTxn(
    Transaction txn, {
    required Cihaz cihaz,
    required String adim,
    required String kullaniciId,
    required DateTime zaman,
    HareketTipi tip = HareketTipi.servis,
    String? depoId,
    String? hedefDepoId,
    int miktar = 0,
    String? not_,
  }) async {
    await txn.insert(
      'stok_hareketleri',
      StokHareketi(
        id: _uuid.v4(),
        urunId: cihaz.urunId,
        depoId: depoId ?? cihaz.depoId ?? '',
        hedefDepoId: hedefDepoId,
        tip: tip,
        miktar: miktar,
        kullaniciId: kullaniciId,
        tarih: zaman,
        not_: (not_ == null || not_.trim().isEmpty) ? null : not_.trim(),
        cihazId: cihaz.id,
        sebep: adim,
        updatedAt: zaman,
      ).toMap(),
    );
  }

  Future<ServisKaydi?> _acikServisTxn(
      DatabaseExecutor txn, String cihazId) async {
    final rows = await txn.query('servis_kayitlari',
        where: 'cihaz_id = ? AND kapanis IS NULL AND deleted = 0',
        whereArgs: [cihazId],
        orderBy: 'acilis_tarihi DESC',
        limit: 1);
    return rows.isEmpty ? null : ServisKaydi.fromMap(rows.first);
  }

  Future<void> _servisGuncelleTxn(Transaction txn, String id,
      Map<String, Object?> degerler, DateTime zaman) async {
    await txn.update(
      'servis_kayitlari',
      {
        ...degerler,
        'updated_at': zaman.millisecondsSinceEpoch,
        'dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static String? _bosIseNull(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();

  /// Depodaki cihaz için arıza kaydı açar: cihaz "arızalı" olur ve
  /// kullanılamaz. [karar]: tamir | degisim
  Future<void> _arizaKaydiAcTxn(
    Transaction txn, {
    required String cihazId,
    required String karar,
    String? aciklama,
    required String kullaniciId,
    required DateTime zaman,
  }) async {
    final c = await _cihazTxn(txn, cihazId);
    if (c.durum != CihazDurumu.depoda || c.depoId == null) {
      throw StateError('${c.seriNo} depoda değil');
    }
    if (c.arizali) {
      throw StateError(
          '${c.seriNo} zaten ${c.servisDurumu!.kisa.toLowerCase()}');
    }
    final durum = karar == 'degisim'
        ? ServisDurumu.degisimGerekli
        : ServisDurumu.tamirGerekli;
    await _cihazGuncelleTxn(txn, cihazId, {'servis_durumu': durum.name}, zaman);
    await txn.insert(
      'servis_kayitlari',
      ServisKaydi(
        id: _uuid.v4(),
        cihazId: cihazId,
        urunId: c.urunId,
        acilisTarihi: zaman,
        arizaAciklama: _bosIseNull(aciklama),
        karar: karar,
        kullaniciId: kullaniciId,
        updatedAt: zaman,
      ).toMap(),
    );
    await _servisHareketiTxn(txn,
        cihaz: c,
        adim: 'Arıza kaydı: ${servisKararAdlari[karar]}',
        kullaniciId: kullaniciId,
        zaman: zaman,
        not_: aciklama);
  }

  /// Cihazı hurdaya ayırır: stoktan düşer, açık servis kaydı kapanır.
  Future<void> _hurdaTxn(
    Transaction txn, {
    required String cihazId,
    required String sebep,
    String? not_,
    required String kullaniciId,
    required DateTime zaman,
  }) async {
    final c = await _cihazTxn(txn, cihazId);
    if (c.durum != CihazDurumu.depoda || c.depoId == null) {
      throw StateError('${c.seriNo} depoda değil; önce depoya geri alın');
    }
    if (c.servisDurumu == ServisDurumu.garantide) {
      throw StateError(
          '${c.seriNo} garanti servisinde; önce dönüş sonucunu girin');
    }
    await _cihazGuncelleTxn(
        txn,
        cihazId,
        {
          'depo_id': null,
          'durum': CihazDurumu.cikti.name,
          'arac_id': null,
          'kullanim_yeri': null,
          'servis_durumu': ServisDurumu.hurda.name,
        },
        zaman);
    await _servisHareketiTxn(txn,
        cihaz: c,
        tip: HareketTipi.hurda,
        adim: sebep,
        miktar: 1,
        kullaniciId: kullaniciId,
        zaman: zaman,
        not_: not_);
    final acik = await _acikServisTxn(txn, cihazId);
    if (acik != null) {
      await _servisGuncelleTxn(
          txn,
          acik.id,
          {
            'kapanis': 'hurda',
            'kapanis_tarihi': zaman.millisecondsSinceEpoch,
            if (acik.sonuc == null) 'sonuc': 'onarilamadi',
            if (acik.gonderimTarihi != null && acik.donusTarihi == null)
              'donus_tarihi': zaman.millisecondsSinceEpoch,
            if (acik.sonucAciklama == null && _bosIseNull(not_) != null)
              'sonuc_aciklama': _bosIseNull(not_),
          },
          zaman);
    }
  }

  /// Sahada kullanılan / çıkışı yapılmış cihazı depoya geri alır.
  /// [arizaKarari] verilirse (tamir | degisim) arıza kaydı açılır;
  /// [hurda] ise cihaz alındığı gibi hurdaya ayrılır (ömrünü doldurdu vb.).
  Future<void> sahadanGeriAl({
    required String cihazId,
    required String depoId,
    required String sebep,
    required String kullaniciId,
    String? not_,
    String? arizaKarari,
    bool hurda = false,
  }) async {
    final db = await _database;
    await db.transaction((txn) async {
      final c = await _cihazTxn(txn, cihazId);
      final simdi = DateTime.now();
      await _girisTxn(txn,
          urunId: c.urunId,
          depoId: depoId,
          seri: c.seriNo,
          kullaniciId: kullaniciId,
          not_: not_,
          sebep: sebep,
          zaman: simdi);
      // Aynı anda yazılan kayıtlar geçmişte doğru sırada görünsün.
      final sonra = simdi.add(const Duration(milliseconds: 1));
      if (hurda) {
        await _hurdaTxn(txn,
            cihazId: cihazId,
            sebep: sebep,
            not_: not_,
            kullaniciId: kullaniciId,
            zaman: sonra);
      } else if (arizaKarari != null) {
        await _arizaKaydiAcTxn(txn,
            cihazId: cihazId,
            karar: arizaKarari,
            aciklama: not_,
            kullaniciId: kullaniciId,
            zaman: sonra);
      }
    });
    _notify();
  }

  /// Depodaki sağlam cihazı arızalı olarak işaretler.
  Future<void> arizaKaydiAc({
    required String cihazId,
    required String karar,
    String? aciklama,
    required String kullaniciId,
  }) async {
    final db = await _database;
    await db.transaction((txn) => _arizaKaydiAcTxn(txn,
        cihazId: cihazId,
        karar: karar,
        aciklama: aciklama,
        kullaniciId: kullaniciId,
        zaman: DateTime.now()));
    _notify();
  }

  /// Arızalı cihazı servise gönderir. [yer]: garanti (firmaya) | ic
  /// (kendi bünyemizde). [tarih]: gönderim / onarıma alma zamanı.
  Future<void> servisGonder({
    required String cihazId,
    required String yer,
    String? firma,
    required DateTime tarih,
    String? not_,
    required String kullaniciId,
  }) async {
    final db = await _database;
    await db.transaction((txn) async {
      final c = await _cihazTxn(txn, cihazId);
      if (c.servisDurumu != ServisDurumu.tamirGerekli &&
          c.servisDurumu != ServisDurumu.degisimGerekli) {
        throw StateError('${c.seriNo} servise gönderilecek durumda değil');
      }
      final simdi = DateTime.now();
      var kayit = await _acikServisTxn(txn, cihazId);
      if (kayit == null) {
        // Dosya yoksa (eski / eksik veri) aç
        kayit = ServisKaydi(
          id: _uuid.v4(),
          cihazId: cihazId,
          urunId: c.urunId,
          acilisTarihi: simdi,
          karar: c.servisDurumu == ServisDurumu.degisimGerekli
              ? 'degisim'
              : 'tamir',
          kullaniciId: kullaniciId,
          updatedAt: simdi,
        );
        await txn.insert('servis_kayitlari', kayit.toMap());
      }
      final firmaTemiz = _bosIseNull(firma);
      await _servisGuncelleTxn(
          txn,
          kayit.id,
          {
            'onarim_yeri': yer,
            'firma': firmaTemiz,
            'gonderim_tarihi': tarih.millisecondsSinceEpoch,
          },
          simdi);
      await _cihazGuncelleTxn(
          txn,
          cihazId,
          {
            'servis_durumu': (yer == 'garanti'
                    ? ServisDurumu.garantide
                    : ServisDurumu.onarimda)
                .name
          },
          simdi);
      await _servisHareketiTxn(txn,
          cihaz: c,
          adim: yer == 'garanti'
              ? 'Garanti servisine gönderildi'
              : 'Kendi bünyemizde onarıma alındı',
          kullaniciId: kullaniciId,
          zaman: simdi,
          not_: [
            if (firmaTemiz != null) firmaTemiz,
            if (_bosIseNull(not_) != null) _bosIseNull(not_)!,
          ].join(' · '));
    });
    _notify();
  }

  /// Servisten dönen cihazın sonucu.
  /// - onarildi: cihaz sağlam olarak [depoId] deposuna eklenir.
  /// - degistirildi: eski cihaz firmaya teslim edilmiş sayılır (stoktan
  ///   düşer); [yeniSeriNo] ile gelen cihaz aynı modelle [depoId]'ye girer.
  /// - onarilamadi: [hurda] ise hurdaya ayrılır, değilse "değişim gerekli"
  ///   olarak depoda bekletilir (yeni servis dosyası açılır).
  Future<void> servisSonucu({
    required String cihazId,
    required String sonuc,
    required DateTime donusTarihi,
    String? aciklama,
    String? depoId,
    String? yeniSeriNo,
    bool hurda = true,
    required String kullaniciId,
  }) async {
    final db = await _database;
    await db.transaction((txn) async {
      final c = await _cihazTxn(txn, cihazId);
      if (!c.arizali) throw StateError('${c.seriNo} serviste görünmüyor');
      final simdi = DateTime.now();
      final sonra = simdi.add(const Duration(milliseconds: 1));
      final kayit = await _acikServisTxn(txn, cihazId);
      final aciklamaTemiz = _bosIseNull(aciklama);
      final eskiDepo = c.depoId;
      final gonderim = kayit?.gonderimTarihi;
      final sureEki = gonderim == null
          ? ''
          : 'Süre: ${sureMetni(donusTarihi.difference(gonderim))}';
      String notMetni([String? on]) => [
            if (on != null) on,
            if (aciklamaTemiz != null) aciklamaTemiz,
            if (sureEki.isNotEmpty) sureEki,
          ].join(' · ');

      Future<void> kaydiKapat(String kapanis, {String? yeniSeri}) async {
        if (kayit == null) return;
        await _servisGuncelleTxn(
            txn,
            kayit.id,
            {
              'donus_tarihi': donusTarihi.millisecondsSinceEpoch,
              'sonuc': sonuc,
              'sonuc_aciklama': aciklamaTemiz,
              if (yeniSeri != null) 'yeni_seri_no': yeniSeri,
              'kapanis': kapanis,
              'kapanis_tarihi': simdi.millisecondsSinceEpoch,
            },
            simdi);
      }

      switch (sonuc) {
        case 'onarildi':
          final hedef = depoId ?? eskiDepo;
          if (hedef == null) throw StateError('Depo seçin');
          await _cihazGuncelleTxn(
              txn,
              cihazId,
              {
                'servis_durumu': null,
                'depo_id': hedef,
                'durum': CihazDurumu.depoda.name,
              },
              simdi);
          await _servisHareketiTxn(txn,
              cihaz: c,
              adim: 'Onarıldı, depoya eklendi',
              depoId: eskiDepo,
              hedefDepoId: hedef,
              miktar: hedef != eskiDepo ? 1 : 0,
              kullaniciId: kullaniciId,
              zaman: simdi,
              not_: notMetni());
          await kaydiKapat('depoya');
          break;

        case 'degistirildi':
          final seri = _normSeri(yeniSeriNo ?? '');
          if (seri.isEmpty) {
            throw StateError('Yeni cihazın seri numarasını girin');
          }
          if (seri == c.seriNo) {
            throw StateError('Yeni seri no eskisiyle aynı olamaz');
          }
          final hedef = depoId ?? eskiDepo;
          if (hedef == null) throw StateError('Depo seçin');
          await _cihazGuncelleTxn(
              txn,
              cihazId,
              {
                'servis_durumu': ServisDurumu.degistirildi.name,
                'depo_id': null,
                'durum': CihazDurumu.cikti.name,
              },
              simdi);
          await _servisHareketiTxn(txn,
              cihaz: c,
              adim: 'Değiştirildi, firmaya teslim',
              depoId: eskiDepo,
              miktar: 1,
              kullaniciId: kullaniciId,
              zaman: simdi,
              not_: notMetni('Yeni SN: $seri'));
          // Yeni cihaz eskinin alım / garanti bilgileriyle girer.
          await _girisTxn(txn,
              urunId: c.urunId,
              depoId: hedef,
              seri: seri,
              kullaniciId: kullaniciId,
              alim: AlimBilgisi.cihazdan(c),
              not_: 'Değişim (eski SN: ${c.seriNo})',
              zaman: sonra);
          await kaydiKapat('degisim', yeniSeri: seri);
          break;

        case 'onarilamadi':
          await _servisHareketiTxn(txn,
              cihaz: c,
              adim: 'Servisten döndü: onarılamadı',
              kullaniciId: kullaniciId,
              zaman: simdi,
              not_: notMetni());
          if (hurda) {
            // Hurda için cihaz "servisten dönmüş" sayılır.
            await _cihazGuncelleTxn(txn, cihazId,
                {'servis_durumu': ServisDurumu.degisimGerekli.name}, simdi);
            await kaydiKapat('hurda');
            await _hurdaTxn(txn,
                cihazId: cihazId,
                sebep: 'Onarılamaz arıza',
                not_: aciklamaTemiz,
                kullaniciId: kullaniciId,
                zaman: sonra);
          } else {
            await kaydiKapat('degisim_bekliyor');
            await _cihazGuncelleTxn(
                txn, cihazId, {'servis_durumu': null}, simdi);
            await _arizaKaydiAcTxn(txn,
                cihazId: cihazId,
                karar: 'degisim',
                aciklama: 'Onarılamadı'
                    '${aciklamaTemiz == null ? '' : ': $aciklamaTemiz'}',
                kullaniciId: kullaniciId,
                zaman: sonra);
          }
          break;

        default:
          throw ArgumentError('Bilinmeyen sonuç: $sonuc');
      }
    });
    _notify();
  }

  /// Depodaki (sağlam veya arızalı) cihazı hurdaya ayırır.
  Future<void> hurdayaAyir({
    required String cihazId,
    required String sebep,
    String? not_,
    required String kullaniciId,
  }) async {
    final db = await _database;
    await db.transaction((txn) => _hurdaTxn(txn,
        cihazId: cihazId,
        sebep: sebep,
        not_: not_,
        kullaniciId: kullaniciId,
        zaman: DateTime.now()));
    _notify();
  }

  /// Cihazın tüm servis dosyaları (en yeni üstte).
  Future<List<ServisKaydi>> cihazServisKayitlari(String cihazId) async {
    final db = await _database;
    final rows = await db.query('servis_kayitlari',
        where: 'cihaz_id = ? AND deleted = 0',
        whereArgs: [cihazId],
        orderBy: 'acilis_tarihi DESC');
    return rows.map(ServisKaydi.fromMap).toList();
  }

  Stream<List<ServisKaydi>> cihazServisKayitlariStream(String cihazId) =>
      _watch(() => cihazServisKayitlari(cihazId));

  /// Rapor: tüm servis dosyaları, cihaz ve ürün bilgisiyle.
  Future<List<Map<String, Object?>>> servisRaporu({
    DateTime? baslangic,
    DateTime? bitis,
  }) async {
    final db = await _database;
    final kosullar = <String>['s.deleted = 0'];
    final args = <Object?>[];
    if (baslangic != null) {
      kosullar.add('s.acilis_tarihi >= ?');
      args.add(baslangic.millisecondsSinceEpoch);
    }
    if (bitis != null) {
      kosullar.add('s.acilis_tarihi <= ?');
      args.add(bitis.millisecondsSinceEpoch);
    }
    return db.rawQuery(
        'SELECT s.*, c.seri_no AS seri_no, c.servis_durumu AS servis_durumu, '
        'c.garanti_bitis AS garanti_bitis, u.ad AS urun_adi, d.ad AS depo_adi '
        'FROM servis_kayitlari s '
        'LEFT JOIN cihazlar c ON c.id = s.cihaz_id '
        'LEFT JOIN urunler u ON u.id = s.urun_id '
        'LEFT JOIN depolar d ON d.id = c.depo_id '
        'WHERE ${kosullar.join(' AND ')} '
        'ORDER BY s.acilis_tarihi DESC',
        args);
  }

  /// Rapor: hurdaya ayrılan cihazlar.
  Future<List<Map<String, Object?>>> hurdaRaporu({
    DateTime? baslangic,
    DateTime? bitis,
  }) async {
    final db = await _database;
    final kosullar = <String>['sh.deleted = 0', "sh.tip = 'hurda'"];
    final args = <Object?>[];
    if (baslangic != null) {
      kosullar.add('sh.tarih >= ?');
      args.add(baslangic.millisecondsSinceEpoch);
    }
    if (bitis != null) {
      kosullar.add('sh.tarih <= ?');
      args.add(bitis.millisecondsSinceEpoch);
    }
    return db.rawQuery(
        'SELECT sh.tarih AS tarih, sh.sebep AS sebep, sh.not_ AS not_, '
        'c.seri_no AS seri_no, u.ad AS urun_adi, d.ad AS depo_adi, '
        'c.alim_tarihi AS alim_tarihi, c.firma AS firma, c.ihale AS ihale, '
        'k.ad AS kullanici '
        'FROM stok_hareketleri sh '
        'LEFT JOIN cihazlar c ON c.id = sh.cihaz_id '
        'LEFT JOIN urunler u ON u.id = sh.urun_id '
        'LEFT JOIN depolar d ON d.id = sh.depo_id '
        'LEFT JOIN kullanicilar k ON k.id = sh.kullanici_id '
        'WHERE ${kosullar.join(' AND ')} '
        'ORDER BY sh.tarih DESC',
        args);
  }

  /// Daha önce girilmiş servis / alım firmaları (öneri için).
  Future<List<String>> oncekiServisFirmalari() async {
    final db = await _database;
    final rows = await db.rawQuery(
        "SELECT firma AS v FROM servis_kayitlari "
        "WHERE firma IS NOT NULL AND firma <> '' AND deleted = 0 "
        "UNION SELECT firma AS v FROM cihazlar "
        "WHERE firma IS NOT NULL AND firma <> '' AND deleted = 0 "
        'ORDER BY 1 COLLATE NOCASE LIMIT 300');
    return [for (final r in rows) r['v'] as String];
  }

  /// Cihazın alım / garanti bilgilerini değiştirir (boş bırakılanlar silinir).
  Future<void> cihazAlimGuncelle(String cihazId, AlimBilgisi alim) async {
    final db = await _database;
    await db.update(
      'cihazlar',
      {
        ...alim.kolonlar(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [cihazId],
    );
    _notify();
  }

  /// Konumu olan ama il/ilçe/mahallesi bulunmamış kullanım kayıtları.
  Future<List<Map<String, Object?>>> adresiEksikKullanimlar(
      {int limit = 15}) async {
    final db = await _database;
    return db.rawQuery(
        'SELECT id, enlem, boylam, konum_hassasiyet, il, ilce, mahalle, '
        'kullanim_yeri '
        'FROM kullanim_kayitlari '
        'WHERE deleted = 0 AND enlem IS NOT NULL AND boylam IS NOT NULL '
        "AND ((mahalle IS NULL AND ilce IS NULL) "
        "     OR kullanim_yeri IS NULL OR kullanim_yeri = '') "
        'ORDER BY updated_at DESC LIMIT ?',
        [limit]);
  }

  /// Konumun en fazla [metre] yakınında daha önce yazılmış kullanım yerleri
  /// (yakından uzağa, tekrarsız). Yalnız hassasiyeti en fazla [metre] olan
  /// eski konumlar sayılır. İnternetsiz çalışır.
  Future<List<String>> yakindakiKullanimYerleri(double enlem, double boylam,
      {double metre = 15}) async {
    final db = await _database;
    final dEnlem = metre / 111320.0;
    final dBoylam =
        metre / (111320.0 * math.max(0.01, math.cos(enlem * math.pi / 180)));
    final rows = await db.rawQuery(
        "SELECT kullanim_yeri, enlem, boylam FROM kullanim_kayitlari "
        "WHERE deleted = 0 AND kullanim_yeri IS NOT NULL AND kullanim_yeri <> '' "
        'AND konum_hassasiyet IS NOT NULL AND konum_hassasiyet <= ? '
        'AND enlem BETWEEN ? AND ? AND boylam BETWEEN ? AND ?',
        [metre, enlem - dEnlem, enlem + dEnlem, boylam - dBoylam,
         boylam + dBoylam]);
    final mesafeler = <String, double>{};
    for (final r in rows) {
      final ad = (r['kullanim_yeri'] as String).trim();
      final m = mesafeMetre(enlem, boylam, (r['enlem'] as num).toDouble(),
          (r['boylam'] as num).toDouble());
      if (m > metre) continue;
      final onceki = mesafeler[ad];
      if (onceki == null || m < onceki) mesafeler[ad] = m;
    }
    final adlar = mesafeler.keys.toList()
      ..sort((a, b) => mesafeler[a]!.compareTo(mesafeler[b]!));
    return adlar;
  }

  /// Bir montaj kaydında boş kalan kullanım yerini doldurur (internetsiz
  /// kaydedilmişse sonradan); cihazın kartındaki yer de boşsa yazılır.
  Future<void> kullanimYeriTamamla(String kayitId, String yer) async {
    yer = trBuyuk(yer); // 1.29.1: otomatik dolan her şey büyük harf
    final db = await _database;
    final simdi = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final n = await txn.rawUpdate(
          'UPDATE kullanim_kayitlari SET kullanim_yeri = ?, updated_at = ?, '
          "dirty = 1 WHERE id = ? AND (kullanim_yeri IS NULL OR kullanim_yeri = '')",
          [yer, simdi, kayitId]);
      if (n == 0) return;
      await txn.rawUpdate(
          'UPDATE cihazlar SET kullanim_yeri = ?, updated_at = ?, dirty = 1 '
          "WHERE (kullanim_yeri IS NULL OR kullanim_yeri = '') "
          "AND durum = 'kullanimda' AND id = (SELECT sh.cihaz_id FROM "
          'stok_hareketleri sh JOIN kullanim_kayitlari kk ON '
          'kk.stok_hareket_id = sh.id WHERE kk.id = ?)',
          [yer, simdi, kayitId]);
    });
    _notify();
  }

  /// Arka planda bulunan adresi yazar; elle girilmiş alanlara dokunmaz.
  /// Adres bulunamadıysa boş metin yazılır (tekrar denenmez).
  Future<void> kullanimAdresiTamamla(
      String id, String? il, String? ilce, String? mahalle) async {
    final db = await _database;
    await db.rawUpdate(
        "UPDATE kullanim_kayitlari SET "
        "il = COALESCE(NULLIF(il, ''), ?), "
        "ilce = COALESCE(NULLIF(ilce, ''), ?), "
        "mahalle = COALESCE(NULLIF(mahalle, ''), ?), "
        'updated_at = ?, dirty = 1 WHERE id = ?',
        [il ?? '', ilce ?? '', mahalle ?? '',
         DateTime.now().millisecondsSinceEpoch, id]);
    _notify();
  }

  /// Sahada (kullanımda) olan cihazların son kurulum noktası ve bölgesi.
  Future<List<Map<String, Object?>>> bolgeRaporu() async {
    final db = await _database;
    return db.rawQuery('''
      SELECT c.seri_no AS seri_no, u.ad AS urun_adi, kk.il AS il,
             kk.ilce AS ilce, kk.mahalle AS mahalle,
             kk.kullanim_yeri AS kullanim_yeri, kk.enlem AS enlem,
             kk.boylam AS boylam, sh.tarih AS tarih
      FROM cihazlar c
      JOIN urunler u ON u.id = c.urun_id
      JOIN stok_hareketleri sh ON sh.cihaz_id = c.id AND sh.deleted = 0
      JOIN kullanim_kayitlari kk ON kk.stok_hareket_id = sh.id
      WHERE c.deleted = 0 AND c.durum = 'kullanimda'
        AND sh.tarih = (SELECT MAX(sh2.tarih) FROM stok_hareketleri sh2
                        JOIN kullanim_kayitlari kk2
                          ON kk2.stok_hareket_id = sh2.id
                        WHERE sh2.cihaz_id = c.id AND sh2.deleted = 0)
      ORDER BY kk.il COLLATE NOCASE, kk.ilce COLLATE NOCASE,
               kk.mahalle COLLATE NOCASE, u.ad COLLATE NOCASE
    ''');
  }

  /// Daha önce girilmiş firma veya ihale adları (yazarken öneri için).
  Future<List<String>> oncekiAlimDegerleri(String kolon) async {
    if (kolon != 'firma' && kolon != 'ihale') return [];
    final db = await _database;
    final rows = await db.rawQuery(
        "SELECT DISTINCT $kolon AS v FROM cihazlar "
        "WHERE $kolon IS NOT NULL AND $kolon <> '' AND deleted = 0 "
        'ORDER BY $kolon COLLATE NOCASE LIMIT 300');
    return [for (final r in rows) r['v'] as String];
  }

  // ---------------------------------------------------------------------
  // Silme (yanlış kayıtlar için). Kayıt gizlenir; silme işlemi sebebiyle
  // birlikte hareket geçmişine yazılır. Hareket kayıtları hiçbir zaman
  // silinmez.
  // ---------------------------------------------------------------------

  Future<void> cihazSil(
    String cihazId, {
    required String sebep,
    String? not_,
    required String kullaniciId,
  }) async {
    final db = await _database;
    await db.transaction((txn) async {
      final rows = await txn.query('cihazlar',
          where: 'id = ?', whereArgs: [cihazId], limit: 1);
      if (rows.isEmpty) throw StateError('Cihaz bulunamadı');
      final c = Cihaz.fromMap(rows.first);
      if (c.deleted) throw StateError('${c.seriNo} zaten silinmiş');
      final simdi = DateTime.now();
      await txn.update(
        'cihazlar',
        {
          'deleted': 1,
          'updated_at': simdi.millisecondsSinceEpoch,
          'dirty': 1,
        },
        where: 'id = ?',
        whereArgs: [cihazId],
      );
      await txn.insert(
        'stok_hareketleri',
        StokHareketi(
          id: _uuid.v4(),
          urunId: c.urunId,
          depoId: c.depoId ?? '',
          tip: HareketTipi.silme,
          miktar: 1,
          kullaniciId: kullaniciId,
          tarih: simdi,
          not_: not_,
          cihazId: cihazId,
          sebep: sebep,
          updatedAt: simdi,
        ).toMap(),
      );
    });
    _notify();
  }

  /// Ürün (model) silinir. Depoda, araçta veya sahada cihazı varsa
  /// silinmez; önce o cihazlar silinmeli veya çıkışı yapılmalı.
  Future<void> urunSil(
    String urunId, {
    required String sebep,
    String? not_,
    required String kullaniciId,
  }) async {
    final db = await _database;
    await db.transaction((txn) async {
      final aktif = Sqflite.firstIntValue(await txn.rawQuery(
              "SELECT COUNT(*) FROM cihazlar WHERE urun_id = ? AND deleted = 0 "
              "AND durum IN ('depoda', 'kullanimda')",
              [urunId])) ??
          0;
      if (aktif > 0) {
        throw StateError('Bu üründen $aktif cihaz depoda / araçta / montajlı '
            'görünüyor. Önce o cihazları silin veya çıkışını yapın.');
      }
      final simdi = DateTime.now();
      await txn.update(
        'urunler',
        {
          'deleted': 1,
          'updated_at': simdi.millisecondsSinceEpoch,
          'dirty': 1,
        },
        where: 'id = ?',
        whereArgs: [urunId],
      );
      await txn.insert(
        'stok_hareketleri',
        StokHareketi(
          id: _uuid.v4(),
          urunId: urunId,
          depoId: '',
          tip: HareketTipi.silme,
          miktar: 0,
          kullaniciId: kullaniciId,
          tarih: simdi,
          not_: not_,
          sebep: sebep,
          updatedAt: simdi,
        ).toMap(),
      );
    });
    _notify();
  }

  /// Okutulan seri numarasının cihaz bilgisini (model, depo, araç) getirir.
  /// Kurum etiketi (karekod veya kod) okutulduysa etiketin cihazı döner.
  Future<CihazBilgi?> seriNoIleCihazBilgi(String seriNo) async {
    final db = await _database;
    final rows = await db.rawQuery(
        '$_cihazBilgiSelect WHERE c.seri_no = ? COLLATE NOCASE AND c.deleted = 0 LIMIT 1',
        [_normSeri(seriNo)]);
    if (rows.isNotEmpty) return CihazBilgi.fromRow(rows.first);
    final okuma = EtiketKodu.coz(seriNo);
    if (okuma == null) return null;
    final e = await db.rawQuery(
        '$_cihazBilgiSelect WHERE c.deleted = 0 AND c.id = '
        '(SELECT cihaz_id FROM etiketler WHERE kod = ? AND deleted = 0 LIMIT 1) '
        'LIMIT 1',
        [okuma.kod]);
    return e.isEmpty ? null : CihazBilgi.fromRow(e.first);
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
        'a.plaka LIKE ? OR c.kullanim_yeri LIKE ? OR e.kod LIKE ? OR '
        "(c.durum = 'kullanimda' AND EXISTS (SELECT 1 FROM kullanim_kayitlari kk "
        'JOIN stok_hareketleri sh ON sh.id = kk.stok_hareket_id '
        'WHERE sh.cihaz_id = c.id AND (kk.mahalle LIKE ? OR kk.ilce LIKE ? '
        'OR kk.il LIKE ?)))) '
        'ORDER BY (c.seri_no = ?) DESC, u.ad, c.seri_no LIMIT ?',
        [like, like, like, like, like, like, like, like, like, _normSeri(q), limit]);
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
        AND servis_durumu IS NULL
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
    String? sebep,
    double? enlem,
    double? boylam,
    double? konumHassasiyet,
    String? il,
    String? ilce,
    String? mahalle,
    String? tutanak,
  }) async {
    final rows = await txn.query('cihazlar',
        where: 'id = ?', whereArgs: [cihazId], limit: 1);
    if (rows.isEmpty) throw StateError('Cihaz bulunamadı');
    final c = Cihaz.fromMap(rows.first);

    if (c.durum != CihazDurumu.depoda || c.depoId == null) {
      throw StateError('${c.seriNo} şu an depoda değil, bu işlem yapılamaz');
    }
    if (c.arizali) {
      throw StateError('${c.seriNo} ${c.servisDurumu!.kisa.toLowerCase()}: '
          'transfer, araca yükleme, montaj / kullanım ve çıkış yapılamaz. '
          'Önce cihaz kartından servis işlemini tamamlayın.');
    }
    // Kurum etiketi engeli (ayarlardan açılırsa): doğrulanmamış etiketli
    // cihaz transfer edilemez, kullanıma verilemez, sahada kullanılamaz.
    if (tip == HareketTipi.transfer || tip == HareketTipi.kullanim) {
      final engel = await _etiketEngeliTxn(txn, c);
      if (engel != null) throw StateError(engel);
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
      case HareketTipi.silme:
      case HareketTipi.servis:
      case HareketTipi.hurda:
        throw ArgumentError('Bu işlem için ilgili özel metodu kullanın');
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
        sebep: sebep,
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
          enlem: enlem,
          boylam: boylam,
          konumHassasiyet: konumHassasiyet,
          il: il,
          ilce: ilce,
          mahalle: mahalle,
          tutanak: tutanak,
          tutanakTarihi: tutanak == null ? null : simdi,
          tutanakKullaniciId: tutanak == null ? null : kullaniciId,
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
    String? sebep,
    double? enlem,
    double? boylam,
    double? konumHassasiyet,
    String? il,
    String? ilce,
    String? mahalle,
    String? arizaKarari, // iadede "Arıza" seçildiyse: tamir | degisim
    String? tutanak, // montajda: alindi | alinacak | kurum_ici
    // Montajda kullanılan malzemeler (urunId -> miktar), [malzemeDepoId]
    // deposundan / aracından düşülür.
    Map<String, int> malzemeler = const {},
    String? malzemeDepoId,
  }) async {
    if (tip == HareketTipi.girisi ||
        tip == HareketTipi.silme ||
        tip == HareketTipi.servis ||
        tip == HareketTipi.hurda) {
      throw ArgumentError('Bu işlem için ilgili özel metodu kullanın');
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
          sebep: sebep,
          enlem: enlem,
          boylam: boylam,
          konumHassasiyet: konumHassasiyet,
          il: il,
          ilce: ilce,
          mahalle: mahalle,
          tutanak: tutanak,
        );
        if (arizaKarari != null) {
          await _arizaKaydiAcTxn(txn,
              cihazId: id,
              karar: arizaKarari,
              aciklama: not_,
              kullaniciId: kullaniciId,
              zaman: DateTime.now());
        }
      }
      final kullanilan = {
        for (final e in malzemeler.entries)
          if (e.value > 0) e.key: e.value
      };
      if (kullanilan.isNotEmpty) {
        if (malzemeDepoId == null) {
          throw StateError('Malzemenin düşüleceği depo / araç belli değil');
        }
        await _malzemeHareketiTxn(
          txn,
          islem: MalzemeIslemi.kullanim,
          kaynakDepoId: malzemeDepoId,
          miktarlar: kullanilan,
          kullaniciId: kullaniciId,
          kullanimYeri: kullanimYeri,
          not_: not_,
          enlem: enlem,
          boylam: boylam,
          konumHassasiyet: konumHassasiyet,
          il: il,
          ilce: ilce,
          mahalle: mahalle,
        );
      }
    });

    _notify();
  }

  // ---------------------------------------------------------------------
  // Bildirimler (yalnızca bu telefonda tutulur, sunucuya gönderilmez)
  // ---------------------------------------------------------------------

  Future<void> bildirimEkle({
    required String tur,
    required String baslik,
    required String govde,
    String? hedef,
  }) async {
    final db = await _database;
    await db.insert('bildirimler', {
      'tur': tur,
      'baslik': baslik,
      'govde': govde,
      'hedef': hedef,
      'tarih': DateTime.now().millisecondsSinceEpoch,
      'okundu': 0,
    });
    // Çok eskiyen bildirimler temizlenir (son 300 kalır).
    await db.rawDelete(
        'DELETE FROM bildirimler WHERE id NOT IN '
        '(SELECT id FROM bildirimler ORDER BY id DESC LIMIT 300)');
    _notify();
  }

  Future<List<Map<String, Object?>>> bildirimListesi() async {
    final db = await _database;
    return db.query('bildirimler', orderBy: 'id DESC', limit: 300);
  }

  Stream<List<Map<String, Object?>>> bildirimListesiStream() =>
      _watch(bildirimListesi);

  Future<int> okunmamisBildirimSayisi() async {
    final db = await _database;
    return Sqflite.firstIntValue(await db
            .rawQuery('SELECT COUNT(*) FROM bildirimler WHERE okundu = 0')) ??
        0;
  }

  Stream<int> okunmamisBildirimSayisiStream() =>
      _watch(okunmamisBildirimSayisi);

  Future<void> bildirimleriOkunduYap() async {
    final db = await _database;
    final n = await db.update('bildirimler', {'okundu': 1},
        where: 'okundu = 0');
    if (n > 0) _notify();
  }

  Future<void> bildirimleriTemizle() async {
    final db = await _database;
    await db.delete('bildirimler');
    _notify();
  }

  /// Bir olay için daha önce bildirim yapıldı mı (aynı olay iki kez gelmesin).
  Future<bool> bildirimGoruldu(String anahtar) async {
    final db = await _database;
    final r = await db.query('bildirim_gorulen',
        columns: ['anahtar'], where: 'anahtar = ?', whereArgs: [anahtar],
        limit: 1);
    return r.isNotEmpty;
  }

  Future<int?> bildirimGorulmeZamani(String anahtar) async {
    final db = await _database;
    final r = await db.query('bildirim_gorulen',
        columns: ['tarih'], where: 'anahtar = ?', whereArgs: [anahtar],
        limit: 1);
    return r.isEmpty ? null : (r.first['tarih'] as num).toInt();
  }

  Future<void> bildirimGorulduIsaretle(String anahtar, [int? tarih]) async {
    final db = await _database;
    await db.insert(
        'bildirim_gorulen',
        {
          'anahtar': anahtar,
          'tarih': tarih ?? DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> bildirimGorulenSil(String anahtarOn) async {
    final db = await _database;
    await db.delete('bildirim_gorulen',
        where: 'anahtar LIKE ?', whereArgs: ['$anahtarOn%']);
  }

  /// Ön ekle başlayan "görüldü" anahtarları (ör. kritik:...).
  Future<List<String>> bildirimGorulenler(String anahtarOn) async {
    final db = await _database;
    final r = await db.query('bildirim_gorulen',
        columns: ['anahtar'], where: 'anahtar LIKE ?',
        whereArgs: ['$anahtarOn%']);
    return [for (final x in r) x['anahtar'] as String];
  }

  Future<void> bildirimGorulenEskileriSil(int oncesi) async {
    final db = await _database;
    await db.delete('bildirim_gorulen',
        where: "(anahtar LIKE 'h:%' OR anahtar LIKE 'e:%') AND tarih < ?",
        whereArgs: [oncesi]);
  }

  /// Bildirim motoru için son hareketler (cihaz, ürün ve depo adlarıyla).
  Future<List<Map<String, Object?>>> bildirimHareketleri(int sonrasi) async {
    final db = await _database;
    return db.rawQuery('''
      SELECT sh.id AS id, sh.tip AS tip, sh.tarih AS tarih, sh.sebep AS sebep,
             sh.not_ AS not_, sh.kullanici_id AS kullanici_id,
             sh.depo_id AS depo_id, sh.hedef_depo_id AS hedef_depo_id,
             c.seri_no AS seri_no, u.ad AS urun_adi, d.ad AS depo_adi,
             hd.ad AS hedef_adi, hd.tur AS hedef_tur, k.ad AS kullanici,
             sh.cihaz_id AS cihaz_id, sh.miktar AS miktar, u.birim AS birim,
             u.seri_takipli AS seri_takipli
      FROM stok_hareketleri sh
      LEFT JOIN cihazlar c ON c.id = sh.cihaz_id
      LEFT JOIN urunler u ON u.id = sh.urun_id
      LEFT JOIN depolar d ON d.id = sh.depo_id
      LEFT JOIN depolar hd ON hd.id = sh.hedef_depo_id
      LEFT JOIN kullanicilar k ON k.id = sh.kullanici_id
      WHERE sh.deleted = 0 AND sh.tarih > ?
      ORDER BY sh.tarih
    ''', [sonrasi]);
  }

  /// Açık servis dosyaları (cihaz ve ürün adıyla).
  Future<List<Map<String, Object?>>> acikServisDosyalari() async {
    final db = await _database;
    return db.rawQuery(
        'SELECT s.id AS id, s.acilis_tarihi AS acilis_tarihi, '
        's.gonderim_tarihi AS gonderim_tarihi, s.firma AS firma, '
        's.onarim_yeri AS onarim_yeri, c.seri_no AS seri_no, u.ad AS urun_adi '
        'FROM servis_kayitlari s '
        'LEFT JOIN cihazlar c ON c.id = s.cihaz_id '
        'LEFT JOIN urunler u ON u.id = s.urun_id '
        'WHERE s.deleted = 0 AND s.kapanis IS NULL '
        'ORDER BY s.acilis_tarihi');
  }

  /// Garantisi [gun] gün içinde bitecek, kullanımdaki / stoktaki cihazlar.
  Future<List<Map<String, Object?>>> garantisiBitecekler(int gun) async {
    final db = await _database;
    final simdi = DateTime.now();
    final bugun = DateTime(simdi.year, simdi.month, simdi.day);
    return db.rawQuery(
        "SELECT c.id AS id, c.seri_no AS seri_no, c.garanti_bitis AS garanti_bitis, "
        'u.ad AS urun_adi FROM cihazlar c JOIN urunler u ON u.id = c.urun_id '
        "WHERE c.deleted = 0 AND c.durum <> 'cikti' "
        'AND c.garanti_bitis IS NOT NULL AND c.garanti_bitis >= ? '
        'AND c.garanti_bitis <= ? ORDER BY c.garanti_bitis',
        [
          bugun.millisecondsSinceEpoch,
          bugun.add(Duration(days: gun + 1)).millisecondsSinceEpoch,
        ]);
  }

  /// Sunucuya gönderilmeyi bekleyen en eski kaydın zamanı (yoksa null).
  Future<int?> enEskiBekleyenKayit() async {
    final db = await _database;
    int? enEski;
    for (final tablo in senkronKolonlari.keys) {
      final v = Sqflite.firstIntValue(await db
          .rawQuery('SELECT MIN(updated_at) FROM $tablo WHERE dirty = 1'));
      if (v != null && (enEski == null || v < enEski)) enEski = v;
    }
    return enEski;
  }

  /// Günlük özet için: [bas]–[bit] arasındaki hareket sayıları (türe göre).
  Future<Map<String, int>> hareketSayilari(DateTime bas, DateTime bit) async {
    final db = await _database;
    final r = await db.rawQuery(
        'SELECT tip, COUNT(*) AS n FROM stok_hareketleri '
        'WHERE deleted = 0 AND cihaz_id IS NOT NULL AND tarih >= ? AND tarih < ? '
        'GROUP BY tip',
        [bas.millisecondsSinceEpoch, bit.millisecondsSinceEpoch]);
    return {for (final x in r) x['tip'] as String: (x['n'] as num).toInt()};
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
      'seri_takipli', 'kutu_icerigi', 'birlesti_id', 'updated_at', 'deleted'
    ],
    'araclar': ['id', 'plaka', 'ad', 'aciklama', 'updated_at', 'deleted'],
    'kullanicilar': ['id', 'ad', 'email', 'rol', 'updated_at', 'deleted'],
    'cihazlar': [
      'id', 'urun_id', 'seri_no', 'depo_id', 'durum', 'arac_id',
      'kullanim_yeri', 'alim_tarihi', 'firma', 'ihale', 'garanti_bitis',
      'servis_durumu', 'updated_at', 'deleted'
    ],
    'stok_hareketleri': [
      'id', 'urun_id', 'depo_id', 'hedef_depo_id', 'tip', 'miktar',
      'kullanici_id', 'tarih', 'not_', 'cihaz_id', 'sebep', 'updated_at',
      'deleted'
    ],
    'kullanim_kayitlari': [
      'id', 'stok_hareket_id', 'arac_id', 'kullanim_yeri', 'not_',
      'enlem', 'boylam', 'konum_hassasiyet', 'il', 'ilce', 'mahalle',
      'tutanak', 'tutanak_tarihi', 'tutanak_kullanici_id',
      'updated_at', 'deleted'
    ],
    'servis_kayitlari': [
      'id', 'cihaz_id', 'urun_id', 'acilis_tarihi', 'ariza_aciklama', 'karar',
      'onarim_yeri', 'firma', 'gonderim_tarihi', 'donus_tarihi', 'sonuc',
      'sonuc_aciklama', 'yeni_seri_no', 'kapanis', 'kapanis_tarihi',
      'kullanici_id', 'updated_at', 'deleted'
    ],
    // 1.22.0: kurum etiketi
    'kurum_kodlari': ['id', 'kod', 'ad', 'aktif', 'sira', 'updated_at', 'deleted'],
    'kurum_ayarlari': ['id', 'deger', 'updated_at', 'deleted'],
    'etiketler': [
      'id', 'cihaz_id', 'kod', 'kurum_kodu_id', 'surum', 'durum', 'seri_nosuz',
      'olusturma', 'kullanici_id', 'updated_at', 'deleted'
    ],
    'etiket_hareketleri': [
      'id', 'etiket_id', 'cihaz_id', 'islem', 'surum', 'aciklama',
      'kullanici_id', 'tarih', 'updated_at', 'deleted'
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
        // Sunucuda henüz olmayan (SQL'i çalıştırılmamış) sütun yereldeki
        // değeri silmesin.
        final map = <String, Object?>{
          for (final k in kolonlar)
            if (r.containsKey(k)) k: r[k]
        };
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
          if (tablo == 'etiketler') {
            final ayniKod = await txn.query('etiketler',
                columns: ['id'],
                where: 'kod = ?',
                whereArgs: [r['kod']],
                limit: 1);
            if (ayniKod.isNotEmpty) {
              cakismalar.add('etiket ${r['kod']}');
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


/// İki koordinat arası yaklaşık mesafe (metre, haversine).
double mesafeMetre(double e1, double b1, double e2, double b2) {
  const r = 6371000.0;
  final de = (e2 - e1) * math.pi / 180;
  final db = (b2 - b1) * math.pi / 180;
  final a = math.sin(de / 2) * math.sin(de / 2) +
      math.cos(e1 * math.pi / 180) *
          math.cos(e2 * math.pi / 180) *
          math.sin(db / 2) *
          math.sin(db / 2);
  return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}
