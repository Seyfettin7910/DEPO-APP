import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/models.dart';
import '../../providers/app_providers.dart';
import 'urun_form_dialog.dart';
import '../../widgets/silme_islemleri.dart';
import '../../widgets/sync_durum_dugmesi.dart';

/// Ürünler (modeller), kategoriye göre gruplu; her başlıkta kategori toplamı,
/// her satırda o modelin tüm depolardaki toplam adedi görünür.
class UrunListScreen extends ConsumerWidget {
  const UrunListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urunlerAsync = ref.watch(urunlerStreamProvider);
    final toplamlar =
        ref.watch(urunToplamStoklariProvider).valueOrNull ?? <String, int>{};
    final kritikler = {
      for (final k in ref.watch(kritikStoklarProvider).valueOrNull ?? const [])
        k.urunId: k,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Ürünler'), actions: ustDugmeler()),
      floatingActionButton: FloatingActionButton(
        onPressed: () => urunFormDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: urunlerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Hata: $e')),
        data: (urunler) {
          if (urunler.isEmpty) {
            return const Center(child: Text('Henüz ürün eklenmedi'));
          }

          final gruplar = <String, List<Urun>>{};
          for (final u in urunler) {
            (gruplar[u.kategori ?? 'Kategorisiz'] ??= []).add(u);
          }
          final kategoriler = gruplar.keys.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          // Toplam adet yalnızca seri numaralı cihazlardan (malzemenin
          // birimi farklı: metre, paket…).
          final genelToplam = urunler
              .where((u) => !u.miktarli)
              .fold<int>(0, (t, u) => t + (toplamlar[u.id] ?? 0));

          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _Kutu(etiket: 'Model', deger: '${urunler.length}'),
                      _Kutu(etiket: 'Kategori', deger: '${kategoriler.length}'),
                      _Kutu(etiket: 'Toplam adet', deger: '$genelToplam'),
                    ],
                  ),
                ),
              ),
              if (kritikler.isNotEmpty)
                Card(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning_amber),
                            const SizedBox(width: 8),
                            Text('Kritik stok (${kritikler.length})',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        for (final k in kritikler.values)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              '• ${k.urunAdi}: toplam ${k.toplam}'
                              '${k.birim == null ? '' : ' ${k.birim}'} / min '
                              '${k.minStok} · ${k.durum}'
                              ' (depolarda ${k.depoda}, araçlarda ${k.aracta})',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              for (final kategori in kategoriler) ...[
                _KategoriBasligi(
                  ad: kategori,
                  toplam: gruplar[kategori]!
                      .where((u) => !u.miktarli)
                      .fold<int>(0, (t, u) => t + (toplamlar[u.id] ?? 0)),
                ),
                for (final urun in gruplar[kategori]!)
                  ListTile(
                    leading: Icon(urun.miktarli
                        ? Icons.cable_outlined
                        : Icons.qr_code_2),
                    title: Text(urun.ad),
                    subtitle: urun.miktarli
                        ? Text('Malzeme · miktarla (${urun.birim})'
                            '${urun.barkod == null ? '' : ' · barkod ${urun.barkod}'}')
                        : (urun.barkod == null
                            ? null
                            : Text('Model barkodu: ${urun.barkod}')),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          urun.miktarli
                              ? urun.miktarMetni(toplamlar[urun.id] ?? 0)
                              : '${toplamlar[urun.id] ?? 0}',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: kritikler.containsKey(urun.id)
                                  ? Colors.red
                                  : null),
                        ),
                        const Text('depoda', style: TextStyle(fontSize: 11)),
                      ],
                    ),
                    // Kısa dokunuşta bir şey açılmaz; düzenleme ve silme
                    // basılı tutunca çıkan menüden yapılır.
                    onLongPress: () async {
                      final secim = await secenekMenusu(context,
                          baslik: urun.ad,
                          secenekler: const [
                            ('duzenle', Icons.edit_outlined, 'Düzenle'),
                            ('sil', Icons.delete_outline, 'Ürünü sil'),
                          ]);
                      if (!context.mounted) return;
                      if (secim == 'duzenle') {
                        urunFormDialog(context, ref, mevcut: urun);
                      } else if (secim == 'sil') {
                        await urunSilAkisi(context, ref, urun);
                      }
                    },
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Kutu extends StatelessWidget {
  final String etiket;
  final String deger;
  const _Kutu({required this.etiket, required this.deger});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(deger,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(etiket, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _KategoriBasligi extends StatelessWidget {
  final String ad;
  final int toplam;
  const _KategoriBasligi({required this.ad, required this.toplam});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              ad.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Text('$toplam adet',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
