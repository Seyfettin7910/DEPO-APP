import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../screens/bildirim/bildirimler_screen.dart';

/// Üst çubuktaki zil: okunmamış bildirim sayısını gösterir.
class BildirimDugmesi extends ConsumerWidget {
  const BildirimDugmesi({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sayi = ref.watch(okunmamisBildirimProvider).valueOrNull ?? 0;
    return IconButton(
      tooltip: 'Bildirimler',
      icon: Badge(
        isLabelVisible: sayi > 0,
        label: Text(sayi > 99 ? '99+' : '$sayi'),
        child: Icon(sayi > 0
            ? Icons.notifications_active_outlined
            : Icons.notifications_none),
      ),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const BildirimlerScreen()),
      ),
    );
  }
}
