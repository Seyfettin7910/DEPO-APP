import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
class HedefliTarayici extends StatefulWidget {
  const HedefliTarayici({
    super.key,
    required this.controller,
    required this.onDetect,
  });

  final MobileScannerController controller;
  final void Function(BarcodeCapture capture) onDetect;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _moduYukle();
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
  void dispose() {
    _netleme?.cancel();
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
      if (onde && mounted) unawaited(c.start().catchError((_) {}));
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
      final g = math.min(alan.width * 0.88, 560.0);
      final y = math.min(math.max(alan.height * 0.26, 64.0), 150.0);
      return Rect.fromCenter(center: merkez, width: g, height: y);
    }
    // Koli karekodu gibi büyük/yoğun kodlar için geniş kare.
    final k = math.min(
        math.min(alan.width * 0.82, alan.height * 0.86), 420.0);
    return Rect.fromCenter(center: merkez, width: k, height: k);
  }

  /// Telefonda kamera kütüphanesi zaten yalnızca çerçevenin içini okur.
  /// Web'de bu her tarayıcıda garanti olmadığından, kodun merkezinin
  /// çerçevede olup olmadığı ayrıca kontrol edilir.
  void _algilandi(BarcodeCapture capture, Size alan, Rect pencere) {
    _sonOkuma = DateTime.now();
    if (!kIsWeb) {
      widget.onDetect(capture);
      return;
    }
    // Kamera görüntüsünün boyutu (yakalamada yoksa kameranın durumundan).
    final goruntu = capture.size != Size.zero
        ? capture.size
        : widget.controller.value.size;
    if (goruntu.width <= 0 || goruntu.height <= 0) {
      widget.onDetect(capture);
      return;
    }
    // Önizleme "cover" ile ekrana sığdırılır: ölçekle ve ortala.
    final olcek = math.max(
        alan.width / goruntu.width, alan.height / goruntu.height);
    final dx = (alan.width - goruntu.width * olcek) / 2;
    final dy = (alan.height - goruntu.height * olcek) / 2;
    final icerdekiler = capture.barcodes.where((b) {
      if (b.corners.isEmpty) return true;
      var sx = 0.0, sy = 0.0;
      for (final c in b.corners) {
        sx += c.dx;
        sy += c.dy;
      }
      final m = Offset(sx / b.corners.length * olcek + dx,
          sy / b.corners.length * olcek + dy);
      return pencere.inflate(8).contains(m);
    }).toList();
    if (icerdekiler.isEmpty) return;
    widget.onDetect(BarcodeCapture(
      barcodes: icerdekiler,
      image: capture.image,
      size: capture.size,
    ));
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
              painter: _CerceveBoyaci(pencere, _netleniyor),
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
                    : 'Kodu çerçeveye alın · 15-25 cm uzakta tutun · '
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
