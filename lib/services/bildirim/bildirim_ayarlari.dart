import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Bildirim türleri. Her kullanıcı kendi telefonunda açıp kapatabilir.
enum BildirimTuru {
  kritikStok(
    'Kritik stok / tükendi',
    'Ürün minimum adedin altına inince veya tükenince',
    'Stok ve servis',
  ),
  yeniAriza(
    'Yeni arıza kaydı',
    'Sahadan arızalı cihaz geri alınınca veya arızalı işaretlenince',
    'Stok ve servis',
  ),
  servisGecikmesi(
    'Servis gecikmesi',
    'Serviste veya arızalı bekleyen cihaz belirlenen günü geçince',
    'Stok ve servis',
  ),
  garantiBitiyor(
    'Garanti bitiyor',
    'Cihazın garantisinin bitmesine belirlenen gün kala',
    'Stok ve servis',
  ),
  cihazGeldi(
    'Araca / depoya cihaz geldi',
    'Transfer, kullanıma verme veya iade ile cihaz gelince',
    'Hareketler',
  ),
  depoyaGiris(
    'Depoya giriş',
    'Yeni cihaz girişi yapılınca',
    'Hareketler',
  ),
  hurdaSilme(
    'Hurda ve silme',
    'Bir cihaz hurdaya ayrılınca veya silinince',
    'Hareketler',
  ),
  servisDonus(
    'Servisten dönüş',
    'Onarıldı / değiştirildi / onarılamadı sonucu girilince',
    'Hareketler',
  ),
  hataliSifre(
    'Hatalı şifre denemeleri',
    'Bir hesaba arka arkaya hatalı şifre girilince (internet gerekir)',
    'Güvenlik ve sistem',
  ),
  yeniIpGiris(
    "Yeni cihaz / IP'den giriş",
    'Bir kullanıcı daha önce görülmemiş IP adresinden girince',
    'Güvenlik ve sistem',
  ),
  gonderilmemis(
    'Gönderilmemiş kayıtlar',
    'Bu telefonda 1 saattir sunucuya gidemeyen işlem varsa',
    'Güvenlik ve sistem',
  ),
  gunlukOzet(
    'Günlük özet',
    'Her sabah: kritik stok, serviste bekleyen, dünkü hareketler',
    'Güvenlik ve sistem',
  ),
  etiketBasim(
    'Basım bekleyen etiket',
    'Basım kuyruğuna yeni kurum etiketi girince (etiketleri basan kişiler için)',
    'Kurum etiketi',
  ),
  etiketUyusmazlik(
    'Etiket uyuşmazlığı',
    'Yapıştırma doğrulamasında etiket ile cihaz eşleşmeyince',
    'Kurum etiketi',
  );

  const BildirimTuru(this.etiket, this.aciklama, this.grup);
  final String etiket;
  final String aciklama;
  final String grup;

  /// Herkesi ilgilendirmeyen (yöneticiye yönelik) türler varsayılan kapalı.
  bool get varsayilan =>
      this != BildirimTuru.hataliSifre &&
      this != BildirimTuru.yeniIpGiris &&
      this != BildirimTuru.etiketBasim;
}

/// 1.19.0'daki türler: kayıtlı ayarda "bilinen" listesi yoksa bunlar
/// biliniyor sayılır; sonradan eklenen türler varsayılan değeriyle açılır.
const _ilkTurler = [
  'kritikStok', 'yeniAriza', 'servisGecikmesi', 'garantiBitiyor', 'cihazGeldi',
  'depoyaGiris', 'hurdaSilme', 'servisDonus', 'hataliSifre', 'yeniIpGiris',
  'gonderilmemis', 'gunlukOzet',
];

class BildirimAyarlari {
  BildirimAyarlari({
    Set<BildirimTuru>? acik,
    this.servisGecikmeGun = 15,
    this.garantiGun = 30,
    Set<String>? izlenenDepolar,
    this.ozetSaat = 8,
    this.ozetDakika = 30,
  })  : acik = acik ??
            {for (final t in BildirimTuru.values) if (t.varsayilan) t},
        izlenenDepolar = izlenenDepolar ?? {};

  final Set<BildirimTuru> acik;
  int servisGecikmeGun;
  int garantiGun;

  /// "Cihaz geldi" için izlenen depo / araçlar; boşsa hepsi.
  final Set<String> izlenenDepolar;
  int ozetSaat;
  int ozetDakika;

  bool acikMi(BildirimTuru t) => acik.contains(t);

  static const _anahtar = 'bildirim_ayarlari';

  static Future<BildirimAyarlari> yukle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Arka plan görevi ayrı çalışır; diskteki son hali oku.
      await prefs.reload();
      final metin = prefs.getString(_anahtar);
      if (metin == null) return BildirimAyarlari();
      final m = jsonDecode(metin) as Map<String, dynamic>;
      final bilinen = {
        for (final x in (m['bilinen'] as List? ?? _ilkTurler)) '$x'
      };
      return BildirimAyarlari(
        acik: {
          for (final ad in (m['acik'] as List? ?? const []))
            for (final t in BildirimTuru.values)
              if (t.name == ad) t,
          // Ayar kaydedildikten sonra eklenen türler varsayılanıyla gelir.
          for (final t in BildirimTuru.values)
            if (!bilinen.contains(t.name) && t.varsayilan) t,
        },
        servisGecikmeGun: (m['servisGecikmeGun'] as num?)?.toInt() ?? 15,
        garantiGun: (m['garantiGun'] as num?)?.toInt() ?? 30,
        izlenenDepolar: {
          for (final d in (m['izlenenDepolar'] as List? ?? const [])) '$d'
        },
        ozetSaat: (m['ozetSaat'] as num?)?.toInt() ?? 8,
        ozetDakika: (m['ozetDakika'] as num?)?.toInt() ?? 30,
      );
    } catch (_) {
      return BildirimAyarlari();
    }
  }

  /// Sunucuya da (web bildirimi) aynı biçimde gönderilir.
  Map<String, dynamic> toJson() => {
        'acik': [for (final t in acik) t.name],
        'bilinen': [for (final t in BildirimTuru.values) t.name],
        'servisGecikmeGun': servisGecikmeGun,
        'garantiGun': garantiGun,
        'izlenenDepolar': izlenenDepolar.toList(),
        'ozetSaat': ozetSaat,
        'ozetDakika': ozetDakika,
      };

  Future<void> kaydet() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_anahtar, jsonEncode(toJson()));
  }
}
