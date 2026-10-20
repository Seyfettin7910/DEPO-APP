import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/tarayici.dart';
import 'renkler.dart';

/// iPhone'da Safari'de, ana ekrana eklenmeden açıldıysa (bir kez) rehber.
bool get _iphoneSafari =>
    kIsWeb && iosTarayici() && tarayiciAdi() == 'Safari';

Future<void> anaEkranRehberiGerekirseGoster(BuildContext context) async {
  if (!_iphoneSafari || anaEkranda()) return;
  try {
    final p = await SharedPreferences.getInstance();
    if (p.getBool('ana_ekran_rehberi') == true) return;
    await p.setBool('ana_ekran_rehberi', true);
  } catch (_) {
    return;
  }
  if (context.mounted) await anaEkranRehberi(context);
}

/// Paylaş → Ana Ekrana Ekle adımları ve neden önemli olduğu.
Future<void> anaEkranRehberi(BuildContext context) {
  Widget adim(String no, String metin) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: Renkler.okut,
              child: Text(no,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(metin, style: const TextStyle(height: 1.35))),
          ],
        ),
      );
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.add_to_home_screen, color: Renkler.okut),
      title: const Text('iPhone\'da ana ekrana ekleyin'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            adim('1', 'Safari\'nin altındaki Paylaş düğmesine (yukarı ok '
                'çıkan kare) dokunun.'),
            adim('2', 'Listede aşağı kaydırıp "Ana Ekrana Ekle"yi seçin.'),
            adim('3', 'Sağ üstte "Ekle"ye dokunun.'),
            adim('4', 'Bundan sonra uygulamayı ana ekrandaki simgeden açın.'),
            const SizedBox(height: 6),
            const Text(
              'Neden önemli: bildirimler yalnızca bu şekilde gelir; Safari, '
              'bir süre açılmayan sitelerin telefonda sakladığı verileri '
              '(yarım işler, internetsiz kayıtlar) silebilir, ana ekrandakini '
              'silmez; kamera ve konum izni hatırlanır; uygulama tam ekran '
              'açılır.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Tamam')),
      ],
    ),
  );
}

/// Ayarlar'da gösterilsin mi (iPhone'da web).
bool get iphoneRehberiGoster => kIsWeb && iosTarayici();

/// iPhone'da Safari dışındaki tarayıcıda açıldıysa üstte uyarı şeridi.
class SafariUyarisi extends StatefulWidget {
  const SafariUyarisi({super.key});

  @override
  State<SafariUyarisi> createState() => _SafariUyarisiState();
}

class _SafariUyarisiState extends State<SafariUyarisi> {
  static bool _kapatildi = false; // bu oturumda kapatıldı

  @override
  Widget build(BuildContext context) {
    if (_kapatildi || !kIsWeb || !iosTarayici()) {
      return const SizedBox.shrink();
    }
    final ad = tarayiciAdi();
    if (ad.isEmpty || ad == 'Safari') return const SizedBox.shrink();
    return Material(
      color: Renkler.zilZemin,
      child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Renkler.urun),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Şu an $ad ile açtınız. Bildirimler ve "Ana Ekrana Ekle" '
                  'için uygulamayı Safari\'de açın.',
                  style: const TextStyle(fontSize: 13.5),
                ),
              ),
              IconButton(
                tooltip: 'Kapat',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _kapatildi = true),
              ),
            ],
          ),
      ),
    );
  }
}
