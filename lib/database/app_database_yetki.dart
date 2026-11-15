part of 'app_database.dart';

/// 1.36.0: roller, yetki tablosu ve bildirim alıcıları (bkz. services/yetki.dart).
///
/// yetkiler          : rol:yetki → izin (yöneticinin düzenlediği tablo)
/// bildirim_alicilari: bildirim türü → roller / kişiler (virgülle)
/// İkisi de senkronlanır; sunucuda yalnız kullanıcı yönetimi yetkisiyle
/// değişir. Kullanıcıların rol / aktiflik bilgileri kullanicilar tablosunda.
const _yetkiTabloSql = '''
CREATE TABLE IF NOT EXISTS yetkiler (
  id TEXT PRIMARY KEY,
  rol TEXT NOT NULL,
  yetki TEXT NOT NULL,
  izin INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  dirty INTEGER NOT NULL DEFAULT 1,
  deleted INTEGER NOT NULL DEFAULT 0
)
''';

const _bildirimAliciTabloSql = '''
CREATE TABLE IF NOT EXISTS bildirim_alicilari (
  id TEXT PRIMARY KEY,
  roller TEXT,
  kisiler TEXT,
  updated_at INTEGER NOT NULL,
  dirty INTEGER NOT NULL DEFAULT 1,
  deleted INTEGER NOT NULL DEFAULT 0
)
''';

/// Bir bildirim türünün alıcıları (merkezi seçim). [roller] / [kisiler]
/// boşsa kimse almaz.
class BildirimAlici {
  const BildirimAlici({required this.tur, this.roller = const {}, this.kisiler = const {}});
  final String tur;
  final Set<KullaniciRol> roller;
  final Set<String> kisiler;

  bool aliciMi(KullaniciRol? rol, String? kisiId) =>
      (rol != null && roller.contains(rol)) ||
      (kisiId != null && kisiler.contains(kisiId));
}

extension YetkiVeritabani on AppDatabase {
  /// rol:yetki → izin. Boşsa sunucuda tablo yok (eski düzen) ya da henüz
  /// senkronlanmadı.
  Future<Map<String, bool>> yetkiTablosu() async {
    final db = await _database;
    final r = await db.query('yetkiler',
        columns: ['id', 'izin'], where: 'deleted = 0');
    return {
      for (final m in r) m['id'] as String: ((m['izin'] as num?)?.toInt() ?? 0) == 1
    };
  }

  /// Arka plan işleri için: [kullaniciId] bu yetkiye sahip mi? (Yetki
  /// tablosu yoksa eski düzen: evet.)
  Future<Yetkilerim> yetkilerimiGetir(String? kullaniciId) async {
    final tablo = await yetkiTablosu();
    if (tablo.isEmpty) return const Yetkilerim.eski();
    final ben = kullaniciId == null ? null : await kullaniciGetir(kullaniciId);
    return Yetkilerim(rol: ben?.rol ?? KullaniciRol.gozlemci, tablo: tablo);
  }

  Stream<Map<String, bool>> yetkiTablosuStream() =>
      _watch(() => yetkiTablosu());

  /// Yöneticinin değişikliği: satırlar dirty olur, sunucuya gönderilir.
  Future<void> yetkileriKaydet(Map<(KullaniciRol, Yetki), bool> degisen) async {
    final db = await _database;
    final simdi = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      for (final e in degisen.entries) {
        final (rol, y) = e.key;
        await txn.insert(
          'yetkiler',
          {
            'id': yetkiKimligi(rol, y),
            'rol': rol.name,
            'yetki': y.anahtar,
            'izin': kilitliDeger(rol, y, e.value) ? 1 : 0,
            'updated_at': simdi,
            'dirty': 1,
            'deleted': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    _notify();
  }

  Future<Map<String, BildirimAlici>> bildirimAlicilari() async {
    final db = await _database;
    final r = await db.query('bildirim_alicilari', where: 'deleted = 0');
    Set<String> parca(Object? s) => {
          for (final x in '${s ?? ''}'.split(','))
            if (x.trim().isNotEmpty) x.trim()
        };
    return {
      for (final m in r)
        m['id'] as String: BildirimAlici(
          tur: m['id'] as String,
          roller: {
            for (final ad in parca(m['roller']))
              for (final rol in KullaniciRol.values)
                if (rol.name == ad) rol
          },
          kisiler: parca(m['kisiler']),
        )
    };
  }

  Stream<Map<String, BildirimAlici>> bildirimAlicilariStream() =>
      _watch(() => bildirimAlicilari());

  Future<void> bildirimAlicisiKaydet(BildirimAlici a) async {
    final db = await _database;
    await db.insert(
      'bildirim_alicilari',
      {
        'id': a.tur,
        'roller': [for (final r in a.roller) r.name].join(','),
        'kisiler': a.kisiler.join(','),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'dirty': 1,
        'deleted': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notify();
  }

  /// Kullanıcı listesi (Ayarlar → Kullanıcılar): ada göre.
  Future<List<Kullanici>> kullanicilar() async {
    final db = await _database;
    final r = await db.query('kullanicilar', where: 'deleted = 0');
    final l = [for (final m in r) Kullanici.fromMap(m)];
    l.sort((a, b) => trKarsilastir(a.ad, b.ad));
    return l;
  }

  Stream<List<Kullanici>> kullanicilarStream() => _watch(() => kullanicilar());

  Future<Kullanici?> kullaniciGetir(String id) async {
    final db = await _database;
    final r = await db.query('kullanicilar', where: 'id = ?', whereArgs: [id], limit: 1);
    return r.isEmpty ? null : Kullanici.fromMap(r.first);
  }

  Stream<Kullanici?> kullaniciStream(String id) => _watch(() => kullaniciGetir(id));

  /// Sunucudan (hesap fonksiyonu sonrası ya da girişte) gelen kendi
  /// durumunu yerele yazar; dirty olmaz (sunucunun bilgisidir).
  Future<void> kullaniciDurumuYaz(String id, Map<String, dynamic> d) async {
    final db = await _database;
    final mevcut = await db.query('kullanicilar', where: 'id = ?', whereArgs: [id], limit: 1);
    final m = <String, Object?>{
      if (d['rol'] != null) 'rol': d['rol'],
      if (d['ad'] != null) 'ad': d['ad'],
      'unvan': d['unvan'],
      'aktif': (d['aktif'] as num?)?.toInt() ?? 1,
      'sifre_degistirmeli': (d['sifre_degistirmeli'] as num?)?.toInt() ?? 0,
      'gecici_bitis': (d['gecici_bitis'] as num?)?.toInt(),
    };
    if (mevcut.isEmpty) return; // satır senkronla gelir
    await db.update('kullanicilar', m, where: 'id = ?', whereArgs: [id]);
    _notify();
  }
}
