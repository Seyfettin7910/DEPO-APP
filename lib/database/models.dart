enum KullaniciRol { admin, depoSorumlusu, sahaKullanicisi }

/// Depo türü: sabit depo ya da seyyar depo olarak çalışan araç.
enum DepoTuru { sabit, arac }

enum HareketTipi { girisi, cikis, transfer, kullanim, iade, silme, servis, hurda }

/// Kayıttaki hareket türünü çözer; tanınmayan (daha yeni sürümden gelmiş)
/// bir tür uygulamayı çökertmesin diye "çıkış" sayılır.
HareketTipi hareketTipiCoz(Object? ad) => HareketTipi.values
    .firstWhere((t) => t.name == ad, orElse: () => HareketTipi.cikis);

/// Seri numaralı bir cihazın şu anki durumu.
enum CihazDurumu { depoda, kullanimda, cikti }

/// Arızalı / servisteki / hurdaya ayrılmış cihazın durumu (sağlam cihazda
/// null). İlk dördünde cihaz depodadır ama kullanılamaz: transfer, kullanıma
/// verme, sahada kullanım ve çıkış yapılamaz.
enum ServisDurumu {
  tamirGerekli,
  degisimGerekli,
  garantide,
  onarimda,
  hurda,
  degistirildi;

  String get etiket => switch (this) {
        ServisDurumu.tamirGerekli => 'Arızalı · tamir gerekli',
        ServisDurumu.degisimGerekli =>
          'Arızalı · tamiri mümkün değil, değişim gerekli',
        ServisDurumu.garantide => 'Garanti servisinde',
        ServisDurumu.onarimda => 'Kendi bünyemizde onarımda',
        ServisDurumu.hurda => 'Hurdaya ayrıldı',
        ServisDurumu.degistirildi => 'Değiştirildi (firmaya teslim)',
      };

  /// Kısa etiket (listelerde rozet).
  String get kisa => switch (this) {
        ServisDurumu.tamirGerekli => 'Arızalı',
        ServisDurumu.degisimGerekli => 'Değişim gerekli',
        ServisDurumu.garantide => 'Garantide',
        ServisDurumu.onarimda => 'Onarımda',
        ServisDurumu.hurda => 'Hurda',
        ServisDurumu.degistirildi => 'Değiştirildi',
      };

  /// Cihaz depoda ama arızalı / serviste (kullanılamaz).
  bool get arizali => index <= ServisDurumu.onarimda.index;

  /// Servise (firmaya / onarıma) gönderilmiş.
  bool get serviste =>
      this == ServisDurumu.garantide || this == ServisDurumu.onarimda;
}

ServisDurumu? servisDurumuCoz(Object? ad) {
  for (final d in ServisDurumu.values) {
    if (d.name == ad) return d;
  }
  return null;
}

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

/// Miktarla takip edilen ürünlerin (kablo, adaptör…) birimleri.
const malzemeBirimleri = ['adet', 'metre', 'paket', 'top', 'kutu'];

class Urun {
  final String id;
  final String ad;
  final String? barkod;
  final String birim;
  final String? kategori;
  final int minStokSeviyesi;
  final bool seriTakipli; // true: her cihaz seri no ile takip edilir

  /// Malzemede bir kutu / topun içeriği (ör. 305 metre); null = 1.
  final int? kutuIcerigi;
  final DateTime updatedAt;

  /// Seri numarasız, miktarla (adet, metre, paket…) takip edilen malzeme.
  bool get miktarli => !seriTakipli;

  /// "50 metre" gibi.
  String miktarMetni(int miktar) => '$miktar $birim';

  /// Bir okutmada eklenen miktar (kutu / top içeriği; yoksa 1).
  int get okutmaMiktari =>
      (kutuIcerigi == null || kutuIcerigi! < 1) ? 1 : kutuIcerigi!;

  /// "610 metre (2 kutu)" gibi; kutu içeriği yoksa yalnız miktar.
  String kutuluMetin(int miktar) {
    final k = okutmaMiktari;
    if (k <= 1 || miktar % k != 0) return miktarMetni(miktar);
    return '${miktarMetni(miktar)} (${miktar ~/ k} kutu)';
  }
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
    this.kutuIcerigi,
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
        kutuIcerigi: (m['kutu_icerigi'] as num?)?.toInt(),
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
        'kutu_icerigi': kutuIcerigi,
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
        tip: hareketTipiCoz(m['tip']),
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
  // Kullanım / montaj anındaki GPS konumu (opsiyonel)
  final double? enlem;
  final double? boylam;
  final double? konumHassasiyet; // metre
  final String? il;
  final String? ilce;
  final String? mahalle; // mahalle veya köy
  // Montaj tutanağı: alindi | alinacak | kurum_ici (eski kayıtlarda null)
  final String? tutanak;
  final DateTime? tutanakTarihi;
  final String? tutanakKullaniciId;
  final DateTime updatedAt;
  final bool dirty;
  final bool deleted;

  KullanimKaydi({
    required this.id,
    required this.stokHareketId,
    this.aracId,
    this.kullanimYeri,
    this.not_,
    this.enlem,
    this.boylam,
    this.konumHassasiyet,
    this.il,
    this.ilce,
    this.mahalle,
    this.tutanak,
    this.tutanakTarihi,
    this.tutanakKullaniciId,
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
        enlem: (m['enlem'] as num?)?.toDouble(),
        boylam: (m['boylam'] as num?)?.toDouble(),
        konumHassasiyet: (m['konum_hassasiyet'] as num?)?.toDouble(),
        il: m['il'] as String?,
        ilce: m['ilce'] as String?,
        mahalle: m['mahalle'] as String?,
        tutanak: m['tutanak'] as String?,
        tutanakTarihi: _epochOrNull(m['tutanak_tarihi']),
        tutanakKullaniciId: m['tutanak_kullanici_id'] as String?,
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
        'enlem': enlem,
        'boylam': boylam,
        'konum_hassasiyet': konumHassasiyet,
        'il': il,
        'ilce': ilce,
        'mahalle': mahalle,
        'tutanak': tutanak,
        'tutanak_tarihi': tutanakTarihi?.millisecondsSinceEpoch,
        'tutanak_kullanici_id': tutanakKullaniciId,
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
  final ServisDurumu? servisDurumu; // arızalı / serviste / hurda; sağlamsa null
  final DateTime updatedAt;
  final bool dirty;
  final bool deleted;

  /// Depoda ama arızalı / serviste (kullanılamaz).
  bool get arizali => servisDurumu?.arizali ?? false;

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
    this.servisDurumu,
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
        servisDurumu: servisDurumuCoz(m['servis_durumu']),
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
        'servis_durumu': servisDurumu?.name,
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


/// Bir arıza / servis dosyası: arızanın tespitinden (sahadan geri alma)
/// onarım sonucuna ve kapanışa (depoya dönüş, değişim veya hurda) kadar.
class ServisKaydi {
  ServisKaydi({
    required this.id,
    required this.cihazId,
    required this.urunId,
    required this.acilisTarihi,
    required this.karar,
    this.arizaAciklama,
    this.onarimYeri,
    this.firma,
    this.gonderimTarihi,
    this.donusTarihi,
    this.sonuc,
    this.sonucAciklama,
    this.yeniSeriNo,
    this.kapanis,
    this.kapanisTarihi,
    required this.kullaniciId,
    required this.updatedAt,
    this.dirty = true,
    this.deleted = false,
  });

  final String id;
  final String cihazId;
  final String urunId;
  final DateTime acilisTarihi;
  final String? arizaAciklama;
  final String karar; // tamir | degisim
  final String? onarimYeri; // garanti | ic
  final String? firma; // garantide servis firması; içte onarımı yapan birim
  final DateTime? gonderimTarihi;
  final DateTime? donusTarihi;
  final String? sonuc; // onarildi | degistirildi | onarilamadi
  final String? sonucAciklama;
  final String? yeniSeriNo; // değişimde gelen cihaz
  final String? kapanis; // depoya | hurda | degisim | degisim_bekliyor
  final DateTime? kapanisTarihi;
  final String kullaniciId;
  final DateTime updatedAt;
  final bool dirty;
  final bool deleted;

  bool get acik => kapanis == null;

  /// Gönderimden dönüşe (dönmediyse bugüne) geçen süre.
  Duration? get onarimSuresi {
    if (gonderimTarihi == null) return null;
    return (donusTarihi ?? DateTime.now()).difference(gonderimTarihi!);
  }

  factory ServisKaydi.fromMap(Map<String, dynamic> m) => ServisKaydi(
        id: m['id'] as String,
        cihazId: m['cihaz_id'] as String,
        urunId: m['urun_id'] as String,
        acilisTarihi: _epochToDate((m['acilis_tarihi'] as num).toInt()),
        arizaAciklama: m['ariza_aciklama'] as String?,
        karar: (m['karar'] as String?) ?? 'tamir',
        onarimYeri: m['onarim_yeri'] as String?,
        firma: m['firma'] as String?,
        gonderimTarihi: _epochOrNull(m['gonderim_tarihi']),
        donusTarihi: _epochOrNull(m['donus_tarihi']),
        sonuc: m['sonuc'] as String?,
        sonucAciklama: m['sonuc_aciklama'] as String?,
        yeniSeriNo: m['yeni_seri_no'] as String?,
        kapanis: m['kapanis'] as String?,
        kapanisTarihi: _epochOrNull(m['kapanis_tarihi']),
        kullaniciId: (m['kullanici_id'] as String?) ?? '',
        updatedAt: _epochToDate((m['updated_at'] as num).toInt()),
        dirty: _intToBool(((m['dirty'] as num?) ?? 0).toInt()),
        deleted: _intToBool(((m['deleted'] as num?) ?? 0).toInt()),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'cihaz_id': cihazId,
        'urun_id': urunId,
        'acilis_tarihi': _dateToEpoch(acilisTarihi),
        'ariza_aciklama': arizaAciklama,
        'karar': karar,
        'onarim_yeri': onarimYeri,
        'firma': firma,
        'gonderim_tarihi': gonderimTarihi?.millisecondsSinceEpoch,
        'donus_tarihi': donusTarihi?.millisecondsSinceEpoch,
        'sonuc': sonuc,
        'sonuc_aciklama': sonucAciklama,
        'yeni_seri_no': yeniSeriNo,
        'kapanis': kapanis,
        'kapanis_tarihi': kapanisTarihi?.millisecondsSinceEpoch,
        'kullanici_id': kullaniciId,
        'updated_at': _dateToEpoch(updatedAt),
        'dirty': _boolToInt(dirty),
        'deleted': _boolToInt(deleted),
      };
}

/// "2 gün 5 saat", "3 saat 10 dk" gibi okunur süre.
String sureMetni(Duration d) {
  if (d.isNegative) return '-';
  final gun = d.inDays;
  final saat = d.inHours % 24;
  final dk = d.inMinutes % 60;
  if (gun > 0) return saat > 0 ? '$gun gün $saat saat' : '$gun gün';
  if (saat > 0) return dk > 0 ? '$saat saat $dk dk' : '$saat saat';
  return '$dk dk';
}

/// Servis kaydındaki kodların okunur karşılıkları.
const servisKararAdlari = {
  'tamir': 'Tamir gerekli',
  'degisim': 'Tamiri mümkün değil, değişim gerekli',
};
const onarimYeriAdlari = {
  'garanti': 'Garanti kapsamında (firma)',
  'ic': 'Kendi bünyemizde',
};
const servisSonucAdlari = {
  'onarildi': 'Onarıldı',
  'degistirildi': 'Yeni cihazla değiştirildi',
  'onarilamadi': 'Onarılamadı',
};
const servisKapanisAdlari = {
  'depoya': 'Depoya eklendi',
  'hurda': 'Hurdaya ayrıldı',
  'degisim': 'Yeni cihaz depoya eklendi',
  'degisim_bekliyor': 'Değişim için bekletiliyor',
};

// ---------------------------------------------------------------------
// Montaj tutanağı
// ---------------------------------------------------------------------

/// Montaj / kullanımda tutanak durumu. Eski kayıtlarda boş: "Belirtilmemiş".
const tutanakSecenekleri = ['alindi', 'alinacak', 'kurum_ici'];

/// Seçim düğmelerindeki ve kartlardaki ad.
String tutanakAdi(String? t) => switch (t) {
      'alindi' => 'Tutanak alındı',
      'alinacak' => 'Tutanak alınacak',
      'kurum_ici' => 'Kurum içi kullanım (tutanak yok)',
      _ => 'Tutanak belirtilmemiş',
    };

/// Raporlardaki kısa ad.
String tutanakKisa(String? t) => switch (t) {
      'alindi' => 'Alındı',
      'alinacak' => 'Alınacak',
      'kurum_ici' => 'Kurum içi',
      _ => 'Belirtilmemiş',
    };

/// Cihazın şu anki durum adı (kartlarda, raporlarda).
const montajDurumAdi = 'Montaj Yapıldı / Kullanıldı';
