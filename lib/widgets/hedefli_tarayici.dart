import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/etiket/etiket_kodu.dart';
import 'kod_yardimci.dart';

/// Hedef çerçevenin şekli: ince-uzun (çizgi barkod) veya kare (karekod).
enum TaramaModu { barkod, karekod }

/// Kamera görüntüsünde yalnızca ortadaki hedef çerçevenin İÇİNDEKİ kodu
/// okur. Etikette seri no barkodunun yanında başka barkodlar ve karekodlar
/// olsa bile, sadece çerçeveye alınan kod dikkate alınır.
///
/// - Sağ üstteki düğmeyle çerçeve "Barkod" (ince-uzun) ve "Karekod" (kare)
///   arasında değiştirilir; seçim telefonda hatırlanır.
/// - Görüntüye dokununca kamera çerçevenin ortasına yeniden netler; kod
///   okunmadığı sürece birkaç saniyede bir kendiliğinden de netler.
/// - İki parmakla yakınlaştırılabilir (telefonu çok yaklaştırınca kamera
///   netleyemez; uzaktan yakınlaştırmak daha iyi sonuç verir).
/// - Uygulama arka plana gidince kamera durur; dönünce, ekran hâlâ öndeyse
///   yeniden açılır.
/// - Yanlış okumayı önlemek için:
///   * kamera açılınca ilk 0,8 sn hiçbir şey okunmaz (telefon kaldırılırken
///     etraftaki kodlar okunmasın),
///   * çerçevede birden çok kod varsa ortaya en yakın olanı alınır,
///   * web adresi, Wi-Fi, MAC adresi, kutu üstündeki ürün barkodu (EAN/UPC)
///     gibi seri no olamayacak kodlar yok sayılır,
///   * kod ancak çerçevede bir süre sabit durursa okunur (kurum etiketi,
///     koli karekodu ve kayıtlı kodlarda kısa, bilinmeyen kodda uzun);
///     çerçevenin altındaki çubuk dolunca okunur.
class HedefliTarayici extends StatefulWidget {
  const HedefliTarayici({
    super.key,
    required this.controller,
    required this.onDetect,
    this.mod,
    this.urunBarkodu = false,
    this.bilinenMi,
  });

  final MobileScannerController controller;
  final void Function(BarcodeCapture capture) onDetect;

  /// Verilirse çerçeve bu modda açılır (ör. etiket doğrulamada önce karekod,
  /// sonra çizgi barkod). Kullanıcı yine de değiştirebilir.
  final TaramaModu? mod;

  /// true: kutu üstündeki ürün barkodları (EAN / UPC) da okunur (malzemenin
  /// fabrika barkodunu okuturken).
  final bool urunBarkodu;

  /// Verilirse: kod sistemde kayıtlı mı (seri no / malzeme barkodu)?
  /// Kayıtlıysa kısa, değilse uzun süre sabit durması beklenir. Kayıtlı
  /// malzeme barkodu (EAN / UPC) da bu sayede okunur.
  final Future<bool> Function(String kod)? bilinenMi;

  @override
  State<HedefliTarayici> createState() => _HedefliTarayiciState();
}

class _HedefliTarayiciState extends State<HedefliTarayici>
    with WidgetsBindingObserver {
  static const _anahtar = 'tarama_modu';
  TaramaModu _mod = TaramaModu.barkod;

  Timer? _netleme;
  DateTime _sonOkuma = DateTime.fromMillisecondsSinceEpoch(0);
  double _zoom = 0;
  double _zoomBaslangic = 0;
  bool _netleniyor = false;

  // Sabit durma (kilitlenme) beklemesi
  static const _acilisBeklemesi = Duration(milliseconds: 800);
  static const _kisaBekleme = Duration(milliseconds: 400);
  static const _uzunBekleme = Duration(milliseconds: 1000);
  static const _kayipSuresi = Duration(milliseconds: 700);

  DateTime _hazir = DateTime.now().add(_acilisBeklemesi);
  String? _aday; // çerçevede sabit durması beklenen kod
  Barcode? _adayKod;
  DateTime _adayBaslangic = DateTime.now();
  Duration _adayBekleme = _kisaBekleme;
  String? _okunan; // en son okunan (gönderilen) kod
  DateTime _okunmaZamani = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _kayip;
  final _bilinenler = <String, bool>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_kameraDinle);
    if (widget.mod != null) {
      _mod = widget.mod!;
    } else {
      _moduYukle();
    }
    if (!kIsWeb) {
      // Kod okunmadığı sürece ara ara ortaya netle (bazı telefonlarda
      // sürekli otomatik netleme yakın mesafede takılı kalıyor).
      _netleme = Timer.periodic(const Duration(seconds: 4), (_) {
        if (DateTime.now().difference(_sonOkuma) > const Duration(seconds: 4)) {
          _ortayaNetle(goster: false);
        }
      });
    }
  }

  @override
  void didUpdateWidget(HedefliTarayici eski) {
    super.didUpdateWidget(eski);
    if (widget.mod != null && widget.mod != eski.mod) {
      setState(() => _mod = widget.mod!);
    }
    if (widget.controller != eski.controller) {
      eski.controller.removeListener(_kameraDinle);
      widget.controller.addListener(_kameraDinle);
    }
  }

  @override
  void dispose() {
    _netleme?.cancel();
    _kayip?.cancel();
    widget.controller.removeListener(_kameraDinle);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = widget.controller;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(c.stop().catchError((_) {}));
    } else if (state == AppLifecycleState.resumed) {
      // Üstte başka bir sayfa açıksa kamera o sayfanındır; burası açılmaz.
      final onde = ModalRoute.of(context)?.isCurrent ?? true;
      if (onde && mounted) {
        _hazir = DateTime.now().add(_acilisBeklemesi);
        unawaited(c.start().catchError((_) {}));
      }
    }
  }

  Future<void> _moduYukle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final kayitli = prefs.getString(_anahtar);
      if (kayitli == TaramaModu.karekod.name && mounted) {
        setState(() => _mod = TaramaModu.karekod);
      }
    } catch (_) {}
  }

  Future<void> _modDegistir() async {
    final yeni =
        _mod == TaramaModu.barkod ? TaramaModu.karekod : TaramaModu.barkod;
    setState(() => _mod = yeni);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_anahtar, yeni.name);
    } catch (_) {}
  }

  Future<void> _ortayaNetle({bool goster = true}) async {
    if (kIsWeb || !widget.controller.value.isRunning) return;
    if (goster && mounted) setState(() => _netleniyor = true);
    try {
      await widget.controller.setFocusPoint(const Offset(0.5, 0.5));
    } catch (_) {}
    if (goster) {
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) setState(() => _netleniyor = false);
    }
  }

  Future<void> _zoomAyarla(double z) async {
    final yeni = z.clamp(0.0, 1.0);
    if ((yeni - _zoom).abs() < 0.01) return;
    _zoom = yeni;
    if (mounted) setState(() {});
    try {
      await widget.controller.setZoomScale(yeni);
    } catch (_) {}
  }

  /// Görüntü alanına göre hedef çerçeve.
  Rect _pencere(Size alan) {
    final merkez = Offset(alan.width / 2, alan.height / 2);
    if (_mod == TaramaModu.barkod) {
      // İnce şerit: yalnızca seri no barkodu sığsın, yandakiler girmesin.
      final g = math.min(alan.width * 0.70, 440.0);
      final y = math.min(math.max(alan.height * 0.18, 56.0), 104.0);
      return Rect.fromCenter(center: merkez, width: g, height: y);
    }
    // Karekod (koli karekodu dahil) için kare.
    final k = math.min(
        math.min(alan.width * 0.62, alan.height * 0.72), 320.0);
    return Rect.fromCenter(center: merkez, width: k, height: k);
  }

  /// Kodun ekrandaki merkezi (önizleme "cover" ile sığdırılır); hesaplanamazsa
  /// null.
  Offset? _merkez(Barcode b, Size goruntu, Size alan) {
    if (b.corners.isEmpty || goruntu.width <= 0 || goruntu.height <= 0) {
      return null;
    }
    final olcek = math.max(
        alan.width / goruntu.width, alan.height / goruntu.height);
    final dx = (alan.width - goruntu.width * olcek) / 2;
    final dy = (alan.height - goruntu.height * olcek) / 2;
    var sx = 0.0, sy = 0.0;
    for (final c in b.corners) {
      sx += c.dx;
      sy += c.dy;
    }
    return Offset(sx / b.corners.length * olcek + dx,
        sy / b.corners.length * olcek + dy);
  }

  /// Kurum etiketi ya da koli karekodu: yerelde tanınır, kısa beklenir.
  bool _taninan(String v) =>
      EtiketKodu.coz(v) != null || seriNolariAyir(v).length > 1;

  void _algilandi(BarcodeCapture capture, Size alan, Rect pencere) {
    final simdi = DateTime.now();
    _sonOkuma = simdi;
    if (simdi.isBefore(_hazir)) return;

    final goruntu = capture.size != Size.zero
        ? capture.size
        : widget.controller.value.size;

    // 1) Seri no olamayacak kodları ayıkla; webde çerçeve dışını at.
    final adaylar = <(Barcode, Offset?)>[];
    for (final b in capture.barcodes) {
      final v = b.rawValue?.trim() ?? '';
      if (v.isEmpty || gereksizKod(v)) continue;
      if (urunBarkoduTuru(b) && !widget.urunBarkodu) {
        // Ürün barkodu yalnızca kayıtlı malzeme barkoduysa okunur.
        if (widget.bilinenMi == null || _bilinenler[v] == false) continue;
      }
      final m = _merkez(b, goruntu, alan);
      if (kIsWeb && m != null && !pencere.inflate(8).contains(m)) continue;
      adaylar.add((b, m));
    }
    if (adaylar.isEmpty) return;

    // 2) Birden çok kod varsa ortaya en yakını
    Barcode secilen;
    if (adaylar.length == 1) {
      secilen = adaylar.first.$1;
    } else if (adaylar.every((a) => a.$2 != null)) {
      adaylar.sort((a, b) => (a.$2! - pencere.center)
          .distance
          .compareTo((b.$2! - pencere.center).distance));
      secilen = adaylar.first.$1;
    } else {
      // Konum hesaplanamıyor: eskisi gibi ekran "birden çok kod" uyarır.
      widget.onDetect(BarcodeCapture(
        barcodes: [for (final a in adaylar) a.$1],
        image: capture.image,
        size: capture.size,
      ));
      return;
    }
    final deger = secilen.rawValue!.trim();

    // 3) Sabit durma: aynı kod yeterince süre çerçevede kalmalı.
    _kayip?.cancel();
    _kayip = Timer(_kayipSuresi, () {
      if (mounted) setState(() => _aday = null);
    });
    if (deger == _okunan &&
        simdi.difference(_okunmaZamani) < const Duration(seconds: 3)) {
      _okunmaZamani = simdi; // hâlâ çerçevede: tekrar okunmaz
      return;
    }
    if (deger != _aday) {
      setState(() {
        _aday = deger;
        _adayKod = secilen;
        _adayBaslangic = simdi;
        _adayBekleme = _beklemeBelirle(deger, secilen);
      });
      return;
    }
    _adayKod = secilen;
    if (simdi.difference(_adayBaslangic) < _adayBekleme) return;

    // Ürün barkodunun kayıtlı olup olmadığı henüz belli değilse bekle.
    if (urunBarkoduTuru(secilen) &&
        !widget.urunBarkodu &&
        _bilinenler[deger] != true) {
      return;
    }

    _okunan = deger;
    _okunmaZamani = simdi;
    setState(() => _aday = null);
    widget.onDetect(BarcodeCapture(
      barcodes: [_adayKod!],
      image: capture.image,
      size: capture.size,
    ));
  }

  double _gecenOran() {
    final gecen = DateTime.now().difference(_adayBaslangic).inMilliseconds;
    return (gecen / _adayBekleme.inMilliseconds).clamp(0.0, 1.0);
  }

  Duration _kalanSure() {
    final kalan = _adayBekleme - DateTime.now().difference(_adayBaslangic);
    return kalan > const Duration(milliseconds: 1)
        ? kalan
        : const Duration(milliseconds: 1);
  }

  /// Kamera (yeniden) açılınca: ilk 0,8 sn okuma yok, aynı kod yeniden
  /// okunabilir.
  bool _calisiyordu = false;
  void _kameraDinle() {
    final calisiyor = widget.controller.value.isRunning;
    if (calisiyor && !_calisiyordu) {
      _hazir = DateTime.now().add(_acilisBeklemesi);
      _okunan = null;
      _aday = null;
    }
    _calisiyordu = calisiyor;
  }

  Duration _beklemeBelirle(String deger, Barcode b) {
    if (_taninan(deger)) return _kisaBekleme;
    final kontrol = widget.bilinenMi;
    if (kontrol == null) return _kisaBekleme;
    final bilinen = _bilinenler[deger];
    if (bilinen != null) return bilinen ? _kisaBekleme : _uzunBekleme;
    // Sistemde kayıtlı mı? Cevap gelene kadar uzun bekleme varsayılır.
    kontrol(deger).then((v) {
      _bilinenler[deger] = v;
      if (mounted && _aday == deger && v) {
        setState(() => _adayBekleme = _kisaBekleme);
      }
    }).catchError((_) {
      _bilinenler[deger] = false;
    });
    return _uzunBekleme;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final alan = Size(c.maxWidth, c.maxHeight);
      final pencere = _pencere(alan);
      final kucuk = alan.height < 260;
      return Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (_) => _ortayaNetle(),
            onScaleStart: (_) => _zoomBaslangic = _zoom,
            onScaleUpdate: (d) {
              if (d.pointerCount < 2) return;
              _zoomAyarla(_zoomBaslangic + (d.scale - 1) * 0.35);
            },
            child: MobileScanner(
              controller: widget.controller,
              scanWindow: pencere,
              // Yaşam döngüsünü bu widget yönetir (üstte başka sayfa
              // açıkken kamerayı yeniden açmamak için).
              useAppLifecycleState: false,
              onDetect: (capture) => _algilandi(capture, alan, pencere),
            ),
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: _CerceveBoyaci(pencere, _netleniyor || _aday != null),
            ),
          ),
          // Kilitlenme çubuğu: dolunca kod okunur.
          if (_aday != null)
            Positioned(
              left: pencere.left + 12,
              width: pencere.width - 24,
              top: pencere.bottom - 10,
              child: IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey('$_aday${_adayBaslangic.millisecondsSinceEpoch}'
                      '${_adayBekleme.inMilliseconds}'),
                  tween: Tween(begin: _gecenOran(), end: 1),
                  duration: _kalanSure(),
                  builder: (_, v, __) => ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: v,
                      minHeight: 5,
                      color: const Color(0xFF4CAF50),
                      backgroundColor: const Color(0x66FFFFFF),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: kucuk ? 6 : 12,
            right: kucuk ? 6 : 12,
            child: _Hap(
              kucuk: kucuk,
              onTap: _modDegistir,
              ikon: _mod == TaramaModu.barkod
                  ? Icons.view_week_outlined
                  : Icons.qr_code_2,
              metin: _mod == TaramaModu.barkod ? 'Barkod' : 'Karekod',
              sonIkon: Icons.swap_horiz,
            ),
          ),
          if (!kIsWeb)
            Positioned(
              top: kucuk ? 6 : 12,
              left: kucuk ? 6 : 12,
              child: _Hap(
                kucuk: kucuk,
                // Kademeler: yok → 1 → 2 → 3 → yok
                onTap: () => _zoomAyarla(_zoom >= 0.3 ? 0 : _zoom + 0.12),
                ikon: Icons.zoom_in,
                metin: _zoom < 0.01
                    ? 'Yakınlaştır'
                    : 'Yakın ${math.max(1, (_zoom / 0.12).round())}',
              ),
            ),
          if (!kucuk)
            Positioned(
              left: 16,
              right: 16,
              top: math.min(pencere.bottom + 12, alan.height - 44),
              child: Text(
                kIsWeb
                    ? 'Yalnızca çerçevenin içindeki kod okunur'
                    : 'Kodu çerçeveye alıp sabit tutun · 15-25 cm uzakta · '
                        'netlemek için dokunun',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    shadows: [Shadow(blurRadius: 4)]),
              ),
            ),
        ],
      );
    });
  }
}

class _Hap extends StatelessWidget {
  const _Hap({
    required this.kucuk,
    required this.onTap,
    required this.ikon,
    required this.metin,
    this.sonIkon,
  });

  final bool kucuk;
  final VoidCallback onTap;
  final IconData ikon;
  final String metin;
  final IconData? sonIkon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: kucuk ? 10 : 14, vertical: kucuk ? 6 : 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ikon, color: Colors.white, size: kucuk ? 16 : 20),
              const SizedBox(width: 6),
              Text(metin,
                  style: TextStyle(
                      color: Colors.white, fontSize: kucuk ? 12 : 14)),
              if (sonIkon != null) ...[
                const SizedBox(width: 4),
                Icon(sonIkon, color: Colors.white70, size: kucuk ? 14 : 18),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Çerçevenin dışını karartır, hedefi yeşil kenarla gösterir.
class _CerceveBoyaci extends CustomPainter {
  _CerceveBoyaci(this.pencere, this.netleniyor);

  final Rect pencere;
  final bool netleniyor;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(pencere, const Radius.circular(12));
    final karartma = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(rr);
    canvas.drawPath(karartma, Paint()..color = const Color(0x99000000));
    canvas.drawRRect(
      rr,
      Paint()
        ..color = netleniyor ? const Color(0xFFFFC107) : const Color(0xFF4CAF50)
        ..style = PaintingStyle.stroke
        ..strokeWidth = netleniyor ? 4 : 3,
    );
    // Ortadan geçen ince kırmızı nişan çizgisi
    canvas.drawLine(
      Offset(pencere.left + 10, pencere.center.dy),
      Offset(pencere.right - 10, pencere.center.dy),
      Paint()
        ..color = const Color(0xAAFF5252)
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_CerceveBoyaci eski) =>
      eski.pencere != pencere || eski.netleniyor != netleniyor;
}
