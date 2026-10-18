import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/app_providers.dart';
import '../services/supabase_service.dart';

/// AppBar'da senkron durumunu gösterir; menüden elle senkronize etme ve
/// çıkış yapma sağlar.
class SyncDurumDugmesi extends ConsumerWidget {
  const SyncDurumDugmesi({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(syncDurumProvider);

    IconData ikon;
    Color? renk;
    String ipucu;
    if (d.calisiyor) {
      ikon = Icons.sync;
      ipucu = 'Senkronize ediliyor...';
    } else if (d.hata != null) {
      ikon = Icons.cloud_off;
      renk = Colors.orange.shade800;
      ipucu = 'Senkron sorunu';
    } else if (d.bekleyen > 0) {
      ikon = Icons.cloud_upload_outlined;
      renk = Colors.orange.shade800;
      ipucu = '${d.bekleyen} değişiklik gönderilecek';
    } else {
      ikon = Icons.cloud_done_outlined;
      renk = Colors.green.shade700;
      ipucu = 'Güncel';
    }

    return PopupMenuButton<String>(
      tooltip: ipucu,
      icon: Badge(
        isLabelVisible: d.bekleyen > 0,
        label: Text('${d.bekleyen}'),
        child: Icon(ikon, color: renk),
      ),
      onSelected: (v) async {
        if (v == 'sync') {
          ref.read(syncServiceProvider).syncNow();
        } else if (v == 'cikis') {
          final onay = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Çıkış yap'),
              content: Text(d.bekleyen > 0
                  ? '${d.bekleyen} değişiklik henüz sunucuya gönderilmedi. '
                      'Telefonda kalır, tekrar giriş yapınca gönderilir.'
                  : 'Oturum kapatılacak.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('İptal')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Çıkış yap')),
              ],
            ),
          );
          if (onay == true) await SupabaseService.cikisYap();
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          enabled: false,
          child: Text(
            [
              SupabaseService.kullanici?.email ?? '',
              if (d.bekleyen > 0) 'Bekleyen: ${d.bekleyen}',
              d.sonBasari == null
                  ? 'Henüz senkronize edilmedi'
                  : 'Son senkron: ${DateFormat('HH:mm:ss').format(d.sonBasari!)}',
              if (d.hata != null) d.hata!,
            ].where((e) => e.isNotEmpty).join('\n'),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        const PopupMenuItem(value: 'sync', child: Text('Şimdi senkronize et')),
        const PopupMenuItem(value: 'cikis', child: Text('Çıkış yap')),
      ],
    );
  }
}
