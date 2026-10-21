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
