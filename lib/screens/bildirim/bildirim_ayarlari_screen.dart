import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/models.dart';
import '../../providers/app_providers.dart';
import '../../services/bildirim/bildirim_ayarlari.dart';
import '../../services/bildirim/bildirim_gosterici.dart';
import '../../services/bildirim/bildirim_motoru.dart';
import '../../widgets/depo_secici.dart';
import 'bildirimler_screen.dart';

/// Bu telefonda hangi bildirimlerin geleceği (her kullanıcı kendisi seçer).
class BildirimAyarlariScreen extends ConsumerStatefulWidget {
  const BildirimAyarlariScreen({super.key});

  @override
  ConsumerState<BildirimAyarlariScreen> createState() =>
      _BildirimAyarlariScreenState();
}

class _BildirimAyarlariScreenState
    extends ConsumerState<BildirimAyarlariScreen> {
  BildirimAyarlari? _ayar;

  @override
  void initState() {
    super.initState();
    BildirimAyarlari.yukle().then((a) {
      if (mounted) setState(() => _ayar = a);
    });
  }

  Future<void> _degisti(void Function(BildirimAyarlari a) f) async {
    final a = _ayar!;
    setState(() => f(a));
    await a.kaydet();
  }

  Widget _gunSecici({
    required String etiket,
    required int deger,
    required List<int> secenekler,
    required ValueChanged<int> degisti,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
      child: Row(
        children: [
          Expanded(child: Text(etiket, style: const TextStyle(fontSize: 13))),
          DropdownButton<int>(
            value: secenekler.contains(deger) ? deger : secenekler.first,
            items: [
              for (final g in secenekler)
                DropdownMenuItem(value: g, child: Text('$g gün')),
            ],
            onChanged: (v) {
              if (v != null) degisti(v);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = _ayar;
    final tema = Theme.of(context);
    if (a == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bildirim ayarları')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final depolar = ref.watch(depolarStreamProvider).value ?? <Depo>[];
    final gruplar = <String, List<BildirimTuru>>{};
    for (final t in BildirimTuru.values) {
      gruplar.putIfAbsent(t.grup, () => []).add(t);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Bildirim ayarları')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              sistemBildirimiVar
                  ? 'Seçtikleriniz bu telefona bildirim olarak gelir; uygulama '
                      'kapalıyken de yaklaşık 15 dakikada bir kontrol edilir. '
                      'Kendi yaptığınız işlemler için bildirim gelmez.'
                  : 'Web sürümünde bildirimler yalnızca sayfa açıkken, üstteki '
                      'zil simgesinde görünür. Telefona bildirim için Android '
                      'uygulamasını kullanın.',
              style: tema.textTheme.bodySmall,
            ),
          ),
          for (final g in gruplar.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(g.key,
                  style: tema.textTheme.titleSmall
                      ?.copyWith(color: tema.colorScheme.primary)),
            ),
            for (final t in g.value) ...[
              SwitchListTile(
                secondary: Icon(bildirimIkonu(t), color: bildirimRengi(t)),
                title: Text(t.etiket),
                subtitle: Text(t.aciklama),
                value: a.acikMi(t),
                onChanged: (v) => _degisti((x) => v ? x.acik.add(t) : x.acik.remove(t)),
              ),
              if (t == BildirimTuru.servisGecikmesi && a.acikMi(t))
                _gunSecici(
                  etiket: 'Kaç gün sonra uyarsın?',
                  deger: a.servisGecikmeGun,
                  secenekler: const [3, 7, 10, 15, 20, 30, 45, 60],
                  degisti: (v) => _degisti((x) => x.servisGecikmeGun = v),
                ),
              if (t == BildirimTuru.garantiBitiyor && a.acikMi(t))
                _gunSecici(
                  etiket: 'Bitişine kaç gün kala?',
                  deger: a.garantiGun,
                  secenekler: const [7, 15, 30, 60, 90],
                  degisti: (v) => _degisti((x) => x.garantiGun = v),
                ),
              if (t == BildirimTuru.cihazGeldi && a.acikMi(t))
                Padding(
                  padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.izlenenDepolar.isEmpty
                            ? 'Tüm depo ve araçlar izleniyor. Yalnızca kendi '
                                'aracınız / deponuz için seçin:'
                            : 'Yalnızca seçilenler izleniyor:',
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final d in depolar)
                            FilterChip(
                              avatar: Icon(depoIkonu(d), size: 16),
                              label: Text(d.ad),
                              selected: a.izlenenDepolar.contains(d.id),
                              onSelected: (s) => _degisti((x) => s
                                  ? x.izlenenDepolar.add(d.id)
                                  : x.izlenenDepolar.remove(d.id)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (t == BildirimTuru.gunlukOzet && a.acikMi(t))
                Padding(
                  padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
                  child: Row(
                    children: [
                      const Expanded(
                          child: Text('Saat', style: TextStyle(fontSize: 13))),
                      TextButton.icon(
                        icon: const Icon(Icons.schedule, size: 18),
                        label: Text(
                            '${a.ozetSaat.toString().padLeft(2, '0')}:${a.ozetDakika.toString().padLeft(2, '0')}'),
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: context,
                            initialTime:
                                TimeOfDay(hour: a.ozetSaat, minute: a.ozetDakika),
                          );
                          if (t != null) {
                            await _degisti((x) {
                              x.ozetSaat = t.hour;
                              x.ozetDakika = t.minute;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ],
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Test bildirimi gönder'),
                  onPressed: () async {
                    await bildirimIzniIste();
                    await BildirimMotoru.test(ref.read(appDatabaseProvider));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Test bildirimi gönderildi')));
                    }
                  },
                ),
                if (sistemBildirimiVar)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.battery_saver_outlined),
                    label: const Text('Pil kısıtlamasını kaldır'),
                    onPressed: pilAyariniAc,
                  ),
              ],
            ),
          ),
          if (sistemBildirimiVar)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Uygulama kapalıyken bildirim gelmiyor veya geç geliyorsa '
                '"Pil kısıtlamasını kaldır" ile uygulamaya izin verin '
                '(özellikle Xiaomi, Oppo, Huawei telefonlarda gerekir).',
                style: tema.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
