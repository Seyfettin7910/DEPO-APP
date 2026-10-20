import 'dart:async';

import 'package:flutter/material.dart';

import '../database/app_database.dart';
import '../database/models.dart';
import '../screens/malzeme/malzeme_islem_screen.dart';
import '../screens/cihaz/cihaz_detay_screen.dart';
import '../screens/cihaz/toplu_giris_screen.dart';
import '../screens/cihaz/toplu_transfer_screen.dart';
import '../screens/cihaz/montaj_screen.dart';
import '../screens/rapor/sayim_screen.dart';
import '../services/taslak_servisi.dart';

IconData taslakIkonu(String tur) => switch (tur) {
      'sayim' => Icons.fact_check_outlined,
      'toplu_transfer' => Icons.swap_horiz,
      'toplu_kullanim' => Icons.local_shipping_outlined,
      'toplu_iade' => Icons.assignment_return_outlined,
      'giris' => Icons.add_box_outlined,
      'saha' => Icons.task_alt,
      'montaj' => Icons.place_outlined,
      'geri_al' => Icons.assignment_return_outlined,
      'ariza' => Icons.build_outlined,
      'servis_gonder' => Icons.send_outlined,
      'servis_sonuc' => Icons.assignment_turned_in_outlined,
      'hurda' => Icons.recycling,
      _ when tur.startsWith('malzeme_') => Icons.cable_outlined,
      _ => Icons.restore_page_outlined,
    };

/// Taslağın ekranını (ya da cihaz kartındaki penceresini) açar.
Future<void> taslagaDevamEt(BuildContext context, Taslak t) {
  final Widget ekran;
  if (t.pencere) {
    ekran = CihazDetayScreen(cihazId: t.cihazId!, acilacakTaslak: t.tur);
  } else {
    switch (t.tur) {
      case 'sayim':
        ekran = const SayimScreen(taslaktan: true);
      case 'toplu_transfer':
        ekran = const TopluTransferScreen(taslaktan: true);
      case 'toplu_kullanim':
        ekran = const TopluTransferScreen(
            tip: HareketTipi.kullanim, taslaktan: true);
      case 'toplu_iade':
        ekran =
            const TopluTransferScreen(tip: HareketTipi.iade, taslaktan: true);
      case 'giris':
        ekran = const TopluGirisScreen(taslaktan: true);
      case 'montaj':
        ekran = const MontajScreen(taslaktan: true);
      default:
        final islem = MalzemeIslemi.values
            .where((m) => t.tur == 'malzeme_${m.name}')
            .firstOrNull;
        if (islem == null) return Future.value();
        ekran = MalzemeIslemScreen(islem: islem, taslaktan: true);
    }
  }
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => ekran));
}

/// Açılışta (ve menüden) yarım kalan işleri listeler: Devam et / Sil.
/// [bosIseHaberVer]: hiç taslak yoksa kısa bilgi gösterilir (menüden).
Future<void> yarimIsleriGoster(BuildContext context,
    {bool bosIseHaberVer = false}) async {
  var liste = await TaslakServisi.hepsi();
  if (!context.mounted) return;
  if (liste.isEmpty) {
    if (bosIseHaberVer) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yarım kalan iş yok')));
    }
    return;
  }
  final secilen = await showDialog<Taslak>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        icon: const Icon(Icons.restore_page_outlined),
        title: const Text('Yarım kalan işler'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                    'Uygulama kapanmadan, güncellenmeden ya da çökmeden önce '
                    'bitmemiş işler. 7 gün saklanır.'),
                const SizedBox(height: 8),
                for (final t in liste)
                  Card(
                    margin: const EdgeInsets.only(top: 6),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(taslakIkonu(t.tur), size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(t.baslik,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 28, top: 2),
                            child: Text('${t.ozet} · ${t.zamanMetni}',
                                style: Theme.of(ctx).textTheme.bodySmall),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () async {
                                  await TaslakServisi.sil(t.anahtar);
                                  liste = [
                                    for (final x in liste)
                                      if (x.anahtar != t.anahtar) x
                                  ];
                                  if (!ctx.mounted) return;
                                  if (liste.isEmpty) {
                                    Navigator.pop(ctx);
                                  } else {
                                    setState(() {});
                                  }
                                },
                                child: const Text('Sil'),
                              ),
                              FilledButton.tonal(
                                onPressed: () => Navigator.pop(ctx, t),
                                child: const Text('Devam et'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Sonra')),
        ],
      ),
    ),
  );
  if (secilen != null && context.mounted) {
    unawaited(taslagaDevamEt(context, secilen));
  }
}

/// Cihaz kartında: bu cihazda yarım kalmış pencere (sahada kullanım,
/// arıza, servis…) varsa "Devam et / Sil" kartı. [otomatikTur] verilirse
/// o pencere açılışta kendiliğinden açılır.
class YarimIslemKarti extends StatefulWidget {
  const YarimIslemKarti({
    super.key,
    required this.cihazId,
    required this.devamEt,
    this.otomatikTur,
  });

  final String cihazId;
  final String? otomatikTur;
  final Future<void> Function(String tur) devamEt;

  @override
  State<YarimIslemKarti> createState() => _YarimIslemKartiState();
}

class _YarimIslemKartiState extends State<YarimIslemKarti> {
  List<Taslak> _liste = const [];
  bool _otomatikAcildi = false;

  @override
  void initState() {
    super.initState();
    TaslakServisi.degisti.addListener(_yukle);
    _yukle();
  }

  @override
  void dispose() {
    TaslakServisi.degisti.removeListener(_yukle);
    super.dispose();
  }

  Future<void> _yukle() async {
    final l = await TaslakServisi.cihazinTaslaklari(widget.cihazId);
    if (!mounted) return;
    setState(() => _liste = l);
    final tur = widget.otomatikTur;
    if (!_otomatikAcildi && tur != null) {
      _otomatikAcildi = true;
      if (l.any((t) => t.tur == tur)) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => mounted ? widget.devamEt(tur) : null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_liste.isEmpty) return const SizedBox.shrink();
    final tema = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      color: tema.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Yarım kalan işlem',
                style: tema.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            for (final t in _liste)
              Row(
                children: [
                  Icon(taslakIkonu(t.tur), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        '${t.baslik.split(' · ').first} · ${t.zamanMetni}'),
                  ),
                  TextButton(
                    onPressed: () => TaslakServisi.sil(t.anahtar),
                    child: const Text('Sil'),
                  ),
                  FilledButton.tonal(
                    onPressed: () => widget.devamEt(t.tur),
                    child: const Text('Devam et'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
