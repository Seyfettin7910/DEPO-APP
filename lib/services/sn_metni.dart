/// Kamerada yazıdan okunan satırlardan seri numarasını ayıklar (Android,
/// "Yazıdan da oku"). Yalnızca etiketli satır alınır: "S/N", "SN", "S.N.",
/// "Serial No / Number", "Seri No". Etiket tek başına bir satırdaysa değer
/// alt satırdan alınır. Değer: harf / rakam (tire olabilir), en az 6 karakter,
/// en az bir rakam. Testleri: test/sn_metni_test.dart.
library;

// Yazı tanıma "/" işaretini çoğu zaman I, l, 1 ya da | okur; S'yi de 5.
const _etiket = r'(?:[S5]\s*[/|\\Il1]\s*N(?:\s*O\b)?|S\s*\.\s*N\s*\.?|SN(?=[\s:#.\-]|\d|$)'
    r'|SER(?:IAL|İAL|I|İ|ı)?\s*\.?\s*(?:NO|NUMBER|NUMARASI|N°|#)\.?)';

final _satirdaDeger = RegExp(
  '(?:^|[^A-Z0-9İ])$_etiket\\s*[:#.\\-]*\\s*([A-Z0-9][A-Z0-9\\-]{3,39})',
  caseSensitive: false,
);

final _yalnizEtiket = RegExp(
  '(?:^|[^A-Z0-9İ])$_etiket\\s*[:#.\\-]*\\s*\$',
  caseSensitive: false,
);

final _ilkParca = RegExp(r'^([A-Z0-9][A-Z0-9\-]{3,39})', caseSensitive: false);
final _rakam = RegExp(r'\d');

/// Etiketli satırdan seri no; bulunamazsa null.
String? snAyikla(List<String> satirlar) {
  for (var i = 0; i < satirlar.length; i++) {
    final satir = satirlar[i].trim();
    if (satir.isEmpty) continue;
    final m = _satirdaDeger.firstMatch(satir);
    if (m != null) {
      final d = _temizle(m.group(1)!);
      if (d != null) return d;
    }
    if (_yalnizEtiket.hasMatch(satir) && i + 1 < satirlar.length) {
      final alt = _ilkParca.firstMatch(satirlar[i + 1].trim());
      if (alt != null) {
        final d = _temizle(alt.group(1)!);
        if (d != null) return d;
      }
    }
  }
  return null;
}

String? _temizle(String ham) {
  var v = ham.toUpperCase();
  // Sondaki tire (satır sonu bölünmesi) atılır.
  while (v.endsWith('-')) {
    v = v.substring(0, v.length - 1);
  }
  if (v.length < 6 || !_rakam.hasMatch(v)) return null;
  return v;
}

// ---------------------------------------------------------------------------
// 1.33.0: etiketteki diğer kodlar ve barkod ↔ yazı eşleştirme
// ---------------------------------------------------------------------------

/// Etikette bir kodun yanındaki yazı: seri no mu, lot / malzeme / model mi?
enum EtiketKodTuru {
  seri('seri no'),
  lot('lot no'),
  malzeme('malzeme kodu'),
  model('model kodu');

  const EtiketKodTuru(this.ad);

  /// Ekrandaki ve sayımdaki adı ("Yok sayıldı: … (lot no)").
  final String ad;
}

// Lot / Batch No · Material Code / Mat. Code / P/N / Part No / Item No ·
// Model / Model No. (Yazı tanıma "/" yerine I, l, 1, | okuyabilir.)
const _lotEtiketi = r'(?:LOT|BATCH)\s*(?:NO|NUMBER|N°|#)?\.?';
const _malzemeEtiketi = r'(?:MATERIAL|MAT\.?)\s*(?:CODE|NO|NUMBER|#)\.?'
    r'|P\s*[/|\\Il1]\s*N(?:\s*O\b)?\.?'
    r'|PART\s*(?:NO|NUMBER|#)\.?|ITEM\s*(?:NO|CODE|#)\.?';
const _modelEtiketi = r'MODEL\s*(?:NO|NUMBER|#)?\.?';

RegExp _satirda(String etiket) => RegExp(
      '(?:^|[^A-Z0-9İ])(?:$etiket)\\s*[:#.\\-]*\\s*([A-Z0-9][A-Z0-9\\-]{2,39})',
      caseSensitive: false,
    );

RegExp _yalniz(String etiket) => RegExp(
      '(?:^|[^A-Z0-9İ])(?:$etiket)\\s*[:#.\\-]*\\s*\$',
      caseSensitive: false,
    );

final _digerEtiketler = <EtiketKodTuru, (RegExp, RegExp)>{
  EtiketKodTuru.lot: (_satirda(_lotEtiketi), _yalniz(_lotEtiketi)),
  EtiketKodTuru.malzeme: (_satirda(_malzemeEtiketi), _yalniz(_malzemeEtiketi)),
  EtiketKodTuru.model: (_satirda(_modelEtiketi), _yalniz(_modelEtiketi)),
};

/// Kamerada yazıdan okunan bir etiketin özeti: seri no ve yanındaki diğer
/// (seri olmayan) kodlar.
class EtiketOkumasi {
  const EtiketOkumasi(this.sn, this.digerleri);

  /// "SN:" / "S/N" yanındaki değer (yoksa null).
  final String? sn;

  /// Lot / malzeme / model kodları: değer → tür.
  final Map<String, EtiketKodTuru> digerleri;

  /// Barkoddan okunan [kod] etikette hangi yazının yanında? Bilinmiyorsa null.
  EtiketKodTuru? tur(String kod) {
    if (sn != null && ayniKod(kod, sn!)) return EtiketKodTuru.seri;
    for (final e in digerleri.entries) {
      if (ayniKod(kod, e.key)) return e.value;
    }
    return null;
  }
}

/// Satırlardan seri no ile lot / malzeme / model kodlarını çıkarır.
EtiketOkumasi etiketOku(List<String> satirlar) {
  final digerleri = <String, EtiketKodTuru>{};
  for (var i = 0; i < satirlar.length; i++) {
    final satir = satirlar[i].trim();
    if (satir.isEmpty) continue;
    for (final e in _digerEtiketler.entries) {
      final (ayni, yalniz) = e.value;
      for (final m in ayni.allMatches(satir)) {
        digerleri[_buyukSade(m.group(1)!)] = e.key;
      }
      if (yalniz.hasMatch(satir) && i + 1 < satirlar.length) {
        final alt = _ilkParca.firstMatch(satirlar[i + 1].trim());
        if (alt != null) digerleri[_buyukSade(alt.group(1)!)] = e.key;
      }
    }
  }
  return EtiketOkumasi(snAyikla(satirlar), digerleri);
}

String _buyukSade(String v) {
  var s = v.toUpperCase();
  while (s.endsWith('-')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// Karşılaştırma için sadeleştirilmiş kod: büyük harf, boşluksuz; yazı
/// tanımanın karıştırdığı harfler rakama çevrilir (O → 0, I / L → 1,
/// S → 5, B → 8, Z → 2). Yalnız eşleştirmede kullanılır; kaydedilen değer
/// her zaman barkodun kendisidir.
String eslesmeAnahtari(String kod) {
  const harita = {'O': '0', 'Q': '0', 'D': '0', 'I': '1', 'L': '1', '|': '1',
      'S': '5', 'B': '8', 'Z': '2'};
  final b = StringBuffer();
  for (final ch in kod.toUpperCase().split('')) {
    if (ch.trim().isEmpty) continue;
    b.write(harita[ch] ?? ch);
  }
  return b.toString();
}

/// Barkoddan okunan kod ile etiketteki yazı aynı mı? (Yazı tanımanın
/// karıştırdığı harfler ve boşluklar önemsenmez; en az 6 karakter.)
bool ayniKod(String barkod, String yazi) {
  final a = eslesmeAnahtari(barkod);
  return a.length >= 6 && a == eslesmeAnahtari(yazi);
}

/// 1.33.0: kayıtlı seriyle karşılaştırma anahtarı: büyük harf, boşluksuz,
/// baştaki "SN:", "S/N", "Serial No" öneki atılmış.
/// ("SN 3017 4162968" → "30174162968")
String seriAnahtari(String s) => s
    .toUpperCase()
    .replaceAll(RegExp(r'\s+'), '')
    .replaceFirst(
        RegExp(r'^(?:S/?N|SERIAL(?:NO|NUMBER)?|SERINO)[:#.\-]*'), '');
