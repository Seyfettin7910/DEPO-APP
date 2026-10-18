import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/models.dart';
import '../../providers/app_providers.dart';
import '../../services/ses_servisi.dart';
import '../../widgets/barkod_okuyucu_sayfasi.dart';
import 'cihaz_detay_screen.dart';
import '../../widgets/silme_islemleri.dart';
import '../urun/urun_form_dialog.dart';

/// Seri numarası (veya model, depo, araç/yer) yazarak ya da okutarak arama.
/// Sonuçta cihazın hangi modele ait olduğu ve şu an hangi depoda / hangi
/// araçta olduğu görünür. Arama kutusu boşken model bazlı adetler listelenir.
class CihazAraScreen extends ConsumerStatefulWidget {
  const CihazAraScreen({super.key});

  @override
  ConsumerState<CihazAraScreen> createState() => _CihazAraScreenState();
}

class _CihazAraScreenState extends ConsumerState<CihazAraScreen> {
  final _ctrl = TextEditingController();
  String _sorgu = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _okut() async {
    final kod = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarkodOkuyucuSayfasi()),
    );
    if (kod == null || !mounted) return;

    final bilgi =
        await ref.read(appDatabaseProvider).seriNoIleCihazBilgi(kod);
    if (!mounted) return;
    setState(() {
      _ctrl.text = kod;
      _sorgu = kod.trim();
    });
    if (bilgi == null) {
      SesServisi.hata();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Kayıtlı cihaz bulunamadı: $kod'),
          backgroundColor: Colors.red.shade700,
        ));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => CihazDetayScreen(cihazId: bilgi.cihaz.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cihaz Ara')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _ctrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Seri no, model, depo, plaka, mahalle / köy, ilçe',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_sorgu.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() {
                          _ctrl.clear();
                          _sorgu = '';
                        }),
                      ),
                    IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      tooltip: 'Seri no okut',
                      onPressed: _okut,
                    ),
                  ],
                ),
              ),
              onChanged: (v) => setState(() => _sorgu = v.trim()),
            ),
          ),
          Expanded(
            child: _sorgu.isEmpty
                ? const _ModelAdetleri()
                : _Sonuclar(sorgu: _sorgu),
          ),
        ],
      ),
    );
  }
}

class _Sonuclar extends ConsumerWidget {
  final String sorgu;
  const _Sonuclar({required this.sorgu});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(cihazAraProvider(sorgu));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Hata: $e')),
      data: (liste) {
        if (liste.isEmpty) {
          return const Center(child: Text('Eşleşen cihaz yok'));
        }
        return ListView.separated(
          itemCount: liste.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final b = liste[i];
            final renk = cihazRengi(b.cihaz);
            return ListTile(
              leading: Icon(cihazIkonu(b.cihaz), color: renk),
              title: Text(b.urunAdi),
              subtitle: Text('SN: ${b.cihaz.seriNo}\n${cihazKonumMetni(b)}'),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => CihazDetayScreen(cihazId: b.cihaz.id)),
              ),
              onLongPress: () async {
                final secim = await secenekMenusu(context,
                    baslik: '${b.urunAdi}\nSN: ${b.cihaz.seriNo}',
                    secenekler: const [
                      ('ac', Icons.open_in_new, 'Cihaz kartını aç'),
                      ('sil', Icons.delete_outline, 'Cihazı sil'),
                    ]);
                if (!context.mounted) return;
                if (secim == 'ac') {
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => CihazDetayScreen(cihazId: b.cihaz.id)));
                } else if (secim == 'sil') {
                  await cihazSilAkisi(context, ref, b);
                }
              },
            );
          },
        );
      },
    );
  }
}

/// Arama boşken: her modelden toplam kaç adet depoda.
class _ModelAdetleri extends ConsumerWidget {
  const _ModelAdetleri();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urunler = ref.watch(urunlerStreamProvider).value ?? <Urun>[];
    final toplamlar =
        ref.watch(urunToplamStoklariProvider).value ?? <String, int>{};

    if (urunler.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Seri numarasını yazın ya da kamera simgesiyle okutun.\n'
            'Cihazın hangi depoda veya hangi araçta olduğunu görürsünüz.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Seri numarasını yazın ya da okutun. Aşağıda modellere göre depodaki adetler var.',
          ),
        ),
        for (final u in urunler)
          ListTile(
            leading: const Icon(Icons.qr_code_2),
            title: Text(u.ad),
            subtitle: u.kategori == null ? null : Text(u.kategori!),
            trailing: Text(
              '${toplamlar[u.id] ?? 0}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            onLongPress: () async {
              final secim = await secenekMenusu(context,
                  baslik: u.ad,
                  secenekler: const [
                    ('duzenle', Icons.edit_outlined, 'Düzenle'),
                    ('sil', Icons.delete_outline, 'Ürünü sil'),
                  ]);
              if (!context.mounted) return;
              if (secim == 'duzenle') {
                urunFormDialog(context, ref, mevcut: u);
              } else if (secim == 'sil') {
                await urunSilAkisi(context, ref, u);
              }
            },
          ),
      ],
    );
  }
}
