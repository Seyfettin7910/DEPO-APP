import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/app_providers.dart';
import '../services/oturum_kilidi.dart';
import '../services/supabase_service.dart';
import '../services/bildirim/web_bildirim.dart';
import 'bildirim_dugmesi.dart';
import 'renkler.dart';

/// Üst çubuktaki iki düğme: senkron göstergesi ve bildirim zili.
List<Widget> ustDugmeler() => const [
      SyncDurumDugmesi(),
      BildirimDugmesi(),
      SizedBox(width: 4),
    ];

/// Üst çubukta senkron durumu: simge + son senkron saati (ya da bekleyen
/// kayıt sayısı / çevrimdışı). Dokununca hemen senkronize eder.
/// Diğer menüler (yarım işler, güncelleme, yenilikler…) Ayarlar sekmesinde.
class SyncDurumDugmesi extends ConsumerWidget {
  const SyncDurumDugmesi({super.key});

  static String saatMetni(DateTime? t) {
    if (t == null) return '—';
    final simdi = DateTime.now();
    final bugun = DateTime(simdi.year, simdi.month, simdi.day);
    final gun = DateTime(t.year, t.month, t.day);
    final saat = DateFormat('HH:mm').format(t);
    if (gun == bugun) return saat;
    if (bugun.difference(gun).inDays == 1) return 'Dün $saat';
    return '${DateFormat('dd.MM').format(t)} $saat';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(syncDurumProvider);
    final cevrimdisi = d.hata?.startsWith('Çevrimdışı') ?? false;

    IconData ikon;
    Color renk;
    Color zemin;
    String metin;
    String ipucu;
    // 1.30.3: "Gönderiliyor…" yalnız gönderilecek kayıt varken; yalnız
    // sunucu denetleniyorsa simgenin yerinde küçük bir dönen halka.
    final denetleniyor = d.calisiyor && d.bekleyen == 0;
    if (d.calisiyor && d.bekleyen > 0) {
      ikon = Icons.sync;
      renk = Renkler.depo;
      zemin = Renkler.depoZemin;
      metin = 'Gönderiliyor…';
      ipucu = 'Senkronize ediliyor';
    } else if (cevrimdisi) {
      ikon = Icons.cloud_off;
      renk = Renkler.cikis;
      zemin = Renkler.cikisZemin;
      metin = 'Çevrimdışı';
      ipucu = d.hata!;
    } else if (d.bekleyen > 0) {
      ikon = Icons.cloud_upload_outlined;
      renk = Renkler.urun;
      zemin = Renkler.urunZemin;
      metin = '${d.bekleyen} bekliyor';
      ipucu = '${d.bekleyen} değişiklik gönderilecek';
    } else if (d.hata != null) {
      ikon = Icons.cloud_off;
      renk = Renkler.urun;
      zemin = Renkler.urunZemin;
      metin = 'Sorun';
      ipucu = d.hata!;
    } else {
      ikon = Icons.cloud_done_outlined;
      renk = Renkler.okut;
      zemin = Renkler.okutZemin;
      metin = saatMetni(d.sonBasari);
      ipucu = d.sonBasari == null
          ? 'Henüz senkronize edilmedi'
          : 'Güncel · son senkron ${DateFormat('dd.MM.yyyy HH:mm').format(d.sonBasari!)}';
    }
    if (denetleniyor) ipucu = 'Sunucu denetleniyor…';

    return Tooltip(
      message: ipucu,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: zemin,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () {
              ref.read(syncServiceProvider).syncNow(elle: true);
              if (d.hata != null) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text(d.hata!)));
              }
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (denetleniyor)
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: renk),
                      ),
                    )
                  else
                    Icon(ikon, color: renk, size: 22),
                  const SizedBox(width: 5),
                  Text(metin,
                      maxLines: 1,
                      style: TextStyle(
                          color: renk,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Onay sorup oturumu kapatır (internet yokken de çalışır).
Future<void> cikisYapOnayli(BuildContext context, WidgetRef ref) async {
  final bekleyen = ref.read(syncDurumProvider).bekleyen;
  final onay = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.logout),
      title: const Text('Çıkış yap'),
      content: Text(bekleyen > 0
          ? '$bekleyen değişiklik henüz sunucuya gönderilmedi. '
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
  if (onay != true) return;
  // Bu tarayıcıdaki bildirim aboneliği kapanır (oturum açıkken silinmeli).
  await WebBildirim.kapat().timeout(const Duration(seconds: 5),
      onTimeout: () {});
  await OturumKilidi.instance.kilitle();
  // Tam çıkış: sunucu oturumu da kapanır; arka plan kontrolü ve
  // bildirimler durur. (İnternet yoksa ekran yine de kilitlenir.)
  try {
    await SupabaseService.cikisYap().timeout(const Duration(seconds: 8));
  } catch (_) {}
}
