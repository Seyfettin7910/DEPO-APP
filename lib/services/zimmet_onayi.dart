/// Belediye zimmeti (1.32.0, Seyfettin'in kararları 02.11.2026):
///
/// Belediye hizmetindeki ürünün **kırsal mahallede** kullanımı **Başkanlık
/// onayı** ister. Sert engel, mahalle listesi ya da konum hesabı yoktur; ayrım
/// ürünün bulunduğu **depo adına** göre yapılır (depo adları sabittir).
/// Ürün BELEDİYE ZİMMETİ deposundan montaja / kullanıma çıkarken sorulur:
///   * Belediye hizmet yerine takılıyor → kaydedilir.
///   * Kırsal mahalleye takılıyor, onay var → evrak sayısı ZORUNLU, kaydedilir.
///   * Kırsal mahalleye takılıyor, onay yok → kaydedilmez ("onay olmadan
///     kullanılamaz"); girişim kaydedilir, isteyen yöneticiye bildirim gider.
library;

/// Kullanım kaydındaki `zimmet_yeri` değerleri.
const zimmetYeriHizmet = 'hizmet';
const zimmetYeriKirsal = 'kirsal';

/// Raporlarda / geçmişte görünen adı.
String zimmetYeriAdi(String? yer) => switch (yer) {
      zimmetYeriHizmet => 'Belediye hizmet yeri',
      zimmetYeriKirsal => 'Kırsal mahalle (Başkanlık onaylı)',
      _ => '',
    };

/// Türkçe harfleri sadeleştirip büyütür ("Belediye  zimmeti" → "BELEDIYE ZIMMETI").
String _sade(String s) {
  const harita = {
    'İ': 'I', 'ı': 'I', 'i': 'I', 'Ş': 'S', 'ş': 'S', 'Ğ': 'G', 'ğ': 'G',
    'Ü': 'U', 'ü': 'U', 'Ö': 'O', 'ö': 'O', 'Ç': 'C', 'ç': 'C',
  };
  final b = StringBuffer();
  for (final ch in s.split('')) {
    b.write(harita[ch] ?? ch.toUpperCase());
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Bu depo "BELEDİYE ZİMMETİ" deposu mu? (Büyük / küçük harf, İ / I ve fazla
/// boşluk farkı önemsenmez; "BELEDİYE ZİMMETİ DEPOSU" gibi adlar da sayılır.)
bool zimmetDeposuMu(String? depoAdi) =>
    depoAdi != null && _sade(depoAdi).contains('BELEDIYE ZIMMET');

/// Montaj ekranında yapılan seçim.
class ZimmetSecimi {
  const ZimmetSecimi(this.yer, [this.evrakSayisi]);
  final String yer; // zimmetYeriHizmet | zimmetYeriKirsal
  final String? evrakSayisi; // kırsalda zorunlu
}

/// Kaydetmeden önceki denetim. Hata yoksa null. Veritabanı katmanı da aynı
/// kuralı uygular; ekran güncellenmese bile kural atlanamaz.
String? zimmetSecimiHatasi({
  required bool zimmet,
  String? yer,
  String? evrakSayisi,
}) {
  if (!zimmet) return null;
  if (yer != zimmetYeriHizmet && yer != zimmetYeriKirsal) {
    return 'Ürün Belediye Zimmeti deposunda: nereye takıldığını seçin '
        '(belediye hizmet yeri / kırsal mahalle)';
  }
  if (yer == zimmetYeriKirsal && (evrakSayisi ?? '').trim().isEmpty) {
    return 'Kırsal mahallede kullanım için Başkanlık onayının evrak '
        'sayısını yazın';
  }
  return null;
}

/// Onay yoksa gösterilen engel metni.
const zimmetEngelMetni =
    'Bu ürün kırsal mahallede Başkanlık onayı olmadan kullanılamaz.';
