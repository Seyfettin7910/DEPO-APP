/// Bölge (il / ilçe / mahalle) adları: Türkçe büyük / küçük harf ve
/// "Mahallesi / Mah. / Köyü" eklerinin atılması.
library;

/// Türkçe küçük harf (I → ı, İ → i).
String trKucuk(String s) =>
    s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

/// Türkçe büyük harf (i → İ, ı → I).
String trBuyuk(String s) =>
    s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

/// Bölge adını düzeltir: "Kulat" → "KULAT", "Sakarya Mahallesi" / "Sakarya
/// Mah." → "SAKARYA", "Kayalar Köyü" → "KAYALAR". Boşsa ''.
String bolgeAdiDuzelt(String? ad) {
  var t = (ad ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return '';
  t = t.replaceAll(
      RegExp(r'\s+(mahallesi|mahalle|mah\.?|köyü|köy|koyu|koy)$',
          caseSensitive: false),
      '');
  // "MAHALLESİ" gibi Türkçe büyük harfli ekler de (İ / I) atılsın.
  final kucuk = trKucuk(t);
  for (final ek in [' mahallesi', ' mahalle', ' mah.', ' mah', ' köyü', ' köy']) {
    if (kucuk.endsWith(ek)) {
      t = t.substring(0, t.length - ek.length).trimRight();
      break;
    }
  }
  // 1.29.1: her yerde büyük harf.
  return trBuyuk(t);
}


/// Montajda "Nerede kullanıldı?" için konumdan gelen yer: "SUSURLUK KULAT"
/// (ilçe + mahalle / köy, büyük harf). İkisi de yoksa ''.
String yerMetni(String? ilce, String? mahalle) => [
      bolgeAdiDuzelt(ilce),
      bolgeAdiDuzelt(mahalle),
    ].where((e) => e.isNotEmpty).map(trBuyuk).join(' ');
