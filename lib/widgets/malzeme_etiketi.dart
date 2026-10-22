import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/models.dart';
import '../providers/app_providers.dart';
import '../services/etiket/etiket_pdf.dart';
import '../services/etiket/etiket_sablonu.dart';
import 'pdf_onizleme.dart';

/// Malzeme barkod etiketi basma (1.30.2): kaç etiket sorulur, etiket kağıdı
/// şablonuyla PDF hazırlanır, büyütülebilir önizlemeden yazdırılır.
Future<void> malzemeEtiketiBas(BuildContext context, Urun u) async {
  if ((u.barkod ?? '').trim().isEmpty) return;
  final ctrl = TextEditingController(text: '1');
  final adet = await showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Barkod etiketi bas'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(u.ad, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('Barkod: ${u.barkod}'),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Kaç etiket? (1-500)',
              helperText: 'Örn. 10 kutu kablo için 10',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç')),
        FilledButton(
          onPressed: () {
            final n = int.tryParse(ctrl.text.trim()) ?? 0;
            if (n >= 1 && n <= 500) Navigator.pop(ctx, n);
          },
          child: const Text('Önizle'),
        ),
      ],
    ),
  );
  if (adet == null || !context.mounted) return;
  try {
    final sablon = await EtiketSablonu.yukle();
    final pdf = await EtiketPdf.malzemeEtiketleri(u, adet, sablon);
    if (!context.mounted) return;
    await PdfOnizleme.ac(context,
        bytes: pdf,
        ad: 'malzeme_${u.barkod}',
        format: EtiketPdf.sayfaFormati(sablon));
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Etiket hazırlanamadı: $e'),
          backgroundColor: Colors.red.shade700));
    }
  }
}

/// Tek malzemeye 266'lı kurum kodu verir.
Future<void> malzemeyeKodVer(
    BuildContext context, WidgetRef ref, Urun u) async {
  try {
    final k = await ref.read(appDatabaseProvider).malzemeyeKurumKoduVer(u.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kurum kodu verildi: $k')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is StateError ? e.message : '$e'),
          backgroundColor: Colors.red.shade700));
    }
  }
}

/// Barkodu olmayan bütün malzemelere kurum kodu (onaylı).
Future<void> barkodsuzlaraKodVer(BuildContext context, WidgetRef ref) async {
  final db = ref.read(appDatabaseProvider);
  final n = await db.barkodsuzMalzemeSayisi();
  if (!context.mounted) return;
  if (n == 0) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Barkodu olmayan malzeme yok')));
    return;
  }
  final onay = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Barkodsuz malzemelere kod üret'),
      content: Text('$n malzemeye 266 ile başlayan kurum içi barkod (EAN-13) '
          'verilecek. Fabrika barkodu olanlara dokunulmaz.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kod üret')),
      ],
    ),
  );
  if (onay != true) return;
  final verilen = await db.barkodsuzMalzemelereKodVer();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$verilen malzemeye kurum kodu verildi. Etiket için '
            'malzemeye basılı tutun → "Barkod etiketi bas".')));
  }
}
