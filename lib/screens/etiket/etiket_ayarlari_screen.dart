import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart';
import '../../providers/app_providers.dart';
import '../../widgets/kod_yardimci.dart';
import 'etiket_sablon_screen.dart';

/// Kurum kodları ve kurum genelindeki etiket ayarları (doğrulama, engel).
class EtiketAyarlariScreen extends ConsumerWidget {
  const EtiketAyarlariScreen({super.key});

  Future<void> _kodDuzenle(BuildContext context, WidgetRef ref,
      [KurumKodu? mevcut]) async {
    final kodCtrl = TextEditingController(text: mevcut?.kod ?? '');
    final adCtrl = TextEditingController(text: mevcut?.ad ?? '');
    var aktif = mevcut?.aktif ?? true;
    String? hata;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(mevcut == null ? 'Kurum kodu ekle' : 'Kurum kodu'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: kodCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Kod (ör. BLD veya BLD-BIM)',
                    helperText: 'Harf, rakam ve tire · en fazla 16 karakter',
                    errorText: hata,
                  ),
                ),
                TextField(
                  controller: adCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Açıklama (ör. Bilgi İşlem Müdürlüğü)'),
                ),
                if (mevcut != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: aktif,
                    title: const Text('Kullanımda'),
                    subtitle: const Text(
                        'Pasif kod yeni girişlerde seçilemez; üretilmiş '
                        'etiketler geçerli kalır.'),
                    onChanged: (v) => setState(() => aktif = v),
                  ),
                if (mevcut != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Kodu değiştirmek daha önce üretilmiş etiketleri '
                      'değiştirmez; yalnızca yeni üretilenler yeni kodu alır.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
            FilledButton(
              onPressed: () async {
                try {
                  await ref.read(appDatabaseProvider).kurumKoduKaydet(
                      id: mevcut?.id,
                      kod: kodCtrl.text,
                      ad: adCtrl.text,
                      aktif: aktif);
                  if (ctx.mounted) Navigator.pop(ctx);
                } on StateError catch (e) {
                  setState(() => hata = e.message);
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    kodCtrl.dispose();
    adCtrl.dispose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kodlar = ref.watch(kurumKodlariProvider).value ?? const <KurumKodu>[];
    final ayar = ref.watch(etiketAyarlariProvider).value ?? const EtiketAyarlari();
    final db = ref.read(appDatabaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Etiket ayarları')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _kodDuzenle(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Kurum kodu'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          const ListTile(
            title: Text('Kurum kodları',
                style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
                'Depoya girişte seçilen kurum koduyla her cihaza benzersiz '
                'bir kod üretilir: KOD-XXXXXXXX (ör. BLD-BIM-7K3Q9X2M).'),
          ),
          if (kodlar.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('Henüz kurum kodu yok. "+ Kurum kodu" ile ekleyin.'),
            ),
          for (final k in kodlar)
            ListTile(
              leading: Icon(Icons.badge_outlined,
                  color: k.aktif ? null : Theme.of(context).disabledColor),
              title: Text(k.kod,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: k.aktif ? null : Theme.of(context).disabledColor)),
              subtitle: Text([
                if (k.ad.isNotEmpty) k.ad,
                if (!k.aktif) 'pasif',
              ].join(' · ')),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _kodDuzenle(context, ref, k),
            ),
          const Divider(height: 32),
          const ListTile(
            title: Text('Kurum genelinde',
                style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Bu ayarlar herkeste aynıdır (sunucuda tutulur).'),
          ),
          SwitchListTile(
            value: ayar.dogrulama,
            title: const Text('Yapıştırma doğrulaması'),
            subtitle: const Text(
                'Basılan etiket yapıştırıldıktan sonra telefonla etiket + '
                'cihazın seri nosu okutulup eşleşme kontrol edilir.'),
            onChanged: (v) =>
                db.kurumAyariYaz(EtiketAyarlari.dogrulamaAnahtari, v ? '1' : '0'),
          ),
          SwitchListTile(
            value: ayar.engel,
            title: const Text('Doğrulanmamış etiketli cihazı engelle'),
            subtitle: Text(ayar.dogrulama
                ? 'Açıksa etiketi basılmış ama doğrulanmamış (veya uyuşmazlık '
                    'kaydı olan) cihaz transfer edilemez, araca yüklenemez, '
                    'montajda kullanılamaz. Arıza / servis / sayım serbesttir.'
                : 'Önce yapıştırma doğrulamasını açın.'),
            onChanged: ayar.dogrulama
                ? (v) async {
                    if (v) {
                      final tamam = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Engel açılsın mı?'),
                          content: const Text(
                              'Etiketi basılmış ama doğrulanmamış cihazlar, '
                              'etiketleri doğrulanana kadar transfer edilemez, '
                              'araca yüklenemez ve montajda kullanılamaz. '
                              'Bu ayar herkes için geçerlidir.'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Vazgeç')),
                            FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Aç')),
                          ],
                        ),
                      );
                      if (tamam != true) return;
                    }
                    await db.kurumAyariYaz(
                        EtiketAyarlari.engelAnahtari, v ? '1' : '0');
                  }
                : null,
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.straighten),
            title: const Text('Etiket kağıdı ve hizalama'),
            subtitle: Text(bilgisayarTarayicisi
                ? 'Bu bilgisayarın etiket ölçüleri, kaydırma ayarı, çizgi barkod'
                : 'Etiketler bilgisayardan basılır; bu ayar bilgisayarda yapılır'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EtiketSablonScreen())),
          ),
          const ListTile(
            leading: Icon(Icons.notifications_outlined),
            title: Text('Basım bildirimi'),
            subtitle: Text('Etiket basım kuyruğu bildirimi, bildirim ayarlarında '
                '"Basım bekleyen etiket" açılarak alınır (zil simgesi → ayarlar).'),
          ),
        ],
      ),
    );
  }
}
