import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/models.dart';
import '../providers/app_providers.dart';
import '../screens/urun/urun_form_dialog.dart';
import 'renkler.dart';

/// Malzeme (kablo, adaptör…) miktarını sorar. [kutuDugmesi]: "+1 kutu".
Future<int?> malzemeMiktariSor(BuildContext context, Urun u,
    {int? mevcut, String? aciklama}) async {
  final ctrl = TextEditingController(text: mevcut == null ? '' : '$mevcut');
  final kutu = u.okutmaMiktari;
  final n = await showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(u.ad),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Miktar (${u.birim})',
                helperText: aciklama ??
                    (kutu > 1 ? '1 kutu / top = ${u.miktarMetni(kutu)}' : null),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v.trim())),
            ),
            if (kutu > 1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(spacing: 6, children: [
                  for (final k in [1, 2, 3])
                    ActionChip(
                      label: Text('$k kutu'),
                      onPressed: () => ctrl.text = '${k * kutu}',
                    ),
                ]),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
              child: const Text('Tamam')),
        ],
      ),
    ),
  );
  ctrl.dispose();
  return (n == null || n < 0) ? null : n;
}

/// Miktarla takip edilen ürünlerden birini seçtirir; listede yoksa
/// "+ Yeni malzeme tanımla" ile oradan çıkmadan tanımlanır. Ürün id'si döner.
Future<String?> malzemeSec(BuildContext context, WidgetRef ref) async {
  final urunler = (ref.read(urunlerStreamProvider).valueOrNull ?? <Urun>[])
      .where((u) => u.miktarli && !u.deleted)
      .toList()
    ..sort((a, b) => a.ad.compareTo(b.ad));
  final secim = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Malzeme seçin',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.add_circle, color: Renkler.okut),
              title: const Text('+ Yeni malzeme tanımla'),
              subtitle: const Text('Listede yoksa: ad, birim, kutu içeriği, '
                  'barkod'),
              onTap: () => Navigator.pop(ctx, ''),
            ),
            const Divider(height: 1),
            if (urunler.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Henüz miktarla takip edilen malzeme yok.'),
              ),
            for (final u in urunler)
              ListTile(
                leading: const Icon(Icons.cable_outlined, color: Renkler.urun),
                title: Text(u.ad),
                subtitle: Text([
                  u.birim,
                  if (u.okutmaMiktari > 1)
                    '1 kutu = ${u.miktarMetni(u.okutmaMiktari)}',
                  if (u.barkod != null) 'barkodlu',
                ].join(' · ')),
                onTap: () => Navigator.pop(ctx, u.id),
              ),
          ],
        ),
      ),
    ),
  );
  if (secim == null || !context.mounted) return null;
  if (secim.isNotEmpty) return secim;
  return urunFormDialog(context, ref, malzeme: true);
}

/// Listedeki malzeme kalemleri (dokununca miktar değişir, ✕ ile çıkar).
class MalzemeKalemleri extends StatelessWidget {
  const MalzemeKalemleri({
    super.key,
    required this.miktarlar,
    required this.urunler,
    required this.onDegisti,
    this.baslik,
  });

  final Map<String, int> miktarlar;
  final Map<String, Urun> urunler;

  /// Yeni miktar (0 = listeden çıkar).
  final void Function(String urunId, int miktar) onDegisti;
  final String? baslik;

  @override
  Widget build(BuildContext context) {
    if (miktarlar.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (baslik != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
            child: Text(baslik!,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.4,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        for (final e in miktarlar.entries)
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: const EdgeInsets.only(left: 4),
            leading: const Icon(Icons.cable_outlined, color: Renkler.urun),
            title: Text(urunler[e.key]?.ad ?? 'Malzeme',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(urunler[e.key]?.kutuluMetin(e.value) ?? '${e.value}'),
            onTap: urunler[e.key] == null
                ? null
                : () async {
                    final n = await malzemeMiktariSor(
                        context, urunler[e.key]!,
                        mevcut: e.value);
                    if (n != null) onDegisti(e.key, n);
                  },
            trailing: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Listeden çıkar',
              onPressed: () => onDegisti(e.key, 0),
            ),
          ),
      ],
    );
  }
}
