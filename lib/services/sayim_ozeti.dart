/// Sayımda model (ürün) bazında özet (1.34.0).
///
/// Sayım ekranındaki Eksik / Bulunan / Fazla listeleri ve sayım raporu
/// cihazları model başlıkları altında toplar; her başlıkta "olmalı /
/// bulunan / eksik / fazla" sayıları yazar. Eksiği en çok olan model en
/// üstte gelir. Testleri: test/sayim_ozeti_test.dart.
library;

import 'urun_adi.dart';

/// Fazla okutulan ama sistemde kayıtlı olmayan seri noların başlığı.
const sayimKayitsizBasligi = 'KAYITLI OLMAYAN SERİ NO';

class SayimGrubu {
  SayimGrubu(this.urunAdi);

  final String urunAdi;

  /// Bu konumda olması gereken seri nolar (sistemdeki sırasıyla).
  final olmali = <String>[];
  final bulunan = <String>[];
  final eksik = <String>[];

  /// Okutulan ama bu konumda olmayan seri nolar (okutma sırasıyla).
  final fazla = <String>[];

  /// Sayım bu modelde tamam: eksik ve fazla yok.
  bool get tamam => eksik.isEmpty && fazla.isEmpty;
}

/// [beklenen]: bu konumda olması gereken cihazlar (seri no, ürün adı).
/// [okunan]: okutulan seri no → sistemdeki ürün adı (kayıtsızsa null),
/// okutma sırasıyla.
List<SayimGrubu> sayimOzeti({
  required List<(String, String)> beklenen,
  required Map<String, String?> okunan,
}) {
  final gruplar = <String, SayimGrubu>{};
  SayimGrubu grup(String ad) => gruplar.putIfAbsent(ad, () => SayimGrubu(ad));

  final beklenenSeriler = <String>{};
  for (final (seri, urun) in beklenen) {
    beklenenSeriler.add(seri);
    final g = grup(urun)..olmali.add(seri);
    if (okunan.containsKey(seri)) {
      g.bulunan.add(seri);
    } else {
      g.eksik.add(seri);
    }
  }
  for (final e in okunan.entries) {
    if (beklenenSeriler.contains(e.key)) continue;
    grup(e.value ?? sayimKayitsizBasligi).fazla.add(e.key);
  }

  return gruplar.values.toList()
    ..sort((a, b) {
      // Önce eksiği çok olan, sonra fazlası çok olan, sonra ada göre.
      final e = b.eksik.length.compareTo(a.eksik.length);
      if (e != 0) return e;
      final f = b.fazla.length.compareTo(a.fazla.length);
      if (f != 0) return f;
      return trKarsilastir(a.urunAdi, b.urunAdi);
    });
}

/// Listede arama: seri no ya da model adı. Büyük / küçük harf, Türkçe harf,
/// boşluk ve noktalama farkı yok sayılır ("7104 poe" → "HIKVISION 7104 POE").
bool sayimAramaUyar(String sorgu, {required String seri, required String urun}) {
  final s = urunAdiAnahtari(sorgu);
  if (s.isEmpty) return true;
  return urunAdiAnahtari(seri).contains(s) || urunAdiAnahtari(urun).contains(s);
}
