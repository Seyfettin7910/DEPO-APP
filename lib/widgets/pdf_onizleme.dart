import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';

/// 1.29.2: yazdırmadan önce PDF önizleme (etiket basımı, hizalama test
/// sayfası, örnek etiketler). Android'in yazdırma ekranında büyütme olmadığı
/// için sayfalar burada gösterilir:
/// - iki parmakla 5 kata kadar büyütülür, büyükken parmakla kaydırılır;
/// - çift dokunuş büyütür / geri alır;
/// - birden çok sayfa yana kaydırılarak gezilir (büyükken kaydırma kapalı).
/// Altta "PDF paylaş" ve "Yazdır". Yazdırıldı / paylaşıldıysa true döner.
class PdfOnizleme extends StatefulWidget {
  const PdfOnizleme({
    super.key,
    required this.bytes,
    required this.ad,
    this.format,
  });

  final Uint8List bytes;
  final String ad;
  final PdfPageFormat? format;

  static Future<bool> ac(
    BuildContext context, {
    required Uint8List bytes,
    required String ad,
    PdfPageFormat? format,
  }) async {
    final r = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => PdfOnizleme(bytes: bytes, ad: ad, format: format)));
    return r ?? false;
  }

  @override
  State<PdfOnizleme> createState() => _PdfOnizlemeState();
}

class _PdfOnizlemeState extends State<PdfOnizleme> {
  final _sayfalar = <Uint8List>[];
  bool _hazir = false;
  String? _hata;
  int _sayfa = 0;
  bool _buyuk = false; // büyütülmüşken sayfa değiştirme kapalı
  bool _calisiyor = false;
  final _pageCtrl = PageController();
  final _donusumler = <int, TransformationController>{};
  Offset? _ciftDokunus;

  @override
  void initState() {
    super.initState();
    unawaited(_hazirla());
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    for (final c in _donusumler.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _hazirla() async {
    try {
      // 200 dpi: A4 ≈ 1650 × 2340 piksel; 5x büyütmede karekod okunur kalır.
      await for (final r in Printing.raster(widget.bytes, dpi: 200)) {
        final png = await r.toPng();
        if (!mounted) return;
        setState(() => _sayfalar.add(png));
      }
    } catch (e) {
      _hata = 'Önizleme gösterilemedi ($e). Yine de yazdırabilir ya da '
          'paylaşabilirsiniz.';
    }
    if (mounted) setState(() => _hazir = true);
  }

  TransformationController _donusum(int i) =>
      _donusumler.putIfAbsent(i, () {
        final c = TransformationController();
        c.addListener(() {
          final buyuk = c.value.getMaxScaleOnAxis() > 1.01;
          if (buyuk != _buyuk && mounted && i == _sayfa) {
            setState(() => _buyuk = buyuk);
          }
        });
        return c;
      });

  void _ciftDokun(int i) {
    final c = _donusum(i);
    if (c.value.getMaxScaleOnAxis() > 1.01) {
      c.value = Matrix4.identity();
      return;
    }
    final n = _ciftDokunus ?? Offset.zero;
    const olcek = 3.0;
    // Dokunulan nokta yerinde kalacak şekilde 3x.
    c.value = Matrix4.identity()
      ..setEntry(0, 0, olcek)
      ..setEntry(1, 1, olcek)
      ..setEntry(0, 3, -n.dx * (olcek - 1))
      ..setEntry(1, 3, -n.dy * (olcek - 1));
  }

  Future<void> _yazdir() async {
    setState(() => _calisiyor = true);
    try {
      await Printing.layoutPdf(
        onLayout: (_) async => widget.bytes,
        name: widget.ad,
        format: widget.format ?? PdfPageFormat.a4,
      );
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _calisiyor = false);
    }
  }

  Future<void> _paylas() async {
    setState(() => _calisiyor = true);
    try {
      await Printing.sharePdf(bytes: widget.bytes, filename: '${widget.ad}.pdf');
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _calisiyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF3A3F44),
      appBar: AppBar(
        title: const Text('Önizleme'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'İki parmakla büyütün · çift dokunuş: büyüt / geri al',
              style: tema.textTheme.bodySmall,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _govde()),
          if (_sayfalar.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${_sayfa + 1} / ${_sayfalar.length}',
                  style: const TextStyle(color: Colors.white70)),
            ),
          Container(
            color: tema.colorScheme.surface,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                    onPressed: _calisiyor ? null : _paylas,
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('PDF paylaş'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                    onPressed: _calisiyor ? null : _yazdir,
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Yazdır'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _govde() {
    if (_sayfalar.isEmpty) {
      if (!_hazir) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 12),
              Text('Önizleme hazırlanıyor…',
                  style: TextStyle(color: Colors.white70)),
            ],
          ),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_hata ?? 'Sayfa yok',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white)),
        ),
      );
    }
    return PageView.builder(
      controller: _pageCtrl,
      physics: _buyuk
          ? const NeverScrollableScrollPhysics()
          : const PageScrollPhysics(),
      itemCount: _sayfalar.length,
      onPageChanged: (i) => setState(() {
        _sayfa = i;
        _buyuk = _donusum(i).value.getMaxScaleOnAxis() > 1.01;
      }),
      itemBuilder: (context, i) => GestureDetector(
        onDoubleTapDown: (d) => _ciftDokunus = d.localPosition,
        onDoubleTap: () => _ciftDokun(i),
        child: InteractiveViewer(
          transformationController: _donusum(i),
          minScale: 1,
          maxScale: 5,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(blurRadius: 8, color: Colors.black45)],
                ),
                child: Image.memory(_sayfalar[i],
                    fit: BoxFit.contain, filterQuality: FilterQuality.medium),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
