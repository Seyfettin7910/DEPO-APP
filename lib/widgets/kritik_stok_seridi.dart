import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../screens/rapor/rapor_onizleme_screen.dart';
import '../services/rapor/rapor_olusturucu.dart';

/// Minimum adedin altına inen ürün varsa ekranın üstünde uyarı şeridi.
/// Dokununca Kritik stok raporu açılır (PDF / Excel alınabilir).
class KritikStokSeridi extends ConsumerWidget {
  const KritikStokSeridi({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(kritikStoklarProvider).value ?? const [];
    if (liste.isEmpty) return const SizedBox.shrink();

    final tukenen = liste.where((k) => k.toplam == 0).length;
    final adlar = liste.take(3).map((k) => '${k.urunAdi} (${k.toplam})').join(', ');
    final renk = tukenen > 0 ? Colors.red.shade700 : Colors.orange.shade800;

    return Material(
      color: renk,
      child: InkWell(
        onTap: () async {
          final rapor =
              await RaporOlusturucu.kritikStok(ref.read(appDatabaseProvider));
          if (!context.mounted) return;
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RaporOnizlemeScreen(rapor: rapor)));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.warning_amber, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${liste.length} ürün kritik stokta'
                  '${tukenen > 0 ? ' ($tukenen tükendi)' : ''}: $adlar'
                  '${liste.length > 3 ? '…' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
