import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/guncelleme_servisi.dart';
import '../services/surum_notlari.dart';

const _gorulenAnahtari = 'yenilikler_gorulen_surum';

/// Güncellemeden sonraki ilk açılışta bu sürümün notlarını bir kez gösterir.
Future<void> yenilikleriGerekirseGoster(BuildContext context) async {
  final surum = GuncellemeServisi.mevcutSurum;
  if (surum.isEmpty) return;
  final not = surumNotlari.where((n) => n.surum == surum).firstOrNull;
  if (not == null) return;
  try {
    final p = await SharedPreferences.getInstance();
    if (p.getString(_gorulenAnahtari) == surum) return;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.new_releases_outlined),
        title: Text('Sürüm $surum: neler var?'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(child: _NotIcerigi(not: not)),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
    await p.setString(_gorulenAnahtari, surum);
  } catch (_) {}
}

/// Tüm sürüm notları (menüden açılır).
class YeniliklerScreen extends StatelessWidget {
  const YeniliklerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mevcut = GuncellemeServisi.mevcutSurum;
    return Scaffold(
      appBar: AppBar(title: const Text('Yenilikler')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (mevcut.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Kullandığınız sürüm: $mevcut',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          for (final n in surumNotlari)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sürüm ${n.surum} · ${n.tarih}',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _NotIcerigi(not: n),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NotIcerigi extends StatelessWidget {
  const _NotIcerigi({required this.not});
  final SurumNotu not;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final b in not.bolumler) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(b.baslik,
                style: tema.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: tema.colorScheme.primary)),
          ),
          for (final m in b.maddeler)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(child: Text(m)),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
