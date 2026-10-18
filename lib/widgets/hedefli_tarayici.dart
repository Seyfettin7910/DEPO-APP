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
/// Sağ üstteki düğmeyle çerçeve "Barkod" (ince-uzun) ve "Karekod" (kare)
/// arasında değiştirilir; seçim telefonda hatırlanır.
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

class _HedefliTarayiciState extends State<HedefliTarayici> {
  static const _anahtar = 'tarama_modu';
  TaramaModu _mod = TaramaModu.barkod;

  @override
  void initState() {
    super.initState();
    _moduYukle();
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

  /// Görüntü alanına göre hedef çerçeve.
  Rect _pencere(Size alan) {
    final merkez = Offset(alan.width / 2, alan.height / 2);
    if (_mod == TaramaModu.barkod) {
      final g = math.min(alan.width * 0.86, 520.0);
      final y = math.min(math.max(alan.height * 0.22, 56.0), 120.0);
      return Rect.fromCenter(center: merkez, width: g, height: y);
    }
    final k = math.min(math.min(alan.width, alan.height) * 0.62, 320.0);
    return Rect.fromCenter(center: merkez, width: k, height: k);
  }

  /// Telefonda kamera kütüphanesi zaten yalnızca çerçevenin içini okur.
  /// Web'de bu her tarayıcıda garanti olmadığından, kodun merkezinin
  /// çerçevede olup olmadığı ayrıca kontrol edilir.
  void _algilandi(BarcodeCapture capture, Size alan, Rect pencere) {
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
          MobileScanner(
            controller: widget.controller,
            scanWindow: pencere,
            onDetect: (capture) => _algilandi(capture, alan, pencere),
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: _CerceveBoyaci(pencere),
            ),
          ),
          Positioned(
            top: kucuk ? 6 : 12,
            right: kucuk ? 6 : 12,
            child: Material(
              color: Colors.black54,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: _modDegistir,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: kucuk ? 10 : 14, vertical: kucuk ? 6 : 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _mod == TaramaModu.barkod
                            ? Icons.view_week_outlined
                            : Icons.qr_code_2,
                        color: Colors.white,
                        size: kucuk ? 16 : 20,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _mod == TaramaModu.barkod ? 'Barkod' : 'Karekod',
                        style: TextStyle(
                            color: Colors.white, fontSize: kucuk ? 12 : 14),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.swap_horiz,
                          color: Colors.white70, size: kucuk ? 14 : 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (!kucuk)
            Positioned(
              left: 0,
              right: 0,
              top: pencere.bottom + 12,
              child: const Text(
                'Yalnızca çerçevenin içindeki kod okunur',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
        ],
      );
    });
  }
}

/// Çerçevenin dışını karartır, hedefi yeşil kenarla gösterir.
class _CerceveBoyaci extends CustomPainter {
  _CerceveBoyaci(this.pencere);

  final Rect pencere;

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
        ..color = const Color(0xFF4CAF50)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
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
  bool shouldRepaint(_CerceveBoyaci eski) => eski.pencere != pencere;
}
