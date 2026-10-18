/// Tüm raporların ortak yapısı. Aynı [Rapor] nesnesi uygulama içinde
/// önizlenir, PDF'e ve Excel'e dökülür; böylece üç görünümde de başlıklar,
/// sütunlar ve satırlar birebir aynıdır.
class Rapor {
  const Rapor({
    required this.baslik,
    required this.altBaslik,
    required this.sutunlar,
    required this.genislikler,
    required this.bolumler,
    required this.dosyaOn,
    this.ozet = const [],
  });

  /// Örn. "Ürünler Raporu"
  final String baslik;

  /// Örn. tarih aralığı veya oluşturma tarihi.
  final String altBaslik;

  /// Bölümler kendi sütunlarını vermezse kullanılan sütunlar.
  final List<String> sutunlar;

  /// Sütunların göreli genişlikleri (PDF'te oran, Excel'de karakter).
  final List<double> genislikler;

  /// Raporun başındaki özet kutuları (etiket → değer).
  final List<MapEntry<String, String>> ozet;

  final List<RaporBolumu> bolumler;

  /// Dosya adının başı (örn. "urunler_raporu").
  final String dosyaOn;

  int get toplamSatir => bolumler.fold(0, (t, b) => t + b.satirlar.length);

  /// Çok sütunlu raporlar PDF'te yatay sayfaya basılır.
  bool get yatay =>
      [sutunlar.length, ...bolumler.map((b) => b.sutunlar?.length ?? 0)]
          .any((n) => n > 6);
}

class RaporBolumu {
  const RaporBolumu({
    this.baslik,
    this.aciklama,
    this.sutunlar,
    this.genislikler,
    required this.satirlar,
  });

  final String? baslik;
  final String? aciklama;

  /// null ise raporun sütunları kullanılır.
  final List<String>? sutunlar;
  final List<double>? genislikler;

  /// Hücreler: String veya int (Excel'de sayı olarak yazılır).
  final List<List<Object?>> satirlar;

  List<String> sutunlariAl(Rapor r) => sutunlar ?? r.sutunlar;
  List<double> genislikleriAl(Rapor r) => genislikler ?? r.genislikler;
}
