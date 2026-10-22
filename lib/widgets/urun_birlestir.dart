import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/models.dart';
import '../providers/app_providers.dart';
import '../services/urun_adi.dart';
import 'buyuk_harf.dart';
import 'renkler.dart';

/// Ürün birleştirme akışı (1.30.0): [kaynak] ürünü seçilen ürüne katılır.
/// 1) Kalacak ürün seçilir ([adaylar] tek ise doğrudan o), 2) özet ve onay
/// ("12 cihaz, 30 hareket taşınacak · geri alınamaz"), 3) birleştirme.
/// Birleştirildiyse kalan ürünün id'si döner.
Future<String?> urunBirlestirAkisi(
  BuildContext context,
  WidgetRef ref,
  Urun kaynak, {
  List<Urun>? adaylar,
}) async {
  final db = ref.read(appDatabaseProvider);
  Urun? hedef;
  final uygunAdaylar =
      adaylar?.where((u) => u.miktarli == kaynak.miktarli).toList();
  if (uygunAdaylar != null && uygunAdaylar.length == 1) {
    hedef = uygunAdaylar.first;
  } else {
    final tumu = uygunAdaylar ??
        (await db.tumUrunler())
            .where((u) => u.id != kaynak.id && u.miktarli == kaynak.miktarli)
            .toList();
    if (!context.mounted) return null;
    if (tumu.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Birleştirilecek aynı türde başka ürün yok')));
      return null;
    }
    hedef = await _hedefSec(context, kaynak, tumu);
  }
  if (hedef == null || !context.mounted) return null;

  final ozet = await db.birlestirmeOzeti(kaynak.id);
  if (!context.mounted) return null;
  final onay = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.merge_type, color: Renkler.urun),
      title: const Text('Ürünleri birleştir'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(kaynak.ad,
              style: const TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: Colors.black54)),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Icon(Icons.arrow_downward, size: 18),
          ),
          Text(hedef!.ad, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text([
            '${ozet.cihaz} cihaz',
            '${ozet.hareket} hareket',
            if (ozet.servis > 0) '${ozet.servis} servis kaydı',
          ].join(', ') +
              ' kalan ürüne taşınacak. "${kaynak.ad}" listeden kalkar.'),
          const SizedBox(height: 8),
          const Text('Hareket kayıtları silinmez. Bu işlem geri alınamaz.',
              style: TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç')),
        FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Renkler.cikis),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Birleştir')),
      ],
    ),
  );
  if (onay != true || !context.mounted) return null;

  try {
    await db.urunleriBirlestir(kaynakId: kaynak.id, hedefId: hedef.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Birleştirildi: ${ozet.cihaz} cihaz '
              '${hedef.ad} ürününe taşındı')));
    }
    return hedef.id;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e is StateError ? e.message : 'Birleştirilemedi: $e'),
        backgroundColor: Colors.red.shade700,
      ));
    }
    return null;
  }
}

/// Kalacak ürünü seçme: adı benzeyenler (İ / I, boşluk farkı) en üstte.
Future<Urun?> _hedefSec(BuildContext context, Urun kaynak, List<Urun> tumu) {
  final anahtar = urunAdiAnahtari(kaynak.ad);
  final ctrl = TextEditingController();
  return showDialog<Urun>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final q = urunAdiAnahtari(ctrl.text);
      final liste = tumu
          .where((u) => q.isEmpty || urunAdiAnahtari(u.ad).contains(q))
          .toList()
        ..sort((a, b) {
          final ab = urunAdiAnahtari(a.ad) == anahtar ? 0 : 1;
          final bb = urunAdiAnahtari(b.ad) == anahtar ? 0 : 1;
          return ab != bb ? ab - bb : a.ad.compareTo(b.ad);
        });
      return AlertDialog(
        title: const Text('Hangi ürünle birleşsin?'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Seçtiğiniz ürün kalır; "${kaynak.ad}" ona katılır.'),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: kodBuyuk,
                decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Ürün ara'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final u in liste)
                      ListTile(
                        dense: true,
                        leading: Icon(
                            u.miktarli ? Icons.straighten : Icons.qr_code_2,
                            color: Renkler.urun),
                        title: Text(u.ad),
                        subtitle: urunAdiAnahtari(u.ad) == anahtar
                            ? const Text('Benzer ad',
                                style: TextStyle(color: Renkler.zil))
                            : (u.kategori == null ? null : Text(u.kategori!)),
                        onTap: () => Navigator.pop(ctx, u),
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
        ],
      );
    }),
  );
}
