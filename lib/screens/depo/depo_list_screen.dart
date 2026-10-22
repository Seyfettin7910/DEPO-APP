import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart';
import '../../database/models.dart';
import '../../providers/app_providers.dart';
import '../../widgets/depo_secici.dart';
import '../../widgets/sync_durum_dugmesi.dart';
import 'depo_stok_screen.dart';
import '../../widgets/kritik_stok_seridi.dart';
import '../../widgets/etiket_karti.dart';
import '../../widgets/kod_yardimci.dart';
import '../../widgets/buyuk_harf.dart';

/// Depolar ve araçlar iki ayrı sekmede. Araçlar da depo gibi çalışır:
/// içinde cihaz / malzeme tutar, transfer hedefi olur.
class DepoListScreen extends ConsumerWidget {
  const DepoListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final depolarAsync = ref.watch(depolarStreamProvider);
    final ozetler = ref.watch(depoOzetleriProvider).valueOrNull ?? {};
    final malzeme = ref.watch(malzemeStoklariProvider).valueOrNull ??
        const <String, Map<String, int>>{};
    final depolar = depolarAsync.valueOrNull ?? const <Depo>[];
    final sabitler = depolar.where((d) => !d.arac).toList();
    final araclar = depolar.where((d) => d.arac).toList();

    // Depo / araç başına kaç çeşit malzeme var
    final malzemeCesidi = <String, int>{};
    for (final m in malzeme.values) {
      for (final e in m.entries) {
        if (e.value > 0) {
          malzemeCesidi[e.key] = (malzemeCesidi[e.key] ?? 0) + 1;
        }
      }
    }

    Widget liste(List<Depo> l, DepoTuru tur) {
      if (depolarAsync.isLoading && depolar.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (depolarAsync.hasError) {
        return Center(child: Text('Hata: ${depolarAsync.error}'));
      }
      return ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          const KritikStokSeridi(),
          if (l.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                tur == DepoTuru.arac
                    ? 'Henüz araç eklenmedi.\n+ düğmesiyle ekleyin.'
                    : 'Henüz depo eklenmedi.\n+ düğmesiyle ekleyin.',
                textAlign: TextAlign.center,
              ),
            ),
          for (final d in l)
            _satir(context, ref, d, ozetler[d.id], malzemeCesidi[d.id] ?? 0),
        ],
      );
    }

    return DefaultTabController(
      length: 2,
      child: Builder(builder: (context) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Depolar'),
            actions: [
              EtiketDugmesi(bilgisayar: bilgisayarTarayicisi),
              ...ustDugmeler(),
            ],
            bottom: TabBar(tabs: [
              Tab(
                icon: const Icon(Icons.warehouse_outlined),
                text: 'Depolar (${sabitler.length})',
              ),
              Tab(
                icon: const Icon(Icons.local_shipping_outlined),
                text: 'Araçlar (${araclar.length})',
              ),
            ]),
          ),
          floatingActionButton: FloatingActionButton(
            tooltip: 'Depo / araç ekle',
            onPressed: () => _formDialog(context, ref,
                tur: DefaultTabController.of(context).index == 1
                    ? DepoTuru.arac
                    : DepoTuru.sabit),
            child: const Icon(Icons.add),
          ),
          body: TabBarView(children: [
            liste(sabitler, DepoTuru.sabit),
            liste(araclar, DepoTuru.arac),
          ]),
        );
      }),
    );
  }

  Widget _satir(BuildContext context, WidgetRef ref, Depo depo,
      DepoOzet? ozet, int malzemeCesidi) {
    final ozetMetni = [
      if (ozet != null && ozet.urunCesidi > 0)
        '${ozet.urunCesidi} çeşit cihaz',
      if (malzemeCesidi > 0) '$malzemeCesidi çeşit malzeme',
    ];

    return ListTile(
      leading: Icon(depoIkonu(depo)),
      title: Text(depo.ad),
      subtitle: Text([
        if (depo.konum != null && depo.konum!.isNotEmpty) depo.konum!,
        if (ozetMetni.isEmpty) (depo.arac ? 'Araç boş' : 'Stok yok'),
        ...ozetMetni,
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
                textCapitalization: TextCapitalization.characters,
                inputFormatters: arac ? kodBuyuk : metinBuyuk,
                controller: adCtrl,
                autofocus: true,
                decoration: InputDecoration(
                    labelText: arac ? 'Araç plakası' : 'Depo adı'),
              ),
              TextField(
                textCapitalization: TextCapitalization.characters,
                inputFormatters: metinBuyuk,
                controller: konumCtrl,
                decoration: InputDecoration(
                  labelText: arac
                      ? 'Açıklama (marka, sürücü... isteğe bağlı)'
                      : 'Konum (isteğe bağlı)',
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
