import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart';
import '../../database/models.dart';
import '../../providers/app_providers.dart';
import '../../widgets/depo_secici.dart';
import '../../widgets/sync_durum_dugmesi.dart';
import 'depo_stok_screen.dart';
import '../../widgets/kritik_stok_seridi.dart';
import '../../widgets/bildirim_dugmesi.dart';

/// Depolar ve araçlar (seyyar depolar) bir arada. Araçlar da depo gibi
/// çalışır: içinde cihaz tutar, transfer hedefi olur.
class DepoListScreen extends ConsumerWidget {
  const DepoListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final depolarAsync = ref.watch(depolarStreamProvider);
    final ozetler = ref.watch(depoOzetleriProvider).value ?? {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Depolar'),
        actions: const [BildirimDugmesi(), SyncDurumDugmesi()],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _ekleSecimi(context, ref),
        child: const Icon(Icons.add),
      ),
      body: depolarAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Hata: $e')),
        data: (depolar) {
          if (depolar.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Henüz depo veya araç eklenmedi.\n+ düğmesiyle ekleyin.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final sabitler = depolar.where((d) => !d.arac).toList();
          final araclar = depolar.where((d) => d.arac).toList();

          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              const KritikStokSeridi(),
              if (sabitler.isNotEmpty) const _Baslik('DEPOLAR'),
              for (final d in sabitler) _satir(context, ref, d, ozetler[d.id]),
              if (araclar.isNotEmpty) const _Baslik('ARAÇLAR (SEYYAR DEPO)'),
              for (final d in araclar) _satir(context, ref, d, ozetler[d.id]),
            ],
          );
        },
      ),
    );
  }

  Widget _satir(
      BuildContext context, WidgetRef ref, Depo depo, DepoOzet? ozet) {
    final ozetMetni = ozet == null || ozet.urunCesidi == 0
        ? (depo.arac ? 'Araçta cihaz yok' : 'Stok yok')
        : '${ozet.urunCesidi} çeşit ürün';

    return ListTile(
      leading: Icon(depoIkonu(depo)),
      title: Text(depo.ad),
      subtitle: Text([
        if (depo.konum != null && depo.konum!.isNotEmpty) depo.konum!,
        ozetMetni,
      ].join(' · ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${ozet?.toplamMiktar ?? 0}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const Text('cihaz', style: TextStyle(fontSize: 11)),
            ],
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'duzenle') {
                _formDialog(context, ref, tur: depo.tur, mevcut: depo);
              } else if (v == 'sil') {
                _sil(context, ref, depo);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'duzenle', child: Text('Düzenle')),
              PopupMenuItem(value: 'sil', child: Text('Sil')),
            ],
          ),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DepoStokScreen(depoId: depo.id, depoAdi: depo.ad),
        ),
      ),
    );
  }

  void _ekleSecimi(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.warehouse_outlined),
              title: const Text('Yeni depo'),
              onTap: () {
                Navigator.pop(ctx);
                _formDialog(context, ref, tur: DepoTuru.sabit);
              },
            ),
            ListTile(
              leading: const Icon(Icons.local_shipping_outlined),
              title: const Text('Yeni araç (seyyar depo)'),
              subtitle: const Text('Sahada gezen araç; içinde cihaz taşıyabilir'),
              onTap: () {
                Navigator.pop(ctx);
                _formDialog(context, ref, tur: DepoTuru.arac);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sil(BuildContext context, WidgetRef ref, Depo depo) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(depo.arac ? 'Aracı sil' : 'Depoyu sil'),
        content: Text('"${depo.ad}" silinsin mi? Geçmiş kayıtlar korunur.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sil')),
        ],
      ),
    );
    if (onay != true) return;
    try {
      await ref.read(appDatabaseProvider).depoSil(depo.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is StateError ? e.message : 'Silinemedi: $e'),
          backgroundColor: Colors.red.shade700,
        ));
      }
    }
  }

  void _formDialog(BuildContext context, WidgetRef ref,
      {required DepoTuru tur, Depo? mevcut}) {
    final arac = tur == DepoTuru.arac;
    final adCtrl = TextEditingController(text: mevcut?.ad ?? '');
    final konumCtrl = TextEditingController(text: mevcut?.konum ?? '');
    String? hata;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(mevcut == null
              ? (arac ? 'Yeni Araç' : 'Yeni Depo')
              : (arac ? 'Aracı Düzenle' : 'Depoyu Düzenle')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: adCtrl,
                autofocus: true,
                textCapitalization:
                    arac ? TextCapitalization.characters : TextCapitalization.words,
                decoration: InputDecoration(
                    labelText: arac ? 'Araç plakası' : 'Depo adı'),
              ),
              TextField(
                controller: konumCtrl,
                decoration: InputDecoration(
                  labelText: arac
                      ? 'Açıklama (marka, sürücü... opsiyonel)'
                      : 'Konum (opsiyonel)',
                ),
              ),
              if (hata != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(hata!,
                      style:
                          TextStyle(color: Theme.of(ctx).colorScheme.error)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () async {
                if (adCtrl.text.trim().isEmpty) {
                  setState(() => hata =
                      arac ? 'Plaka boş olamaz' : 'Depo adı boş olamaz');
                  return;
                }
                final konum =
                    konumCtrl.text.trim().isEmpty ? null : konumCtrl.text.trim();
                final db = ref.read(appDatabaseProvider);
                try {
                  if (mevcut == null) {
                    await db.depoEkle(
                        ad: adCtrl.text, konum: konum, tur: tur);
                  } else {
                    await db.depoGuncelle(
                        id: mevcut.id, ad: adCtrl.text, konum: konum);
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } catch (e) {
                  setState(() =>
                      hata = e is StateError ? e.message : 'Kaydedilemedi: $e');
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Baslik extends StatelessWidget {
  final String metin;
  const _Baslik(this.metin);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(metin,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
}
