import 'dart:math';

/// Kurum etiketi kodu: `KURUM-XXXXXXXX`
///
/// - KURUM: ayarlardan tanımlanan kurum kodu (ör. BLD, BLD-BIM).
/// - XXXXXXXX: 7 rastgele karakter + 1 kontrol karakteri.
///
/// Karıştırılan karakterler (0/O, 1/I/L) kullanılmaz. Kontrol karakteri tek
/// karakter hatalarını ve yan yana iki karakterin yer değiştirmesini yakalar;
/// yanlış okunan veya elle yanlış yazılan kod geçersiz sayılır.
class EtiketKodu {
  EtiketKodu._();

  /// 31 karakter (asal sayı: kontrol karakteri için).
  static const alfabe = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  static const _govdeUzunluk = 7;
  static final _rastgele = Random.secure();

  /// Kurum kodu biçimi: büyük harf / rakam grupları, aralarında tire.
  static final kurumKoduDeseni = RegExp(r'^[A-Z0-9]{1,8}(-[A-Z0-9]{1,8}){0,2}$');

  /// Kullanıcının yazdığı kurum kodunu düzenler (Türkçe harfleri çevirir,
  /// boşlukları tireye dönüştürür). Geçersizse null.
  static String? kurumKoduDuzenle(String ham) {
    const tr = {
      'Ç': 'C', 'Ğ': 'G', 'İ': 'I', 'I': 'I', 'Ö': 'O', 'Ş': 'S', 'Ü': 'U',
      'ç': 'C', 'ğ': 'G', 'ı': 'I', 'i': 'I', 'ö': 'O', 'ş': 'S', 'ü': 'U',
    };
    final b = StringBuffer();
    for (final c in ham.trim().split('')) {
      b.write(tr[c] ?? c.toUpperCase());
    }
    final s = b
        .toString()
        .replaceAll(RegExp(r'[\s_./]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    if (s.isEmpty || s.length > 16 || !kurumKoduDeseni.hasMatch(s)) return null;
    return s;
  }

  static int _kontrol(String govde) {
    var t = 0;
    for (var i = 0; i < govde.length; i++) {
      t += (i + 1) * alfabe.indexOf(govde[i]);
    }
    return t % alfabe.length;
  }

  /// Yeni (rastgele) kod üretir. Benzersizlik veritabanında ayrıca denetlenir.
  static String uret(String kurumKodu) {
    final b = StringBuffer();
    for (var i = 0; i < _govdeUzunluk; i++) {
      b.write(alfabe[_rastgele.nextInt(alfabe.length)]);
    }
    final govde = b.toString();
    return '$kurumKodu-$govde${alfabe[_kontrol(govde)]}';
  }

  /// Kod kurum etiketi biçiminde ve kontrol karakteri doğru mu?
  static bool gecerliMi(String kod) {
    final k = kod.trim().toUpperCase();
    final i = k.lastIndexOf('-');
    if (i <= 0) return false;
    final son = k.substring(i + 1);
    if (son.length != _govdeUzunluk + 1) return false;
    for (final c in son.split('')) {
      if (!alfabe.contains(c)) return false;
    }
    final govde = son.substring(0, _govdeUzunluk);
    return alfabe[_kontrol(govde)] == son[_govdeUzunluk] &&
        kurumKoduDeseni.hasMatch(k.substring(0, i));
  }

  // -------------------------------------------------------------------
  // Etiketteki karekodun içeriği
  // -------------------------------------------------------------------

  static const _on = 'DOS1*';

  /// Karekoda yazılan metin: kod, etiket sürümü ve cihazın seri numarası.
  /// Uygulama bunu kendi etiketi olarak tanır (koli karekoduyla karışmaz) ve
  /// internet olmadan da etiketin hangi cihaza ait olduğunu bilir.
  static String karekodIcerigi(String kod, int surum, String seriNo) =>
      '$_on$kod*$surum*$seriNo';

  /// Okunan değer kurum etiketiyse çözer: karekod (kod + sürüm + seri no)
  /// veya çizgi barkod / elle yazılmış kod (yalnızca kod). Değilse null.
  static EtiketOkuma? coz(String ham) {
    final s = ham.trim();
    if (s.toUpperCase().startsWith(_on)) {
      final parca = s.substring(_on.length).split('*');
      if (parca.length < 3) return null;
      final kod = parca[0].trim().toUpperCase();
      final surum = int.tryParse(parca[1].trim());
      final seri = parca.sublist(2).join('*').trim().toUpperCase();
      if (kod.isEmpty) return null;
      return EtiketOkuma(kod: kod, surum: surum, seriNo: seri.isEmpty ? null : seri);
    }
    if (gecerliMi(s)) return EtiketOkuma(kod: s.toUpperCase());
    return null;
  }
}

/// Okutulan kurum etiketinin içeriği.
class EtiketOkuma {
  const EtiketOkuma({required this.kod, this.surum, this.seriNo});

  final String kod;

  /// Yalnızca karekodda bulunur (çizgi barkodda yok).
  final int? surum;
  final String? seriNo;

  bool get karekod => surum != null;
}
