import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../database/models.dart';
import '../services/cihaz_tercihleri.dart';
import '../services/gorunum_ayari.dart';
import '../services/guncelleme_servisi.dart';
import '../services/supabase_service.dart';
import '../services/taslak_servisi.dart';
import '../widgets/renkler.dart';
import '../widgets/sync_durum_dugmesi.dart';
import '../widgets/iphone_rehberi.dart';
import '../widgets/yarim_isler.dart';
import 'bildirim/bildirim_ayarlari_screen.dart';
import 'etiket/etiket_ayarlari_screen.dart';
import 'yenilikler_screen.dart';

/// Alt menüdeki "Ayarlar" sekmesi: hesap, yarım kalan işler, senkron,
/// bildirim / etiket ayarları, büyük yazı, güncelleme, yenilikler ve çıkış.
class AyarlarScreen extends ConsumerWidget {
  const AyarlarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(syncDurumProvider);
    final tema = Theme.of(context);

    void ac(Widget ekran) => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ekran));

    final senkronMetni = [
      d.sonBasari == null
          ? 'Henüz senkronize edilmedi'
          : 'Son senkron: ${_gunMetni(d.sonBasari!)}',
      d.bekleyen > 0 ? '${d.bekleyen} kayıt bekliyor' : 'bekleyen yok',
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayarlar'),
        actions: ustDugmeler(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        children: [
          _Kutu(children: [
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              leading: Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                    color: Renkler.depoZemin, shape: BoxShape.circle),
                child: const Icon(Icons.person_outline,
                    color: Renkler.depo, size: 28),
              ),
              title: Text(SupabaseService.kullanici?.email ?? 'Oturum yok',
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text(senkronMetni),
            ),
          ]),
          const _Baslik('İŞLER'),
          _Kutu(children: [
            ValueListenableBuilder<int>(
              valueListenable: TaslakServisi.degisti,
              builder: (context, _, __) => FutureBuilder<List<Taslak>>(
                future: TaslakServisi.hepsi(),
                builder: (context, snap) {
                  final adet = snap.data?.length ?? 0;
                  return _Satir(
                    ikon: Icons.edit_note,
                    renk: Renkler.urun,
                    zemin: Renkler.urunZemin,
                    baslik: 'Yarım kalan işler',
                    alt: 'Sayım, transfer, giriş, montaj…',
                    sag: adet == 0
                        ? null
                        : Badge(
                            backgroundColor: Renkler.urun,
                            largeSize: 24,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            label: Text('$adet',
                                style: const TextStyle(fontSize: 13)),
                          ),
                    onTap: () =>
                        yarimIsleriGoster(context, bosIseHaberVer: true),
                  );
                },
              ),
            ),
            _Satir(
              ikon: Icons.cloud_sync_outlined,
              renk: Renkler.okut,
              zemin: Renkler.okutZemin,
              baslik: 'Şimdi senkronize et',
              alt: d.calisiyor ? 'Gönderiliyor…' : d.hata,
              onTap: () => ref.read(syncServiceProvider).syncNow(),
            ),
          ]),
          const _Baslik('TERCİHLER'),
          _Kutu(children: [
            const _VarsayilanDepoSatiri(),
            _Satir(
              ikon: Icons.notifications_none,
              renk: Renkler.zil,
              zemin: Renkler.zilZemin,
              baslik: 'Bildirim ayarları',
              onTap: () => ac(const BildirimAyarlariScreen()),
            ),
            _Satir(
              ikon: Icons.qr_code_2,
              renk: Renkler.ara,
              zemin: Renkler.araZemin,
              baslik: 'Kurum etiketi ayarları',
              onTap: () => ac(const EtiketAyarlariScreen()),
            ),
            if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
              ValueListenableBuilder<bool>(
                valueListenable: CihazTercihleri.yazidanOku,
                builder: (context, acik, _) => _Satir(
                  ikon: Icons.document_scanner_outlined,
                  renk: Renkler.montaj,
                  zemin: Renkler.montajZemin,
                  baslik: 'Yazıdan da oku',
                  alt: 'Barkod okunmazsa etiketteki S/N satırı okunur',
                  sag: Switch(
                      value: acik, onChanged: CihazTercihleri.yazidanOkuAyarla),
                  onTap: () => CihazTercihleri.yazidanOkuAyarla(!acik),
                ),
              ),
            ValueListenableBuilder<bool>(
              valueListenable: GorunumAyari.buyukYazi,
              builder: (context, acik, _) => _Satir(
                ikon: Icons.text_increase,
                renk: Renkler.depo,
                zemin: Renkler.depoZemin,
                baslik: 'Büyük yazı',
                alt: 'Yazıları ve simgeleri büyütür',
                sag: Switch(value: acik, onChanged: GorunumAyari.ayarla),
                onTap: () => GorunumAyari.ayarla(!acik),
              ),
            ),
          ]),
          const _Baslik('UYGULAMA'),
          _Kutu(children: [
            _Satir(
              ikon: Icons.system_update_outlined,
              renk: Renkler.rapor,
              zemin: Renkler.raporZemin,
              baslik: 'Güncellemeleri denetle',
              alt: GuncellemeServisi.mevcutSurum.isEmpty
                  ? null
                  : 'Sürüm ${GuncellemeServisi.mevcutSurum}',
              onTap: () => GuncellemeServisi.elleDenetle(context),
            ),
            if (iphoneRehberiGoster)
              _Satir(
                ikon: Icons.add_to_home_screen,
                renk: Renkler.okut,
                zemin: Renkler.okutZemin,
                baslik: 'Ana ekrana ekle (iPhone)',
                alt: 'Bildirim ve kalıcı saklama için',
                onTap: () => anaEkranRehberi(context),
              ),
            _Satir(
              ikon: Icons.auto_awesome_outlined,
              renk: Renkler.ara,
              zemin: Renkler.araZemin,
              baslik: 'Yenilikler',
              onTap: () => ac(const YeniliklerScreen()),
            ),
          ]),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Renkler.cikis,
              side: const BorderSide(color: Renkler.cikis, width: 1.5),
              minimumSize: const Size.fromHeight(52),
              textStyle:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('Çıkış yap'),
            onPressed: () => cikisYapOnayli(context, ref),
          ),
          const SizedBox(height: 16),
          Text(
            'Developed by Seyfettin AYDIN',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 0.5,
              fontStyle: FontStyle.italic,
              color: tema.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  static String _gunMetni(DateTime t) {
    final s = SyncDurumDugmesi.saatMetni(t);
    final bugun = DateTime.now();
    final ayniGun =
        t.year == bugun.year && t.month == bugun.month && t.day == bugun.day;
    return ayniGun ? 'bugün $s' : s;
  }
}

class _Baslik extends StatelessWidget {
  const _Baslik(this.metin);
  final String metin;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(metin,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.4,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

class _Kutu extends StatelessWidget {
  const _Kutu({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: tema.colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: tema.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          children[i],
        ],
      ]),
    );
  }
}

class _Satir extends StatelessWidget {
  const _Satir({
    required this.ikon,
    required this.renk,
    required this.zemin,
    required this.baslik,
    this.alt,
    this.sag,
    this.onTap,
  });

  final IconData ikon;
  final Color renk;
  final Color zemin;
  final String baslik;
  final String? alt;
  final Widget? sag;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: RenkliSimge(ikon, renk: renk, zemin: zemin),
      title: Text(baslik,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      subtitle: alt == null
          ? null
          : Text(alt!, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: sag ?? const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}


/// Ayarlar → Varsayılan giriş deposu (bu telefona özel): Depoya girişte hazır
/// seçili gelir.
class _VarsayilanDepoSatiri extends ConsumerStatefulWidget {
  const _VarsayilanDepoSatiri();

  @override
  ConsumerState<_VarsayilanDepoSatiri> createState() =>
      _VarsayilanDepoSatiriState();
}

class _VarsayilanDepoSatiriState extends ConsumerState<_VarsayilanDepoSatiri> {
  String? _depoId;

  @override
  void initState() {
    super.initState();
    CihazTercihleri.girisDeposu().then((v) {
      if (mounted) setState(() => _depoId = v);
    });
  }

  Future<void> _sec(List<Depo> depolar) async {
    final secim = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Varsayılan giriş deposu'),
        children: [
          for (final d in depolar)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, d.id),
              child: Row(children: [
                Icon(
                    d.id == _depoId
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: Renkler.okut),
                const SizedBox(width: 12),
                Expanded(child: Text(d.ad)),
              ]),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ''),
            child: const Row(children: [
              Icon(Icons.block, color: Renkler.ayar),
              SizedBox(width: 12),
              Text('Seçilmesin'),
            ]),
          ),
        ],
      ),
    );
    if (secim == null) return;
    final id = secim.isEmpty ? null : secim;
    await CihazTercihleri.girisDeposuAyarla(id);
    if (mounted) setState(() => _depoId = id);
  }

  @override
  Widget build(BuildContext context) {
    final depolar = (ref.watch(depolarStreamProvider).valueOrNull ?? <Depo>[])
        .where((d) => !d.arac)
        .toList();
    final ad = depolar.where((d) => d.id == _depoId).firstOrNull?.ad;
    return _Satir(
      ikon: Icons.warehouse_outlined,
      renk: Renkler.okut,
      zemin: Renkler.okutZemin,
      baslik: 'Varsayılan giriş deposu',
      alt: ad ?? 'Seçilmedi · Depoya girişte hazır seçili gelir',
      onTap: () => _sec(depolar),
    );
  }
}
