/// Genel sayım (1.35.0): her depo / araç ayrı sayılır, "Bitir"de sonuç
/// kaydedilir (sayimlar tablosu). Raporlar → "Genel sayım" seçilen tarih
/// aralığındaki sayımları tek raporda birleştirir:
///  - her yerin son sayımı (aynı yer birden çok sayıldıysa sonuncusu),
///  - sayılmamış yerler,
///  - bir yerde fazla çıkıp sistemde başka yerde görünen cihazlar
///    "yeri yanlış kayıtlı" sayılır, kendi yerinde eksik çıkmışlarsa oradaki
///    eksikten düşülür (kayıp değildir),
///  - model bazında özet.
/// Testleri: test/genel_sayim_test.dart.
library;

import 'dart:convert';

import 'sayim_ozeti.dart';
import 'urun_adi.dart';

/// Sayımda fazla çıkan cihaz: seri no, sistemdeki ürün adı (kayıtsızsa
/// null), sistemde nerede göründüğü ("Sistemde: ANA DEPO" gibi).
typedef SayimFazlasi = (String seri, String? urun, String sistemdekiYer);

/// Miktarlı malzeme: ad, birim, sistemdeki miktar, sayılan (sayılmadıysa null).
typedef SayimMalzemesi = (String ad, String birim, int sistemde, int? sayilan);

/// Kaydedilmiş bir sayımın içeriği (sayimlar.icerik JSON'u).
class SayimIcerigi {
  const SayimIcerigi({
    this.bulunan = const [],
    this.eksik = const [],
    this.fazla = const [],
    this.malzeme = const [],
  });

  /// (seri no, ürün adı)
  final List<(String, String)> bulunan;
  final List<(String, String)> eksik;
  final List<SayimFazlasi> fazla;
  final List<SayimMalzemesi> malzeme;

  String json() => jsonEncode({
        'bulunan': [for (final (s, u) in bulunan) [s, u]],
        'eksik': [for (final (s, u) in eksik) [s, u]],
        'fazla': [for (final (s, u, y) in fazla) [s, u, y]],
        'malzeme': [for (final (a, b, si, sa) in malzeme) [a, b, si, sa]],
      });

  /// Bozuk ya da boş içerik çökertmez; boş sayım döner.
  factory SayimIcerigi.coz(String? metin) {
    if (metin == null || metin.isEmpty) return const SayimIcerigi();
    try {
      final m = jsonDecode(metin) as Map<String, dynamic>;
      List<List<dynamic>> liste(String k) =>
          [for (final x in (m[k] as List? ?? const [])) if (x is List) x];
      String yazi(Object? v) => v == null ? '' : '$v';
      int sayi(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
      return SayimIcerigi(
        bulunan: [
          for (final x in liste('bulunan'))
            if (x.length >= 2) (yazi(x[0]), yazi(x[1])),
        ],
        eksik: [
          for (final x in liste('eksik'))
            if (x.length >= 2) (yazi(x[0]), yazi(x[1])),
        ],
        fazla: [
          for (final x in liste('fazla'))
            if (x.length >= 3) (yazi(x[0]), x[1] as String?, yazi(x[2])),
        ],
        malzeme: [
          for (final x in liste('malzeme'))
            if (x.length >= 4)
              (yazi(x[0]), yazi(x[1]), sayi(x[2]), x[3] == null ? null : sayi(x[3])),
        ],
      );
    } catch (_) {
      return const SayimIcerigi();
    }
  }
}

/// Bir yerin kaydedilmiş sayımı.
class SayimKaydi {
  const SayimKaydi({
    required this.depoId,
    required this.depoAdi,
    required this.tarih,
    this.kullanici,
    required this.icerik,
  });

  final String depoId;
  final String depoAdi;

  /// Sayımın bittiği an (Bitir).
  final DateTime tarih;
  final String? kullanici;
  final SayimIcerigi icerik;
}

/// Sayılması gereken yer (depo / araç).
typedef SayimYeri = (String id, String ad, bool arac);

/// Bir yerin genel sayımdaki satırı. [kayit] null ise yer sayılmadı.
class GenelSayimYeri {
  GenelSayimYeri(this.yer, this.kayit);
  final SayimYeri yer;
  final SayimKaydi? kayit;

  /// Bu yerde eksik çıkıp başka yerde bulunan (eksikten düşülen) cihazlar.
  int baskaYerdeBulunan = 0;

  int get olmali =>
      (kayit?.icerik.bulunan.length ?? 0) + (kayit?.icerik.eksik.length ?? 0);
  int get bulunan => kayit?.icerik.bulunan.length ?? 0;
  int get eksik => (kayit?.icerik.eksik.length ?? 0) - baskaYerdeBulunan;
  int get fazla => kayit?.icerik.fazla.length ?? 0;
}

/// Yeri yanlış kayıtlı cihaz: [bulunduguYer]'de okutuldu ama sistemde
/// başka yerde / durumda görünüyor. [kendiYerindeEksik]: sistemdeki yerin
/// sayımında eksik çıkmıştı (eşleşti).
class YeriYanlisCihaz {
  const YeriYanlisCihaz({
    required this.seri,
    required this.urun,
    required this.bulunduguYer,
    required this.sistemdekiYer,
    required this.kendiYerindeEksik,
  });
  final String seri;
  final String urun;
  final String bulunduguYer;
  final String sistemdekiYer;
  final bool kendiYerindeEksik;
}

/// Model özeti satırı.
class GenelSayimModeli {
  GenelSayimModeli(this.urun);
  final String urun;
  int olmali = 0;
  int bulunan = 0;
  int eksik = 0;
  int yeriYanlis = 0;
}

class GenelSayimSonucu {
  GenelSayimSonucu({
    required this.yerler,
    required this.eksikler,
    required this.yeriYanlis,
    required this.kayitsizlar,
    required this.modeller,
    required this.malzemeFarklari,
  });

  /// Sayılan yerler önce (yer adına göre), sonra sayılmayanlar.
  final List<GenelSayimYeri> yerler;

  /// Hiçbir yerde bulunamayan cihazlar: (seri, ürün, yer).
  final List<(String, String, String)> eksikler;
  final List<YeriYanlisCihaz> yeriYanlis;

  /// Sistemde hiç kaydı olmayan okutmalar: (seri, bulunduğu yer).
  final List<(String, String)> kayitsizlar;

  /// Eksiği çok olan model üstte.
  final List<GenelSayimModeli> modeller;

  /// Sayılan miktarı sistemdekinden farklı malzemeler:
  /// (yer, malzeme, birim, sistemde, sayılan).
  final List<(String, String, String, int, int)> malzemeFarklari;

  int get sayilanYer => yerler.where((y) => y.kayit != null).length;
  int get olmali => yerler.fold(0, (t, y) => t + y.olmali);
  int get bulunan => yerler.fold(0, (t, y) => t + y.bulunan);
}

/// [kayitlar]: tarih aralığındaki bütün sayımlar (sıra önemsiz).
/// [yerler]: sayılması gereken bütün depo ve araçlar (silinmemiş).
/// Listede olmayan bir yerin sayımı da (sonradan silinmiş depo) gösterilir.
GenelSayimSonucu genelSayim({
  required List<SayimKaydi> kayitlar,
  required List<SayimYeri> yerler,
}) {
  // Her yerin son sayımı.
  final son = <String, SayimKaydi>{};
  for (final k in kayitlar) {
    final o = son[k.depoId];
    if (o == null || k.tarih.isAfter(o.tarih)) son[k.depoId] = k;
  }

  final satirlar = <String, GenelSayimYeri>{};
  for (final y in yerler) {
    satirlar[y.$1] = GenelSayimYeri(y, son[y.$1]);
  }
  for (final k in son.values) {
    satirlar.putIfAbsent(
        k.depoId, () => GenelSayimYeri((k.depoId, k.depoAdi, false), k));
  }

  // Bir yerde eksik çıkan seri no → o yer.
  final eksikYeri = <String, GenelSayimYeri>{};
  for (final s in satirlar.values) {
    for (final (seri, _) in s.kayit?.icerik.eksik ?? const <(String, String)>[]) {
      eksikYeri[seri] = s;
    }
  }

  // Fazlalar: kayıtsız / yeri yanlış. Aynı seri birden çok yerde fazla
  // çıktıysa en son sayılan yerdeki geçerli.
  final fazlalar = <String, (SayimFazlasi, GenelSayimYeri)>{};
  for (final s in satirlar.values) {
    for (final f in s.kayit?.icerik.fazla ?? const <SayimFazlasi>[]) {
      final o = fazlalar[f.$1];
      if (o == null || s.kayit!.tarih.isAfter(o.$2.kayit!.tarih)) {
        fazlalar[f.$1] = (f, s);
      }
    }
  }
  final kayitsizlar = <(String, String)>[];
  final yeriYanlis = <YeriYanlisCihaz>[];
  final bulunanEksikler = <String>{};
  for (final (f, s) in fazlalar.values) {
    final (seri, urun, sistemdekiYer) = f;
    if (urun == null) {
      kayitsizlar.add((seri, s.yer.$2));
      continue;
    }
    final kendi = eksikYeri[seri];
    final eslesti = kendi != null && kendi != s;
    if (eslesti) {
      kendi.baskaYerdeBulunan++;
      bulunanEksikler.add(seri);
    }
    yeriYanlis.add(YeriYanlisCihaz(
      seri: seri,
      urun: urun,
      bulunduguYer: s.yer.$2,
      sistemdekiYer: sistemdekiYer,
      kendiYerindeEksik: eslesti,
    ));
  }

  // Gerçek eksikler ve model özeti.
  final eksikler = <(String, String, String)>[];
  final modeller = <String, GenelSayimModeli>{};
  GenelSayimModeli model(String u) =>
      modeller.putIfAbsent(u, () => GenelSayimModeli(u));
  final malzemeFarklari = <(String, String, String, int, int)>[];
  for (final s in satirlar.values) {
    final k = s.kayit;
    if (k == null) continue;
    for (final (_, u) in k.icerik.bulunan) {
      model(u)
        ..olmali += 1
        ..bulunan += 1;
    }
    for (final (seri, u) in k.icerik.eksik) {
      final m = model(u)..olmali += 1;
      if (bulunanEksikler.contains(seri)) continue;
      m.eksik += 1;
      eksikler.add((seri, u, s.yer.$2));
    }
    for (final (ad, birim, sistemde, sayilan) in k.icerik.malzeme) {
      if (sayilan != null && sayilan != sistemde) {
        malzemeFarklari.add((s.yer.$2, ad, birim, sistemde, sayilan));
      }
    }
  }
  for (final y in yeriYanlis) {
    model(y.urun).yeriYanlis += 1;
  }

  int yerSirasi(GenelSayimYeri a, GenelSayimYeri b) {
    final s = (a.kayit == null ? 1 : 0).compareTo(b.kayit == null ? 1 : 0);
    if (s != 0) return s;
    final t = (a.yer.$3 ? 1 : 0).compareTo(b.yer.$3 ? 1 : 0);
    return t != 0 ? t : trKarsilastir(a.yer.$2, b.yer.$2);
  }

  eksikler.sort((a, b) {
    final y = trKarsilastir(a.$3, b.$3);
    if (y != 0) return y;
    final u = trKarsilastir(a.$2, b.$2);
    return u != 0 ? u : a.$1.compareTo(b.$1);
  });
  yeriYanlis.sort((a, b) {
    final u = trKarsilastir(a.urun, b.urun);
    return u != 0 ? u : a.seri.compareTo(b.seri);
  });
  kayitsizlar.sort((a, b) {
    final y = trKarsilastir(a.$2, b.$2);
    return y != 0 ? y : a.$1.compareTo(b.$1);
  });

  return GenelSayimSonucu(
    yerler: satirlar.values.toList()..sort(yerSirasi),
    eksikler: eksikler,
    yeriYanlis: yeriYanlis,
    kayitsizlar: kayitsizlar,
    modeller: modeller.values.toList()
      ..sort((a, b) {
        final e = b.eksik.compareTo(a.eksik);
        if (e != 0) return e;
        final y = b.yeriYanlis.compareTo(a.yeriYanlis);
        return y != 0 ? y : trKarsilastir(a.urun, b.urun);
      }),
    malzemeFarklari: malzemeFarklari,
  );
}

/// Sayım ekranındaki gruplardan kaydedilecek içerik.
SayimIcerigi sayimIcerigi({
  required List<SayimGrubu> gruplar,
  required String Function(String seri) sistemdekiYer,
  List<SayimMalzemesi> malzeme = const [],
}) =>
    SayimIcerigi(
      bulunan: [
        for (final g in gruplar)
          for (final s in g.bulunan) (s, g.urunAdi),
      ],
      eksik: [
        for (final g in gruplar)
          for (final s in g.eksik) (s, g.urunAdi),
      ],
      fazla: [
        for (final g in gruplar)
          for (final s in g.fazla)
            (
              s,
              g.urunAdi == sayimKayitsizBasligi ? null : g.urunAdi,
              sistemdekiYer(s),
            ),
      ],
      malzeme: malzeme,
    );
