enum KullaniciRol { admin, depoSorumlusu, sahaKullanicisi }

/// Depo türü: sabit depo ya da seyyar depo olarak çalışan araç.
enum DepoTuru { sabit, arac }

enum HareketTipi { girisi, cikis, transfer, kullanim, iade }

/// Seri numaralı bir cihazın şu anki durumu.
enum CihazDurumu { depoda, kullanimda, cikti }

DateTime _epochToDate(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);
DateTime? _epochOrNull(Object? ms) =>
    ms == null ? null : DateTime.fromMillisecondsSinceEpoch((ms as num).toInt());
int _dateToEpoch(DateTime d) => d.millisecondsSinceEpoch;
bool _intToBool(int i) => i == 1;
int _boolToInt(bool b) => b ? 1 : 0;

class Depo {
  final String id;
  final String ad; // araçlarda plaka
  final String? konum; // araçlarda açıklama (marka, şoför vb.)
  final DepoTuru tur;
  final DateTime updatedAt;
  final bool dirty;
  final bool deleted;

  Depo({
    required this.id,
    required this.ad,
    this.konum,
    this.tur = DepoTuru.sabit,
    required this.updatedAt,
    this.dirty = true,
    this.deleted = false,
  });

  bool get arac => tur == DepoTuru.arac;

  factory Depo.fromMap(Map<String, dynamic> m) => Depo(
        id: m['id'] as String,
        ad: m['ad'] as String,
        konum: m['konum'] as String?,
        tur: m['tur'] == 'arac' ? DepoTuru.arac : DepoTuru.sabit,
        updatedAt: _epochToDate(m['updated_at'] as int),
        dirty: _intToBool(m['dirty'] as int),
        deleted: _intToBool(m['deleted'] as int),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'ad': ad,
        'konum': konum,
        'tur': tur.name,
        'updated_at': _dateToEpoch(updatedAt),
        'dirty': _boolToInt(dirty),
        'deleted': _boolToInt(deleted),
      };
}

class Urun {
  final String id;
  final String ad;
  final String? barkod;
  final String birim;
  final String? kategori;
  final int minStokSeviyesi;
  final bool seriTakipli; // true: her cihaz seri no ile takip edilir
  final DateTime updatedAt;
  final bool dirty;
  final bool deleted;

  Urun({
    required this.id,
    required this.ad,
    this.barkod,
    this.birim = 'adet',
    this.kategori,
    this.minStokSeviyesi = 0,
    this.seriTakipli = false,
    required this.updatedAt,
    this.dirty = true,
    this.deleted = false,
  });

  factory Urun.fromMap(Map<String, dynamic> m) => Urun(
        id: m['id'] as String,
        ad: m['ad'] as String,
        barkod: m['barkod'] as String?,
        birim: (m['birim'] as String?) ?? 'adet',
        kategori: m['kategori'] as String?,
        minStokSeviyesi: (m['min_stok_seviyesi'] as int?) ?? 0,
        seriTakipli: _intToBool((m['seri_takipli'] as int?) ?? 0),
        updatedAt: _epochToDate(m['updated_at'] as int),
        dirty: _intToBool(m['dirty'] as int),
        deleted: _intToBool(m['deleted'] as int),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'ad': ad,
        'barkod': barkod,
        'birim': birim,
        'kategori': kategori,
        'min_stok_seviyesi': minStokSeviyesi,
        'seri_takipli': _boolToInt(seriTakipli),
        'updated_at': _dateToEpoch(updatedAt),
        'dirty': _boolToInt(dirty),
        'deleted': _boolToInt(deleted),
      };
}

class Arac {
  final String id;
  final String plaka;
  final String? ad;
  final String? aciklama;
  final DateTime updatedAt;
  final bool dirty;
  final bool deleted;

  Arac({
    required this.id,
    required this.plaka,
    this.ad,
    this.aciklama,
    required this.updatedAt,
    this.dirty = true,
    this.deleted = false,
  });

  factory Arac.fromMap(Map<String, dynamic> m) => Arac(
        id: m['id'] as String,
        plaka: m['plaka'] as String,
        ad: m['ad'] as String?,
        aciklama: m['aciklama'] as String?,
        updatedAt: _epochToDate(m['updated_at'] as int),
        dirty: _intToBool(m['dirty'] as int),
        deleted: _intToBool(m['deleted'] as int),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'plaka': plaka,
        'ad': ad,
        'aciklama': aciklama,
        'updated_at': _dateToEpoch(updatedAt),
        'dirty': _boolToInt(dirty),
        'deleted': _boolToInt(deleted),
      };
}

class Kullanici {
  final String id;
  final String ad;
  final String email;
  final KullaniciRol rol;
  final DateTime updatedAt;
  final bool dirty;
  final bool deleted;

  Kullanici({
    required this.id,
    required this.ad,
    required this.email,
    required this.rol,
    required this.updatedAt,
    this.dirty = true,
    this.deleted = false,
  });

  factory Kullanici.fromMap(Map<String, dynamic> m) => Kullanici(
        id: m['id'] as String,
        ad: m['ad'] as String,
        email: m['email'] as String,
        rol: KullaniciRol.values.firstWhere((r) => r.name == m['rol']),
        updatedAt: _epochToDate(m['updated_at'] as int),
        dirty: _intToBool(m['dirty'] as int),
        deleted: _intToBool(m['deleted'] as int),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'ad': ad,
        'email': email,
        'rol': rol.name,
        'updated_at': _dateToEpoch(updatedAt),
        'dirty': _boolToInt(dirty),
        'deleted': _boolToInt(deleted),
      };
}

class DepoStok {
  final String id;
  final String depoId;
  final String urunId;
  final int miktar;
  final DateTime updatedAt;
  final bool dirty;
  final bool deleted;

  DepoStok({
    required this.id,
    required this.depoId,
    required this.urunId,
    this.miktar = 0,
    required this.updatedAt,
    this.dirty = true,
    this.deleted = false,
  });

  factory DepoStok.fromMap(Map<String, dynamic> m) => DepoStok(
        id: m['id'] as String,
        depoId: m['depo_id'] as String,
        urunId: m['urun_id'] as String,
        miktar: (m['miktar'] as int?) ?? 0,
        updatedAt: _epochToDate(m['updated_at'] as int),
        dirty: _intToBool(m['dirty'] as int),
        deleted: _intToBool(m['deleted'] as int),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'depo_id': depoId,
        'urun_id': urunId,
        'miktar': miktar,
        'updated_at': _dateToEpoch(updatedAt),
        'dirty': _boolToInt(dirty),
        'deleted': _boolToInt(deleted),
      };
}

class StokHareketi {
  final String id;
  final String urunId;
  final String depoId;
  final String? hedefDepoId;
  final HareketTipi tip;
  final int miktar;
  final String kullaniciId;
  final DateTime tarih;
  final String? not_;
  final String? cihazId; // seri numaralı cihaz hareketlerinde dolu
  final String? sebep; // depoya geri almada: Arıza, Değişim...
  final DateTime updatedAt;
  final bool dirty;
  final bool deleted;

  StokHareketi({
    required this.id,
    required this.urunId,
    required this.depoId,
    this.hedefDepoId,
    required this.tip,
    required this.miktar,
    required this.kullaniciId,
    required this.tarih,
    this.not_,
    this.cihazId,
    this.sebep,
    required this.updatedAt,
    this.dirty = true,
    this.deleted = false,
  });

  factory StokHareketi.fromMap(Map<String, dynamic> m) => StokHareketi(
        id: m['id'] as String,
        urunId: m['urun_id'] as String,
        depoId: m['depo_id'] as String,
        hedefDepoId: m['hedef_depo_id'] as String?,
        tip: HareketTipi.values.firstWhere((t) => t.name == m['tip']),
        miktar: m['miktar'] as int,
        kullaniciId: m['kullanici_id'] as String,
        tarih: _epochToDate(m['tarih'] as int),
        not_: m['not_'] as String?,
        cihazId: m['cihaz_id'] as String?,
        sebep: m['sebep'] as String?,
        updatedAt: _epochToDate(m['updated_at'] as int),
        dirty: _intToBool(m['dirty'] as int),
        deleted: _intToBool(m['deleted'] as int),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'urun_id': urunId,
        'depo_id': depoId,
        'hedef_depo_id': hedefDepoId,
        'tip': tip.name,
        'miktar': miktar,
        'kullanici_id': kullaniciId,
        'tarih': _dateToEpoch(tarih),
        'not_': not_,
        'cihaz_id': cihazId,
        'sebep': sebep,
        'updated_at': _dateToEpoch(updatedAt),
        'dirty': _boolToInt(dirty),
        'deleted': _boolToInt(deleted),
      };
}

class KullanimKaydi {
  final String id;
  final String stokHareketId;
  final String? aracId;
  final String? kullanimYeri;
  final String? not_;
  final DateTime updatedAt;
  final bool dirty;
  final bool deleted;

  KullanimKaydi({
    required this.id,
    required this.stokHareketId,
    this.aracId,
    this.kullanimYeri,
    this.not_,
    required this.updatedAt,
    this.dirty = true,
    this.deleted = false,
  });

  factory KullanimKaydi.fromMap(Map<String, dynamic> m) => KullanimKaydi(
        id: m['id'] as String,
        stokHareketId: m['stok_hareket_id'] as String,
        aracId: m['arac_id'] as String?,
        kullanimYeri: m['kullanim_yeri'] as String?,
        not_: m['not_'] as String?,
        updatedAt: _epochToDate(m['updated_at'] as int),
        dirty: _intToBool(m['dirty'] as int),
        deleted: _intToBool(m['deleted'] as int),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'stok_hareket_id': stokHareketId,
        'arac_id': aracId,
        'kullanim_yeri': kullanimYeri,
        'not_': not_,
        'updated_at': _dateToEpoch(updatedAt),
        'dirty': _boolToInt(dirty),
        'deleted': _boolToInt(deleted),
      };
}

/// Seri numarasıyla tek tek takip edilen fiziksel cihaz (ör. bir NVR).
class Cihaz {
  final String id;
  final String urunId;
  final String seriNo;
  final String? depoId; // yalnızca durum == depoda iken dolu
  final CihazDurumu durum;
  final String? aracId;
  final String? kullanimYeri;
  // Alım / garanti bilgileri (opsiyonel)
  final DateTime? alimTarihi;
  final String? firma;
  final String? ihale;
  final DateTime? garantiBitis;
  final DateTime updatedAt;
  final bool dirty;
  final bool deleted;

  Cihaz({
    required this.id,
    required this.urunId,
    required this.seriNo,
    this.depoId,
    required this.durum,
    this.aracId,
    this.kullanimYeri,
    this.alimTarihi,
    this.firma,
    this.ihale,
    this.garantiBitis,
    required this.updatedAt,
    this.dirty = true,
    this.deleted = false,
  });

  factory Cihaz.fromMap(Map<String, dynamic> m) => Cihaz(
        id: m['id'] as String,
        urunId: m['urun_id'] as String,
        seriNo: m['seri_no'] as String,
        depoId: m['depo_id'] as String?,
        durum: CihazDurumu.values.firstWhere((d) => d.name == m['durum']),
        aracId: m['arac_id'] as String?,
        kullanimYeri: m['kullanim_yeri'] as String?,
        alimTarihi: _epochOrNull(m['alim_tarihi']),
        firma: m['firma'] as String?,
        ihale: m['ihale'] as String?,
        garantiBitis: _epochOrNull(m['garanti_bitis']),
        updatedAt: _epochToDate(m['updated_at'] as int),
        dirty: _intToBool(m['dirty'] as int),
        deleted: _intToBool(m['deleted'] as int),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'urun_id': urunId,
        'seri_no': seriNo,
        'depo_id': depoId,
        'durum': durum.name,
        'arac_id': aracId,
        'kullanim_yeri': kullanimYeri,
        'alim_tarihi': alimTarihi?.millisecondsSinceEpoch,
        'firma': firma,
        'ihale': ihale,
        'garanti_bitis': garantiBitis?.millisecondsSinceEpoch,
        'updated_at': _dateToEpoch(updatedAt),
        'dirty': _boolToInt(dirty),
        'deleted': _boolToInt(deleted),
      };
}


/// Cihazın alım / garanti bilgileri (giriş ekranında ve cihaz kartında
/// düzenlenir). Boş metinler veritabanına null olarak yazılır.
class AlimBilgisi {
  AlimBilgisi({
    this.alimTarihi,
    this.firma = '',
    this.ihale = '',
    this.garantiBitis,
  });

  factory AlimBilgisi.cihazdan(Cihaz c) => AlimBilgisi(
        alimTarihi: c.alimTarihi,
        firma: c.firma ?? '',
        ihale: c.ihale ?? '',
        garantiBitis: c.garantiBitis,
      );

  DateTime? alimTarihi;
  String firma;
  String ihale;
  DateTime? garantiBitis;

  String? get firmaVeyaNull => firma.trim().isEmpty ? null : firma.trim();
  String? get ihaleVeyaNull => ihale.trim().isEmpty ? null : ihale.trim();

  bool get bos =>
      alimTarihi == null &&
      firmaVeyaNull == null &&
      ihaleVeyaNull == null &&
      garantiBitis == null;

  /// Veritabanı sütunları (null değerler dahil).
  Map<String, Object?> kolonlar() => {
        'alim_tarihi': alimTarihi?.millisecondsSinceEpoch,
        'firma': firmaVeyaNull,
        'ihale': ihaleVeyaNull,
        'garanti_bitis': garantiBitis?.millisecondsSinceEpoch,
      };
}
