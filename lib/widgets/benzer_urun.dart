import 'package:flutter/material.dart';

import '../database/models.dart';
import 'renkler.dart';

/// Benzer ürün seçimi (1.29.3): yeni ürün tanımlarken ad, var olan bir ürünle
/// yalnız İ / I, büyük / küçük harf ya da boşluk farkıyla aynıysa açılır.
/// Dönen değer: seçilen [Urun] (yeni ürün oluşturulmaz), [benzerYeni]
/// ("Hiçbiri değil, yeni ürün oluştur") ya da null (vazgeç, forma dönülür).
const benzerYeni = 'yeni';

Future<Object?> benzerUrunSec(BuildContext context, List<Urun> benzerler) {
  return showDialog<Object>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.content_copy_outlined, color: Renkler.zil),
      title: const Text('Bu ada benzeyen ürün var'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Aynı ürünse listeden seçin; yeni ürün açılmaz, '
                'cihazlar ve stok tek ürün altında toplanır.'),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final u in benzerler)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: Icon(
                            u.miktarli
                                ? Icons.straighten
                                : Icons.qr_code_2,
                            color: Renkler.urun),
                        title: Text(u.ad,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text([
                          u.miktarli ? 'Miktarla (${u.birim})' : 'Seri no ile',
                          if ((u.kategori ?? '').isNotEmpty) u.kategori!,
                        ].join(' · ')),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.pop(ctx, u),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, benzerYeni),
            child: const Text('Hiçbiri değil, yeni ürün oluştur')),
      ],
    ),
  );
}

/// Ad düzeltirken aynı adda (benzer) başka ürün varsa (1.30.0: birleştirme
/// seçeneğiyle). Dönen: 'kaydet' (yine de kaydet), 'birlestir' ya da null.
Future<String?> benzerAdUyarisi(BuildContext context, List<Urun> cakisan) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded, color: Renkler.zil),
      title: const Text('Bu adda başka ürün var'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final u in cakisan)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• ${u.ad}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 8),
          const Text('Aynı ürünse "Birleştir" ile bu ürünün cihazlarını ve '
              'hareketlerini ona taşıyın; tek ürün olarak görünür. '
              'Kaydederseniz iki ürün ayrı ayrı görünür.'),
        ],
      ),
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, 'kaydet'),
            child: const Text('Yine de kaydet')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, 'birlestir'),
            child: const Text('Birleştir')),
      ],
    ),
  );
}
