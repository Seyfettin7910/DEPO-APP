import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/models.dart';
import '../providers/app_providers.dart';
import '../services/ses_servisi.dart';

const cihazSilmeSebepleri = [
  'Yanlış kayıt / hatalı okutma',
  'Mükerrer kayıt',
  'Kayıp / çalıntı',
  'Diğer',
];

const urunSilmeSebepleri = [
  'Yanlış tanımlandı',
  'Mükerrer ürün',
  'Artık kullanılmıyor',
  'Diğer',
];

/// Silme sebebini ve açıklamayı sorar. Vazgeçilirse null.
Future<(String, String?)?> silmeNedeniSor(
  BuildContext context, {
  required String baslik,
  required String aciklama,
  required List<String> sebepler,
}) {
  String? sebep;
  String? hata;
  final notCtrl = TextEditingController();
  return showDialog<(String, String?)>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        scrollable: true,
        icon: Icon(Icons.delete_outline,
            color: Theme.of(ctx).colorScheme.error, size: 32),
        title: Text(baslik),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(aciklama),
            const SizedBox(height: 12),
            Text('Silme nedeni', style: Theme.of(ctx).textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final s in sebepler)
                  ChoiceChip(
                    label: Text(s),
                    selected: sebep == s,
                    onSelected: (sec) => setState(() {
                      sebep = sec ? s : null;
                      hata = null;
                    }),
                  ),
              ],
            ),
            TextField(
              controller: notCtrl,
              decoration: InputDecoration(
                labelText:
                    sebep == 'Diğer' ? 'Açıklama (zorunlu)' : 'Açıklama (opsiyonel)',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Silme işlemi, nedeni ve yapan kişiyle birlikte hareket '
              'kayıtlarına yazılır. Hareket kayıtları silinemez.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            if (hata != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(hata!,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () {
              if (sebep == null) {
                setState(() => hata = 'Silme nedenini seçin');
                return;
              }
              final not_ = notCtrl.text.trim();
              if (sebep == 'Diğer' && not_.isEmpty) {
                setState(() => hata = '"Diğer" için açıklama yazın');
                return;
              }
              Navigator.pop(ctx, (sebep!, not_.isEmpty ? null : not_));
            },
            child: const Text('Sil'),
          ),
        ],
      ),
    ),
  );
}

void _mesaj(BuildContext context, String metin, {bool hata = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(metin),
      backgroundColor: hata ? Colors.red.shade700 : null,
    ));
}

/// Seri numaralı cihazı (sebep sorarak) siler.
Future<bool> cihazSilAkisi(
    BuildContext context, WidgetRef ref, CihazBilgi bilgi) async {
  final sonuc = await silmeNedeniSor(
    context,
    baslik: 'Cihazı sil',
    aciklama: '${bilgi.urunAdi}\nSN: ${bilgi.cihaz.seriNo}\n\n'
        'Cihaz listelerden ve stoktan kalkar. Aynı seri no ileride '
        'yeniden girilebilir.',
    sebepler: cihazSilmeSebepleri,
  );
  if (sonuc == null || !context.mounted) return false;
  try {
    await ref.read(appDatabaseProvider).cihazSil(
          bilgi.cihaz.id,
          sebep: sonuc.$1,
          not_: sonuc.$2,
          kullaniciId: ref.read(aktifKullaniciIdProvider) ?? 'demo-kullanici',
        );
    SesServisi.basari();
    if (context.mounted) _mesaj(context, '${bilgi.cihaz.seriNo} silindi');
    return true;
  } catch (e) {
    SesServisi.hata();
    if (context.mounted) {
      _mesaj(context, e is StateError ? e.message : 'Silinemedi: $e', hata: true);
    }
    return false;
  }
}

/// Ürünü (modeli) sebep sorarak siler.
Future<bool> urunSilAkisi(BuildContext context, WidgetRef ref, Urun urun) async {
  final sonuc = await silmeNedeniSor(
    context,
    baslik: 'Ürünü sil',
    aciklama: '${urun.ad}${urun.kategori == null ? '' : ' (${urun.kategori})'}\n\n'
        'Depoda, araçta veya sahada cihazı olan ürün silinemez. Geçmiş '
        'kayıtlar ve raporlar korunur.',
    sebepler: urunSilmeSebepleri,
  );
  if (sonuc == null || !context.mounted) return false;
  try {
    await ref.read(appDatabaseProvider).urunSil(
          urun.id,
          sebep: sonuc.$1,
          not_: sonuc.$2,
          kullaniciId: ref.read(aktifKullaniciIdProvider) ?? 'demo-kullanici',
        );
    SesServisi.basari();
    if (context.mounted) _mesaj(context, '${urun.ad} silindi');
    return true;
  } catch (e) {
    SesServisi.hata();
    if (context.mounted) {
      _mesaj(context, e is StateError ? e.message : 'Silinemedi: $e', hata: true);
    }
    return false;
  }
}

/// Basılı tutunca açılan seçenek menüsü.
Future<String?> secenekMenusu(BuildContext context,
    {required String baslik, required List<(String, IconData, String)> secenekler}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(baslik,
                style: Theme.of(ctx).textTheme.titleMedium,
                textAlign: TextAlign.center),
          ),
          for (final s in secenekler)
            ListTile(
              leading: Icon(s.$2,
                  color: s.$1 == 'sil' ? Theme.of(ctx).colorScheme.error : null),
              title: Text(s.$3,
                  style: s.$1 == 'sil'
                      ? TextStyle(color: Theme.of(ctx).colorScheme.error)
                      : null),
              onTap: () => Navigator.pop(ctx, s.$1),
            ),
        ],
      ),
    ),
  );
}
