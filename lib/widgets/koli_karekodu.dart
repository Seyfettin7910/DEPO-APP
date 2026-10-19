import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/models.dart';
import '../providers/app_providers.dart';
import '../screens/cihaz/cihaz_detay_screen.dart';
import '../screens/cihaz/toplu_giris_screen.dart';
import '../screens/cihaz/toplu_transfer_screen.dart';

/// Koli karekodu okutulduğunda (içinde birden çok seri no) açılan özet:
/// hangi seri noların kayıtlı (nerede), hangilerinin kayıtsız olduğu.
/// "Depoya ekle" kayıtsızları, "Transfer et" kayıtlıları ilgili ekrana
/// hazır liste olarak götürür.
///
/// [ac]: yeni sayfayı açan fonksiyon (okutma ekranı kendi kamerasını
/// durdurup açar).
Future<void> koliKarekoduGoster(
  BuildContext context,
  WidgetRef ref,
  List<String> seriler, {
  required Future<void> Function(Widget ekran) ac,
}) async {
  final db = ref.read(appDatabaseProvider);
  final bilgiler = <String, CihazBilgi?>{};
  for (final s in seriler) {
    bilgiler[s] = await db.seriNoIleCihazBilgi(s);
  }
  if (!context.mounted) return;

  final yeni = [for (final s in seriler) if (bilgiler[s] == null) s];
  final kayitli = [for (final s in seriler) if (bilgiler[s] != null) s];
  final tasinabilir = [
    for (final s in kayitli)
      if (bilgiler[s]!.cihaz.durum == CihazDurumu.depoda &&
          !bilgiler[s]!.cihaz.arizali)
        s
  ];

  final secim = await showModalBottomSheet<Widget>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final tema = Theme.of(ctx);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx, kaydirma) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Koli karekodu · ${seriler.length} seri no',
                        style: tema.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: [
                  if (yeni.isNotEmpty)
                    Chip(
                      avatar: Icon(Icons.fiber_new,
                          size: 18, color: Colors.red.shade700),
                      label: Text('${yeni.length} kayıtsız'),
                    ),
                  if (kayitli.isNotEmpty)
                    Chip(
                      avatar: Icon(Icons.check_circle,
                          size: 18, color: Colors.green.shade700),
                      label: Text('${kayitli.length} kayıtlı'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: kaydirma,
                itemCount: seriler.length,
                itemBuilder: (ctx, i) {
                  final s = seriler[i];
                  final b = bilgiler[s];
                  if (b == null) {
                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.qr_code_2, color: Colors.red.shade700),
                      title: Text(s),
                      subtitle: const Text('Kayıtlı değil'),
                    );
                  }
                  return ListTile(
                    dense: true,
                    leading: Icon(cihazIkonu(b.cihaz), color: cihazRengi(b.cihaz)),
                    title: Text(s),
                    subtitle: Text('${b.urunAdi} · ${cihazKonumMetni(b)}',
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        Navigator.pop(ctx, CihazDetayScreen(cihazId: b.cihaz.id)),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    if (tasinabilir.isNotEmpty)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(
                              ctx, TopluTransferScreen(onceSeriNolari: tasinabilir)),
                          icon: const Icon(Icons.swap_horiz),
                          label: Text('Transfer (${tasinabilir.length})'),
                        ),
                      ),
                    if (tasinabilir.isNotEmpty && yeni.isNotEmpty)
                      const SizedBox(width: 10),
                    if (yeni.isNotEmpty)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(
                              ctx, TopluGirisScreen(onceSeriNolari: yeni)),
                          icon: const Icon(Icons.add_box_outlined),
                          label: Text('Depoya ekle (${yeni.length})'),
                        ),
                      ),
                    if (tasinabilir.isEmpty && yeni.isEmpty)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Kapat'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
  if (secim != null && context.mounted) await ac(secim);
}
