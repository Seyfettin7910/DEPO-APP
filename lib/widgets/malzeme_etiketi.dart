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

/// Tek malzemeye 266'lı stok kodu verir (fabrika barkodu varsa onun yerine,
/// onaylı).
Future<void> malzemeyeKodVer(
    BuildContext context, WidgetRef ref, Urun u) async {
  final fabrika = (u.barkod ?? '').trim();
  if (fabrika.isNotEmpty) {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stok kodu ver'),
        content: Text('${u.ad}\n\nFabrika barkodu ($fabrika) silinip yerine '
            '266 ile başlayan stok kodu yazılacak. Bundan sonra bu malzeme '
            'yalnız stok kodu etiketiyle okunur.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Stok kodu ver')),
        ],
      ),
    );
    if (onay != true || !context.mounted) return;
  }
  try {
    final k = await ref
        .read(appDatabaseProvider)
        .malzemeyeKurumKoduVer(u.id, fabrikaninYerine: true);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Stok kodu verildi: $k. Etiket için malzemeye basılı '
              'tutun → "Barkod etiketi bas".')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is StateError ? e.message : '$e'),
          backgroundColor: Colors.red.shade700));
    }
  }
}

/// Malzemelere toplu stok kodu (onaylı): barkodsuzlara ya da bütün
/// malzemelere (fabrika barkodlarının yerine).
Future<void> barkodsuzlaraKodVer(BuildContext context, WidgetRef ref) async {
  final db = ref.read(appDatabaseProvider);
  final (bos, fabrika) = await db.stokKoduSayilari();
  if (!context.mounted) return;
  if (bos + fabrika == 0) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Bütün malzemelerin stok kodu var')));
    return;
  }
  final secim = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Malzemelere stok kodu ver'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Barkodu olmayan: $bos malzeme\n'
              'Fabrika barkodlu: $fabrika malzeme'),
          const SizedBox(height: 12),
          const Text('Stok kodu 266 ile başlayan kurum içi barkoddur (EAN-13). '
              'Fabrika barkodlarının yerine verilirse o malzemeler bundan '
              'sonra yalnız stok kodu etiketiyle okunur.'),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç')),
        if (bos > 0)
          OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Yalnız barkodsuzlara ($bos)')),
        if (fabrika > 0)
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Bütün malzemelere (${bos + fabrika})')),
      ],
    ),
  );
  if (secim == null) return;
  final verilen = await db.malzemelereStokKoduVer(fabrikaninYerine: secim);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$verilen malzemeye stok kodu verildi. Etiket için '
            'malzemeye basılı tutun → "Barkod etiketi bas".')));
  }
}

/// 1.30.3: malzeme girişi kaydedilince "Kaç kutu geldi? Etiket basılsın
/// mı?" — her malzeme için önerilen etiket sayısı (miktar / kutu içeriği),
/// değiştirilebilir; 0 olanlar basılmaz. Tek PDF, önizlemeden yazdırılır.
Future<void> girisSonrasiEtiketSor(
    BuildContext context, List<(Urun, int)> girenler) async {
  final kalemler = [
    for (final (u, miktar) in girenler)
      if ((u.barkod ?? '').trim().isNotEmpty && miktar > 0) (u, miktar),
  ];
  if (kalemler.isEmpty) return;
  final ctrl = [
    for (final (u, miktar) in kalemler)
      TextEditingController(
          text: '${((miktar + u.okutmaMiktari - 1) ~/ u.okutmaMiktari).clamp(1, 500)}'),
  ];
  final bas = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Etiket basılsın mı?'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Kaç kutu / parça geldi? Her birine bir stok kodu '
                  'etiketi basılır (0: basılmaz).'),
              const SizedBox(height: 8),
              for (var i = 0; i < kalemler.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(kalemler[i].$1.ad,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            Text(kalemler[i].$1.kutuluMetin(kalemler[i].$2),
                                style: Theme.of(ctx).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 72,
                        child: TextField(
                          controller: ctrl[i],
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          decoration: const InputDecoration(
                              isDense: true, suffixText: 'ad.'),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Basma')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Önizle')),
      ],
    ),
  );
  final adetler = [
    for (final c in ctrl) (int.tryParse(c.text.trim()) ?? 0).clamp(0, 500)
  ];
  for (final c in ctrl) {
    c.dispose();
  }
  if (bas != true || !context.mounted) return;
  final secilen = [
    for (var i = 0; i < kalemler.length; i++)
      if (adetler[i] > 0) (kalemler[i].$1, adetler[i]),
  ];
  if (secilen.isEmpty) return;
  try {
    final sablon = await EtiketSablonu.yukle();
    final pdf = await EtiketPdf.cokluMalzemeEtiketleri(secilen, sablon);
    if (!context.mounted) return;
    await PdfOnizleme.ac(context,
        bytes: pdf,
        ad: 'malzeme_girisi_etiketleri',
        format: EtiketPdf.sayfaFormati(sablon));
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Etiket hazırlanamadı: $e'),
          backgroundColor: Colors.red.shade700));
    }
  }
}
