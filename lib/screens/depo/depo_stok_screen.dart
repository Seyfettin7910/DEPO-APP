import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../database/app_database.dart';
import '../../database/models.dart';
import '../../providers/app_providers.dart';
import '../cihaz/cihaz_detay_screen.dart';
import '../cihaz/toplu_giris_screen.dart';
import '../cihaz/toplu_transfer_screen.dart';
import '../rapor/sayim_screen.dart';

/// Bir deponun detayı: "Stok" sekmesinde ürünlerin güncel adedi,
/// "Hareketler" sekmesinde giren/çıkan her işlem görünür.
class DepoStokScreen extends ConsumerWidget {
  final String depoId;
  final String depoAdi;

  const DepoStokScreen({super.key, required this.depoId, required this.depoAdi});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(depoAdi),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Stok'),
              Tab(text: 'Cihazlar'),
              Tab(text: 'Hareketler'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _islemMenusu(context, depoId, depoAdi),
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Seri no ile işlem'),
        ),
        body: TabBarView(
          children: [
            _StokListesi(depoId: depoId),
            _CihazListesi(depoId: depoId),
            _HareketListesi(depoId: depoId),
          ],
        ),
      ),
    );
  }
}

void _islemMenusu(BuildContext context, String depoId, String depoAdi) {
  {
    void ac(Widget ekran) {
      Navigator.pop(context);
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ekran));
    }

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_box_outlined),
              title: Text('Yeni cihaz girişi ($depoAdi)'),
              subtitle: const Text('Seri no okutarak bu depoya ekle'),
              onTap: () => ac(TopluGirisScreen(onceSeciliDepoId: depoId)),
            ),
            ListTile(
              leading: const Icon(Icons.move_to_inbox_outlined),
              title: Text('Buraya transfer ($depoAdi)'),
              subtitle: const Text('Başka depo/araçtaki cihazları buraya al'),
              onTap: () =>
                  ac(TopluTransferScreen(onceHedefDepoId: depoId)),
            ),
            ListTile(
              leading: const Icon(Icons.assignment_return_outlined),
              title: Text('Toplu iade ($depoAdi)'),
              subtitle: const Text('Araçtaki cihazları seri no okutup buraya iade al'),
              onTap: () => ac(TopluTransferScreen(
                  tip: HareketTipi.iade, onceHedefDepoId: depoId)),
            ),
            ListTile(
              leading: const Icon(Icons.local_shipping_outlined),
              title: const Text('Toplu kullanıma ver'),
              subtitle: const Text('Seri no okutup bir depo/araca ver'),
              onTap: () => ac(const TopluTransferScreen(
                  tip: HareketTipi.kullanim)),
            ),
            ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: Text('Sayım yap ($depoAdi)'),
              subtitle: const Text('Cihazları okutup sistemle karşılaştır'),
              onTap: () => ac(SayimScreen(onceSeciliDepoId: depoId)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Model bazlı adetler: bu depoda her üründen kaç cihaz var.
class _StokListesi extends ConsumerWidget {
  final String depoId;
  const _StokListesi({required this.depoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sayilarAsync = ref.watch(depoUrunSayilariProvider(depoId));
    final urunlerAsync = ref.watch(urunlerStreamProvider);

    return sayilarAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Hata: $e')),
      data: (sayilar) {
        final urunlerMap = <String, Urun>{
          for (final u in urunlerAsync.value ?? <Urun>[]) u.id: u,
        };
        final girdiler = sayilar.entries.where((e) => e.value > 0).toList()
          ..sort((a, b) {
            final an = urunlerMap[a.key]?.ad ?? '';
            final bn = urunlerMap[b.key]?.ad ?? '';
            return an.toLowerCase().compareTo(bn.toLowerCase());
          });

        if (girdiler.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Bu depoda henüz cihaz yok.\n\n'
                'Aşağıdaki "Seri no ile giriş" düğmesiyle seri numaralarını '
                'okutarak ekleyebilirsiniz.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final toplam = girdiler.fold<int>(0, (t, e) => t + e.value);

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
                    _OzetKutusu(etiket: 'Çeşit ürün', deger: '${girdiler.length}'),
                    _OzetKutusu(etiket: 'Toplam adet', deger: '$toplam'),
                  ],
                ),
              ),
            ),
            for (final e in girdiler)
              _StokSatiri(
                depoId: depoId,
                urun: urunlerMap[e.key],
                urunId: e.key,
                adet: e.value,
              ),
          ],
        );
      },
    );
  }
}

/// Bu depoda şu an bulunan her seri numarası; üstte arama kutusu.
class _CihazListesi extends ConsumerStatefulWidget {
  final String depoId;
  const _CihazListesi({required this.depoId});

  @override
  ConsumerState<_CihazListesi> createState() => _CihazListesiState();
}

class _CihazListesiState extends ConsumerState<_CihazListesi> {
  String _filtre = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(depoCihazlariProvider(widget.depoId));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Hata: $e')),
      data: (liste) {
        if (liste.isEmpty) {
          return const Center(child: Text('Bu depoda cihaz yok'));
        }
        final f = _filtre.toLowerCase();
        final gorunen = f.isEmpty
            ? liste
            : liste
                .where((b) =>
                    b.cihaz.seriNo.toLowerCase().contains(f) ||
                    b.urunAdi.toLowerCase().contains(f))
                .toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Bu depoda seri no / model ara',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _filtre = v.trim()),
              ),
            ),
            Expanded(
              child: gorunen.isEmpty
                  ? const Center(child: Text('Eşleşen cihaz yok'))
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: gorunen.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final b = gorunen[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.qr_code_2),
                          title: Text(b.urunAdi),
                          subtitle: Text('SN: ${b.cihaz.seriNo}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  CihazDetayScreen(cihazId: b.cihaz.id),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _OzetKutusu extends StatelessWidget {
  final String etiket;
  final String deger;
  const _OzetKutusu({required this.etiket, required this.deger});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(deger,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(etiket, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _StokSatiri extends StatelessWidget {
  final String depoId;
  final String urunId;
  final Urun? urun;
  final int adet;
  const _StokSatiri({
    required this.depoId,
    required this.urunId,
    required this.adet,
    this.urun,
  });

  @override
  Widget build(BuildContext context) {
    final dusuk = urun != null &&
        urun!.minStokSeviyesi > 0 &&
        adet <= urun!.minStokSeviyesi;
    final renk = dusuk ? Colors.red : null;

    return ListTile(
      leading: Icon(Icons.inventory_2, color: renk),
      title: Text(urun?.ad ?? urunId),
      subtitle: Text([
        if (urun?.kategori != null) urun!.kategori!,
        if (dusuk) 'Minimum seviyenin altında',
      ].join(' · ')),
      trailing: Text(
        '$adet',
        style:
            TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: renk),
      ),
      onTap: urun == null
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TopluGirisScreen(
                    onceSeciliUrunId: urun!.id,
                    onceSeciliDepoId: depoId,
                  ),
                ),
              ),
    );
  }
}

class _HareketListesi extends ConsumerWidget {
  final String depoId;
  const _HareketListesi({required this.depoId});

  static final _tarihFormat = DateFormat('dd.MM.yyyy HH:mm');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hareketlerAsync = ref.watch(depoHareketleriProvider(depoId));

    return hareketlerAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Hata: $e')),
      data: (hareketler) {
        if (hareketler.isEmpty) {
          return const Center(child: Text('Bu depoda henüz hareket yok'));
        }
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: hareketler.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final h = hareketler[i];
            final artis = h.miktar > 0;
            final renk = artis ? Colors.green.shade700 : Colors.red.shade700;

            return ListTile(
              leading: Icon(_ikon(h), color: renk),
              title: Text(h.urunAdi),
              subtitle: Text([
                if (h.seriNo != null) 'SN: ${h.seriNo}',
                _etiket(h),
                _tarihFormat.format(h.tarih),
                if (h.kullaniciAdi != null) h.kullaniciAdi!,
                if (h.not_ != null && h.not_!.isNotEmpty) h.not_!,
              ].join(' · ')),
              trailing: Text(
                '${artis ? '+' : ''}${h.miktar}',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 18, color: renk),
              ),
            );
          },
        );
      },
    );
  }

  IconData _ikon(HareketSatiri h) {
    switch (h.tip) {
      case HareketTipi.girisi:
        return Icons.arrow_downward;
      case HareketTipi.cikis:
        return Icons.arrow_upward;
      case HareketTipi.transfer:
        return Icons.swap_horiz;
      case HareketTipi.kullanim:
        return Icons.local_shipping_outlined;
      case HareketTipi.iade:
        return Icons.assignment_return_outlined;
    }
  }

  String _etiket(HareketSatiri h) {
    switch (h.tip) {
      case HareketTipi.girisi:
        return 'Giriş';
      case HareketTipi.cikis:
        return 'Çıkış';
      case HareketTipi.transfer:
        final yon = h.miktar > 0 ? '←' : '→';
        return 'Transfer $yon ${h.karsiDepoAdi ?? '-'}';
      case HareketTipi.iade:
        return 'İade ${h.miktar > 0 ? '←' : '→'} ${h.karsiDepoAdi ?? '-'}';
      case HareketTipi.kullanim:
        if (h.karsiDepoAdi != null) {
          return 'Kullanıma verildi ${h.miktar > 0 ? '←' : '→'} ${h.karsiDepoAdi}';
        }
        return 'Sahada kullanıldı: ${h.aracPlaka ?? h.kullanimYeri ?? '-'}';
    }
  }
}
