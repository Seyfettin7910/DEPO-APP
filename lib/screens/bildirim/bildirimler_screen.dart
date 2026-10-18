import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/app_providers.dart';
import '../../services/bildirim/bildirim_ayarlari.dart';
import '../../services/bildirim/bildirim_motoru.dart';
import 'bildirim_ayarlari_screen.dart';

IconData bildirimIkonu(BildirimTuru? t) => switch (t) {
      BildirimTuru.kritikStok => Icons.warning_amber,
      BildirimTuru.yeniAriza => Icons.build_outlined,
      BildirimTuru.servisGecikmesi => Icons.hourglass_bottom,
      BildirimTuru.garantiBitiyor => Icons.verified_user_outlined,
      BildirimTuru.cihazGeldi => Icons.local_shipping_outlined,
      BildirimTuru.depoyaGiris => Icons.move_to_inbox_outlined,
      BildirimTuru.hurdaSilme => Icons.recycling,
      BildirimTuru.servisDonus => Icons.assignment_turned_in_outlined,
      BildirimTuru.hataliSifre => Icons.gpp_maybe_outlined,
      BildirimTuru.yeniIpGiris => Icons.login,
      BildirimTuru.gonderilmemis => Icons.cloud_off,
      BildirimTuru.gunlukOzet => Icons.summarize_outlined,
      null => Icons.notifications_none,
    };

Color bildirimRengi(BildirimTuru? t) => switch (t) {
      BildirimTuru.kritikStok ||
      BildirimTuru.hataliSifre ||
      BildirimTuru.gonderilmemis =>
        Colors.red.shade700,
      BildirimTuru.yeniAriza ||
      BildirimTuru.servisGecikmesi ||
      BildirimTuru.garantiBitiyor =>
        Colors.orange.shade800,
      BildirimTuru.hurdaSilme => Colors.brown.shade600,
      BildirimTuru.yeniIpGiris => Colors.purple.shade600,
      _ => const Color(0xFF2E6F40),
    };

/// Uygulama içi bildirim listesi (bu telefonda tutulur).
class BildirimlerScreen extends ConsumerStatefulWidget {
  const BildirimlerScreen({super.key});

  @override
  ConsumerState<BildirimlerScreen> createState() => _BildirimlerScreenState();
}

class _BildirimlerScreenState extends ConsumerState<BildirimlerScreen> {
  static final _tarih = DateFormat('dd.MM.yyyy HH:mm');
  Set<int> _yeniler = {};

  @override
  void initState() {
    super.initState();
    // Açılınca okunmamışlar vurgulanır, sonra hepsi okundu sayılır.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final db = ref.read(appDatabaseProvider);
      final liste = await db.bildirimListesi();
      if (!mounted) return;
      setState(() => _yeniler = {
            for (final b in liste)
              if (b['okundu'] == 0) (b['id'] as num).toInt(),
          });
      await db.bildirimleriOkunduYap();
    });
  }

  Future<void> _temizle() async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bildirimleri temizle'),
        content: const Text('Bu telefondaki bildirim listesi silinir. '
            'Hareket kayıtları ve raporlar etkilenmez.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Temizle')),
        ],
      ),
    );
    if (onay == true) await ref.read(appDatabaseProvider).bildirimleriTemizle();
  }

  @override
  Widget build(BuildContext context) {
    final liste = ref.watch(bildirimListesiProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bildirimler'),
        actions: [
          if (liste.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Listeyi temizle',
              onPressed: _temizle,
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Bildirim ayarları',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const BildirimAyarlariScreen())),
          ),
        ],
      ),
      body: liste.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.notifications_none, size: 56),
                    const SizedBox(height: 8),
                    const Text('Henüz bildirim yok', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const BildirimAyarlariScreen())),
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('Hangi bildirimler gelsin?'),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              itemCount: liste.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final b = liste[i];
                final tur = bildirimTuruCoz(b['tur']);
                final yeni = _yeniler.contains((b['id'] as num).toInt());
                return ListTile(
                  tileColor: yeni
                      ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.35)
                      : null,
                  leading: Icon(bildirimIkonu(tur), color: bildirimRengi(tur)),
                  title: Text('${b['baslik']}',
                      style: TextStyle(
                          fontWeight: yeni ? FontWeight.bold : FontWeight.w500)),
                  subtitle: Text(
                    '${b['govde']}\n${_tarih.format(DateTime.fromMillisecondsSinceEpoch((b['tarih'] as num).toInt()))}',
                  ),
                  isThreeLine: true,
                );
              },
            ),
    );
  }
}
