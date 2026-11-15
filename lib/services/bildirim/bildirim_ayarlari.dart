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
    'Transfer, Araca Yükle veya iade ile cihaz / malzeme gelince',
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
  sifreTalebi(
    'Şifre talebi',
    'Bir kullanıcı giriş ekranında "Şifremi unuttum" deyince (yöneticiler için)',
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
  ),
  zimmetOnaysiz(
    'Onaysız zimmet kullanımı girişimi',
    'Belediye Zimmeti\'ndeki ürün Başkanlık onayı olmadan kırsal mahalleye '
        'takılmak istenince (yöneticiler için)',
    'Belediye zimmeti',
  );

  const BildirimTuru(this.etiket, this.aciklama, this.grup);
  final String etiket;
  final String aciklama;
  final String grup;

  /// Herkesi ilgilendirmeyen (yöneticiye yönelik) türler varsayılan kapalı.
  bool get varsayilan =>
      this != BildirimTuru.hataliSifre &&
      this != BildirimTuru.yeniIpGiris &&
      this != BildirimTuru.etiketBasim &&
      this != BildirimTuru.zimmetOnaysiz &&
      this != BildirimTuru.sifreTalebi;

  /// 1.36.0: alıcıları yöneticinin merkezi olarak seçtiği türler
  /// (Kullanıcılar → Roller ve yetkiler → Bildirim alıcıları). "Gönderilmemiş
  /// kayıtlar" yalnız o telefonu ilgilendirir, merkezden seçilmez.
  bool get merkezi => this != BildirimTuru.gonderilmemis;
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
    Set<BildirimTuru>? kapatilan,
  })  : acik = acik ??
            {for (final t in BildirimTuru.values) if (t.varsayilan) t},
        kapatilan = kapatilan ?? {},
        izlenenDepolar = izlenenDepolar ?? {};

  final Set<BildirimTuru> acik;

  /// 1.36.0: kişinin kendisinin kapattığı türler. Merkezi alıcı listesinde
  /// olsa bile bu türleri almaz (kişi yalnızca kapatabilir).
  final Set<BildirimTuru> kapatilan;
  int servisGecikmeGun;
  int garantiGun;

  /// "Cihaz geldi" için izlenen depo / araçlar; boşsa hepsi.
  final Set<String> izlenenDepolar;
  int ozetSaat;
  int ozetDakika;

  bool acikMi(BildirimTuru t) => acik.contains(t);

  /// Kişinin anahtarı: açar ya da kapatır.
  void ayarla(BildirimTuru t, bool ac) {
    if (ac) {
      acik.add(t);
      kapatilan.remove(t);
    } else {
      acik.remove(t);
      kapatilan.add(t);
    }
  }

  /// 1.36.0: merkezi alıcı seçimine göre geçerli ayar. Bir tür için merkezi
  /// seçim varsa: alıcıysa ve kendisi kapatmadıysa alır. Merkezi seçim
  /// yoksa (sunucu eski) kişinin kendi ayarı geçerli.
  BildirimAyarlari merkezeGore(bool? Function(BildirimTuru t)? alici) {
    if (alici == null) return this;
    final gecerli = <BildirimTuru>{};
    for (final t in BildirimTuru.values) {
      final m = t.merkezi ? alici(t) : null;
      if (m == null) {
        if (acik.contains(t)) gecerli.add(t);
      } else if (m && !kapatilan.contains(t)) {
        gecerli.add(t);
      }
    }
    return BildirimAyarlari(
      acik: gecerli,
      kapatilan: kapatilan,
      servisGecikmeGun: servisGecikmeGun,
      garantiGun: garantiGun,
      izlenenDepolar: izlenenDepolar,
      ozetSaat: ozetSaat,
      ozetDakika: ozetDakika,
    );
  }

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
      final acikAdlar = {for (final x in (m['acik'] as List? ?? const [])) '$x'};
      // 1.36.0 öncesi kayıt: varsayılanı açık olup kapalı duran türler
      // kişinin kendisinin kapattıklarıdır.
      final kapatilanAdlar = m['kapatilan'] is List
          ? {for (final x in m['kapatilan'] as List) '$x'}
          : {
              for (final t in BildirimTuru.values)
                if (t.varsayilan &&
                    bilinen.contains(t.name) &&
                    !acikAdlar.contains(t.name))
                  t.name
            };
      return BildirimAyarlari(
        kapatilan: {
          for (final t in BildirimTuru.values)
            if (kapatilanAdlar.contains(t.name)) t
        },
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
        'kapatilan': [for (final t in kapatilan) t.name],
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
