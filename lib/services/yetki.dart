/// 1.36.0: Roller ve yetkiler.
///
/// Yetki tablosu yöneticinin düzenleyebildiği bir tablodur (Ayarlar → Roller
/// ve yetkiler); aşağıdaki varsayılanlarla başlar. Sunucuda da aynı tablo
/// (yetkiler) ve aynı adlar kullanılır: supabase_guncelleme_1_36_0.sql.
/// Kilitler: Yönetici rolünden kullanıcı yönetimi kaldırılamaz; hareket
/// kaydı silme kimseye açılamaz. Testleri: test/yetki_test.dart.
library;

import '../database/models.dart';

enum Yetki {
  okut(1, 'Okutma, cihaz kartını görme', 'Genel', 'YDSGA'),
  ara(2, 'Cihaz arama', 'Genel', 'YDSGA'),
  depoGiris(3, 'Depoya giriş (yeni cihaz)', 'Cihaz hareketleri', 'YD'),
  transfer(4, 'Depolar arası transfer', 'Cihaz hareketleri', 'YD'),
  aracaYukle(5, 'Araca yükleme', 'Cihaz hareketleri', 'YDS'),
  iade(6, 'Araçtan depoya iade', 'Cihaz hareketleri', 'YDS'),
  montaj(7, 'Montaj / kullanıldı', 'Cihaz hareketleri', 'YDS'),
  geriAlma(8, 'Sahadan geri alma', 'Cihaz hareketleri', 'YDS'),
  ariza(9, 'Arıza bildirme (arızalı işaretleme)', 'Cihaz hareketleri', 'YDS'),
  servis(10, 'Servis süreci (gönderme, dönüş, değişim)', 'Cihaz hareketleri', 'YD'),
  cihazDuzenle(11, 'Cihaz kartı bilgisini düzenleme (alım, garanti, tutanak)',
      'Cihaz hareketleri', 'YD'),
  hurda(12, 'Hurdaya ayırma', 'Cihaz hareketleri', 'Y'),
  cihazSil(13, 'Cihaz silme', 'Cihaz hareketleri', 'Y'),
  malzemeGiris(14, 'Malzeme girişi', 'Malzeme', 'YD'),
  malzemeAraca(15, 'Malzemeyi araca yükleme', 'Malzeme', 'YDS'),
  malzemeIade(15, 'Araçtan depoya malzeme iadesi', 'Malzeme', 'YDS'),
  malzemeTransfer(15, 'Depolar arası malzeme transferi', 'Malzeme', 'YD'),
  malzemeKullanim(16, 'Montajda malzeme kullanımı', 'Malzeme', 'YDS'),
  urunTanim(17, 'Ürün / model tanımlama, düzenleme', 'Tanımlar', 'YD'),
  urunBirlestir(18, 'Ürün birleştirme', 'Tanımlar', 'YD'),
  urunSil(19, 'Ürün silme', 'Tanımlar', 'Y'),
  depoTanim(20, 'Depo / araç tanımlama, düzenleme', 'Tanımlar', 'YD'),
  depoSil(21, 'Depo / araç silme', 'Tanımlar', 'Y'),
  sayim(22, 'Sayım', 'Sayım ve etiket', 'YD'),
  kurumKodu(23, 'Kurum kodu üretme, basım kuyruğu', 'Sayım ve etiket', 'YD'),
  etiketBas(24, 'Etiket basma (bilgisayardan)', 'Sayım ve etiket', 'YD'),
  etiketDogrula(25, 'Etiket yapıştırma doğrulaması', 'Sayım ve etiket', 'YDS'),
  etiketAyar(26, 'Kurum etiketi ayarları (kodlar, engel)', 'Sayım ve etiket', 'Y'),
  rapor(27, 'Raporlar, PDF / Excel', 'Rapor ve yönetim', 'YDGA'),
  girisKayitlari(28, 'Giriş kayıtları', 'Rapor ve yönetim', 'Y'),
  okumaIstatistik(29, 'Okuma istatistikleri raporu', 'Rapor ve yönetim', 'YD'),
  kullaniciYonetimi(30, 'Kullanıcı yönetimi, roller ve yetkiler',
      'Rapor ve yönetim', 'Y'),
  bildirimAyar(31, 'Kendi bildirim ayarları', 'Rapor ve yönetim', 'YDSGA'),
  hareketSilme(33, 'Hareket kaydı silme', 'Rapor ve yönetim', '');

  const Yetki(this.no, this.etiket, this.grup, this._varsayilan);

  /// Notlardaki yetki tablosundaki madde numarası.
  final int no;
  final String etiket;
  final String grup;

  /// Varsayılan olarak açık olduğu roller: Y Yönetici · D Depo sorumlusu ·
  /// S Saha · G Gözlemci · A Amir.
  final String _varsayilan;

  /// Sunucudaki adı (yetkiler.yetki): depoGiris → depo_giris.
  String get anahtar => name.replaceAllMapped(
      RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

  bool varsayilan(KullaniciRol rol) => _varsayilan.contains(_harf[rol]!);

  /// Kilitli hücre: değeri değiştirilemez.
  bool kilitli(KullaniciRol rol) =>
      this == Yetki.hareketSilme ||
      (this == Yetki.kullaniciYonetimi && rol == KullaniciRol.admin);

  static Yetki? anahtardan(String a) {
    for (final y in values) {
      if (y.anahtar == a) return y;
    }
    return null;
  }
}

const _harf = {
  KullaniciRol.admin: 'Y',
  KullaniciRol.depoSorumlusu: 'D',
  KullaniciRol.sahaKullanicisi: 'S',
  KullaniciRol.gozlemci: 'G',
  KullaniciRol.amir: 'A',
};

/// Sunucudaki yetkiler.id: "rol:yetki".
String yetkiKimligi(KullaniciRol rol, Yetki y) => '${rol.name}:${y.anahtar}';

/// Kilitleri uygular (sunucu da aynısını yapar).
bool kilitliDeger(KullaniciRol rol, Yetki y, bool istenen) {
  if (y == Yetki.hareketSilme) return false;
  if (y == Yetki.kullaniciYonetimi && rol == KullaniciRol.admin) return true;
  return istenen;
}

/// Giriş yapan kişinin geçerli yetkileri.
///
/// [tablo] (rol:yetki → izin) sunucudan senkronlanır. Sunucuda yetki
/// tablosu henüz yoksa (1.36.0 SQL'i çalıştırılmadıysa) [eskiDuzen] true:
/// herkes her şeyi yapabilir (bugünkü gibi), hiçbir düğme gizlenmez.
class Yetkilerim {
  const Yetkilerim({
    required this.rol,
    required this.tablo,
    this.eskiDuzen = false,
  });

  /// Sunucu tablosu yok: eski düzen (her şey açık).
  const Yetkilerim.eski()
      : rol = null,
        tablo = const {},
        eskiDuzen = true;

  final KullaniciRol? rol;
  final Map<String, bool> tablo;
  final bool eskiDuzen;

  bool var_(Yetki y) {
    if (eskiDuzen) return y != Yetki.hareketSilme;
    final r = rol;
    if (r == null) return false;
    final deger = tablo[yetkiKimligi(r, y)] ?? y.varsayilan(r);
    return kilitliDeger(r, y, deger);
  }

  bool herhangi(Iterable<Yetki> l) => l.any(var_);
  bool get yonetici => var_(Yetki.kullaniciYonetimi);
}
