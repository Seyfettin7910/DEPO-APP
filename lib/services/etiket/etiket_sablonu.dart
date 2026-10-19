import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Etiket kağıdı / rulo etiket ölçüleri (milimetre). Baskı yapılan
/// bilgisayarda saklanır (hizalama yazıcıya göre değişir).
class EtiketSablonu {
  const EtiketSablonu({
    required this.ad,
    this.rulo = false,
    this.sayfaGenislik = 210,
    this.sayfaYukseklik = 297,
    this.sutun = 3,
    this.satir = 8,
    this.ustKenar = 0.5,
    this.solKenar = 0,
    this.etiketGenislik = 70,
    this.etiketYukseklik = 37,
    this.yatayAra = 0,
    this.dikeyAra = 0,
    this.kaydirX = 0,
    this.kaydirY = 0,
    this.cizgiBarkod = true,
    this.kurumAdi = '',
  });

  final String ad;

  /// Rulo etiket (etiket yazıcısı): her sayfa tek etiket.
  final bool rulo;
  final double sayfaGenislik;
  final double sayfaYukseklik;
  final int sutun;
  final int satir;
  final double ustKenar;
  final double solKenar;
  final double etiketGenislik;
  final double etiketYukseklik;
  final double yatayAra;
  final double dikeyAra;

  /// Hizalama düzeltmesi: tüm baskıyı sağa (+) / sola (−), aşağı (+) /
  /// yukarı (−) kaydırır.
  final double kaydirX;
  final double kaydirY;

  /// Etikete çizgi barkod da basılsın mı (yer yeterliyse).
  final bool cizgiBarkod;

  /// Etiketin üstünde küçük yazı (ör. kurum adı). Boşsa basılmaz.
  final String kurumAdi;

  int get sayfadakiEtiket => rulo ? 1 : sutun * satir;

  String get olcuMetni {
    String f(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    final et = '${f(etiketGenislik)}×${f(etiketYukseklik)} mm';
    return rulo ? 'Rulo · $et' : 'A4 · $sutun×$satir · $et';
  }

  EtiketSablonu kopya({
    String? ad,
    bool? rulo,
    double? sayfaGenislik,
    double? sayfaYukseklik,
    int? sutun,
    int? satir,
    double? ustKenar,
    double? solKenar,
    double? etiketGenislik,
    double? etiketYukseklik,
    double? yatayAra,
    double? dikeyAra,
    double? kaydirX,
    double? kaydirY,
    bool? cizgiBarkod,
    String? kurumAdi,
  }) =>
      EtiketSablonu(
        ad: ad ?? this.ad,
        rulo: rulo ?? this.rulo,
        sayfaGenislik: sayfaGenislik ?? this.sayfaGenislik,
        sayfaYukseklik: sayfaYukseklik ?? this.sayfaYukseklik,
        sutun: sutun ?? this.sutun,
        satir: satir ?? this.satir,
        ustKenar: ustKenar ?? this.ustKenar,
        solKenar: solKenar ?? this.solKenar,
        etiketGenislik: etiketGenislik ?? this.etiketGenislik,
        etiketYukseklik: etiketYukseklik ?? this.etiketYukseklik,
        yatayAra: yatayAra ?? this.yatayAra,
        dikeyAra: dikeyAra ?? this.dikeyAra,
        kaydirX: kaydirX ?? this.kaydirX,
        kaydirY: kaydirY ?? this.kaydirY,
        cizgiBarkod: cizgiBarkod ?? this.cizgiBarkod,
        kurumAdi: kurumAdi ?? this.kurumAdi,
      );

  /// Ölçüler sayfaya sığıyor mu? Sığmıyorsa açıklama döner.
  String? hata() {
    if (etiketGenislik < 15 || etiketYukseklik < 10) {
      return 'Etiket en az 15×10 mm olmalı';
    }
    if (rulo) return null;
    if (sutun < 1 || satir < 1) return 'Sütun ve satır en az 1 olmalı';
    final g = solKenar + sutun * etiketGenislik + (sutun - 1) * yatayAra;
    final y = ustKenar + satir * etiketYukseklik + (satir - 1) * dikeyAra;
    if (g > sayfaGenislik + 0.5) {
      return 'Etiketler sayfa genişliğini aşıyor (${g.toStringAsFixed(1)} mm)';
    }
    if (y > sayfaYukseklik + 0.5) {
      return 'Etiketler sayfa yüksekliğini aşıyor (${y.toStringAsFixed(1)} mm)';
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'ad': ad,
        'rulo': rulo,
        'sayfaGenislik': sayfaGenislik,
        'sayfaYukseklik': sayfaYukseklik,
        'sutun': sutun,
        'satir': satir,
        'ustKenar': ustKenar,
        'solKenar': solKenar,
        'etiketGenislik': etiketGenislik,
        'etiketYukseklik': etiketYukseklik,
        'yatayAra': yatayAra,
        'dikeyAra': dikeyAra,
        'kaydirX': kaydirX,
        'kaydirY': kaydirY,
        'cizgiBarkod': cizgiBarkod,
        'kurumAdi': kurumAdi,
      };

  factory EtiketSablonu.fromJson(Map<String, dynamic> m) {
    double d(String k, double v) => (m[k] as num?)?.toDouble() ?? v;
    return EtiketSablonu(
      ad: (m['ad'] as String?) ?? 'Özel',
      rulo: m['rulo'] == true,
      sayfaGenislik: d('sayfaGenislik', 210),
      sayfaYukseklik: d('sayfaYukseklik', 297),
      sutun: (m['sutun'] as num?)?.toInt() ?? 3,
      satir: (m['satir'] as num?)?.toInt() ?? 8,
      ustKenar: d('ustKenar', 0),
      solKenar: d('solKenar', 0),
      etiketGenislik: d('etiketGenislik', 70),
      etiketYukseklik: d('etiketYukseklik', 37),
      yatayAra: d('yatayAra', 0),
      dikeyAra: d('dikeyAra', 0),
      kaydirX: d('kaydirX', 0),
      kaydirY: d('kaydirY', 0),
      cizgiBarkod: m['cizgiBarkod'] != false,
      kurumAdi: (m['kurumAdi'] as String?) ?? '',
    );
  }

  static const _anahtar = 'etiket_sablonu';

  static Future<EtiketSablonu> yukle() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_anahtar);
      if (s != null) {
        return EtiketSablonu.fromJson(jsonDecode(s) as Map<String, dynamic>);
      }
    } catch (_) {}
    return hazirlar.first;
  }

  Future<void> kaydet() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_anahtar, jsonEncode(toJson()));
    } catch (_) {}
  }

  /// Yaygın A4 etiket kağıtları ve rulo etiket ölçüleri. Kağıdın paketinde
  /// yazan ölçüler farklıysa "Özel ölçü" ile düzeltilir.
  static const hazirlar = <EtiketSablonu>[
    EtiketSablonu(
        ad: 'A4 · 3×8 (70×37 mm)',
        sutun: 3, satir: 8, etiketGenislik: 70, etiketYukseklik: 37,
        ustKenar: 0.5, solKenar: 0),
    EtiketSablonu(
        ad: 'A4 · 3×7 (70×42,3 mm)',
        sutun: 3, satir: 7, etiketGenislik: 70, etiketYukseklik: 42.3,
        ustKenar: 0.45, solKenar: 0),
    EtiketSablonu(
        ad: 'A4 · 3×7 (63,5×38,1 mm)',
        sutun: 3, satir: 7, etiketGenislik: 63.5, etiketYukseklik: 38.1,
        ustKenar: 15.15, solKenar: 7.2, yatayAra: 2.5),
    EtiketSablonu(
        ad: 'A4 · 2×7 (99,1×38,1 mm)',
        sutun: 2, satir: 7, etiketGenislik: 99.1, etiketYukseklik: 38.1,
        ustKenar: 15.15, solKenar: 4.65, yatayAra: 2.5),
    EtiketSablonu(
        ad: 'A4 · 4×10 (48,5×25,4 mm)',
        sutun: 4, satir: 10, etiketGenislik: 48.5, etiketYukseklik: 25.4,
        ustKenar: 21.5, solKenar: 8),
    EtiketSablonu(
        ad: 'A4 · 5×13 (38,1×21,2 mm)',
        sutun: 5, satir: 13, etiketGenislik: 38.1, etiketYukseklik: 21.2,
        ustKenar: 10.7, solKenar: 4.75, yatayAra: 2.5),
    EtiketSablonu(
        ad: 'Rulo · 50×30 mm', rulo: true,
        etiketGenislik: 50, etiketYukseklik: 30,
        sayfaGenislik: 50, sayfaYukseklik: 30, sutun: 1, satir: 1),
    EtiketSablonu(
        ad: 'Rulo · 40×25 mm', rulo: true,
        etiketGenislik: 40, etiketYukseklik: 25,
        sayfaGenislik: 40, sayfaYukseklik: 25, sutun: 1, satir: 1),
    EtiketSablonu(
        ad: 'Rulo · 58×40 mm', rulo: true,
        etiketGenislik: 58, etiketYukseklik: 40,
        sayfaGenislik: 58, sayfaYukseklik: 40, sutun: 1, satir: 1),
    EtiketSablonu(
        ad: 'Rulo · 100×50 mm', rulo: true,
        etiketGenislik: 100, etiketYukseklik: 50,
        sayfaGenislik: 100, sayfaYukseklik: 50, sutun: 1, satir: 1),
  ];
}
