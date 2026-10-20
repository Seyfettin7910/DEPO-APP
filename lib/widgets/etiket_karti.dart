import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../database/app_database.dart';
import '../database/models.dart';
import '../providers/app_providers.dart';
import '../screens/etiket/etiket_dogrula_screen.dart';
import '../screens/etiket/etiketler_screen.dart';
import 'etiket_secimi.dart';

/// Cihaz kartında kurum etiketi: kod, durum, işlemler ve etiket geçmişi.
class EtiketKarti extends ConsumerWidget {
  const EtiketKarti({super.key, required this.bilgi});
  final CihazBilgi bilgi;

  static final _tarih = DateFormat('dd.MM.yyyy HH:mm');

  String _kullanici(WidgetRef ref) =>
      ref.read(aktifKullaniciIdProvider) ?? 'demo-kullanici';

  void _mesaj(BuildContext context, String m, {bool hata = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(m), backgroundColor: hata ? Colors.red.shade700 : null));
  }

  Future<void> _kodUret(BuildContext context, WidgetRef ref) async {
    final db = ref.read(appDatabaseProvider);
    final kodlar = await db.kurumKodlari(sadeceAktif: true);
    final onceki = await EtiketTercihi.yukle(kodlar);
    if (!context.mounted || kodlar.isEmpty) return;
    final t = await etiketTercihiSec(context,
        kodlar: kodlar,
        mevcut: onceki,
        kodUretmeSecenegi: false,
        baslik: 'Kurum kodu üret');
    if (t == null || t.kurumKoduId == null) return;
    try {
      await db.etiketUret(
          cihazIdleri: [bilgi.cihaz.id],
          kurumKoduId: t.kurumKoduId!,
          kuyruga: t.kuyruga,
          kullaniciId: _kullanici(ref));
      if (context.mounted) _mesaj(context, 'Kurum kodu üretildi');
    } catch (e) {
      if (context.mounted) {
        _mesaj(context, e is StateError ? e.message : 'Üretilemedi: $e',
            hata: true);
      }
    }
  }

  Future<void> _yenidenBas(
      BuildContext context, WidgetRef ref, EtiketBilgi e) async {
    final ctrl = TextEditingController();
    final tamam = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Etiket yeniden basılsın mı?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Kod aynı kalır (${e.kod}), etiket sürümü ${e.surum + 1} olur '
                've basım kuyruğuna girer. Eski etiket okutulursa uyarı verilir.'),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                  labelText: 'Sebep (ör. yıprandı, okunmuyor)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yeniden bas')),
        ],
      ),
    );
    final sebep = ctrl.text.trim();
    ctrl.dispose();
    if (tamam != true) return;
    await ref.read(appDatabaseProvider).yenidenBas(
        etiketId: e.id,
        kullaniciId: _kullanici(ref),
        sebep: sebep.isEmpty ? null : sebep);
    if (context.mounted) _mesaj(context, 'Etiket basım kuyruğuna alındı');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etiket = ref.watch(cihazEtiketiProvider(bilgi.cihaz.id)).valueOrNull;
    final ayar =
        ref.watch(etiketAyarlariProvider).valueOrNull ?? const EtiketAyarlari();
    final kodlar =
        ref.watch(kurumKodlariProvider).valueOrNull ?? const <KurumKodu>[];
    final aktifCihaz = !bilgi.cihaz.deleted && bilgi.cihaz.durum != CihazDurumu.cikti;

    if (etiket == null) {
      // Kurum kodu tanımlı değilse özellik kullanılmıyor: kart gösterilmez.
      if (kodlar.where((k) => k.aktif).isEmpty || !aktifCihaz) {
        return const SizedBox.shrink();
      }
      return Card(
        child: ListTile(
          leading: const Icon(Icons.label_off_outlined),
          title: const Text('Kurum etiketi yok'),
          subtitle: const Text('Bu cihaza kurum kodu üretilebilir'),
          trailing: TextButton(
            onPressed: () => _kodUret(context, ref),
            child: const Text('Kod üret'),
          ),
        ),
      );
    }

    final gecmis =
        ref.watch(etiketGecmisiProvider(bilgi.cihaz.id)).valueOrNull ?? const [];
    final renk = etiketDurumRengi(etiket.durum);
    final durumMetni = etiket.durum == EtiketDurumu.basildi && !ayar.dogrulama
        ? 'Basıldı'
        : etiket.durum.etiket;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(etiketDurumIkonu(etiket.durum), color: renk, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(etiket.kod,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                      Text(
                        [
                          'Kurum etiketi',
                          durumMetni,
                          if (etiket.surum > 1) 'sürüm ${etiket.surum}',
                          if (etiket.seriNosuz) 'seri nosuz ürün',
                        ].join(' · '),
                        style: TextStyle(color: renk),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (ayar.dogrulama && etiket.dogrulanmadi)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  ayar.engel
                      ? '⚠ Etiket doğrulanmadan transfer, araca yükleme ve '
                          'montaj yapılamaz.'
                      : '⚠ Etiket doğrulanmadı.',
                  style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
                ),
              ),
            Wrap(
              spacing: 4,
              children: [
                if (etiket.durum == EtiketDurumu.kayitli)
                  TextButton.icon(
                    onPressed: () async {
                      await ref.read(appDatabaseProvider).kuyrugaAl(
                          etiketIdleri: [etiket.id],
                          kullaniciId: _kullanici(ref));
                      if (context.mounted) {
                        _mesaj(context, 'Basım kuyruğuna alındı');
                      }
                    },
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Basım kuyruğuna al'),
                  ),
                if (ayar.dogrulama && etiket.dogrulanmadi && aktifCihaz)
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const EtiketDogrulaScreen())),
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('Doğrula'),
                  ),
                if (etiket.durum != EtiketDurumu.kayitli &&
                    etiket.durum != EtiketDurumu.kuyrukta &&
                    aktifCihaz)
                  TextButton.icon(
                    onPressed: () => _yenidenBas(context, ref, etiket),
                    icon: const Icon(Icons.replay),
                    label: const Text('Yeniden bas'),
                  ),
                if (etiket.durum == EtiketDurumu.kuyrukta)
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const EtiketlerScreen())),
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Kuyrukta · bilgisayardan basılır'),
                  ),
              ],
            ),
            if (gecmis.isNotEmpty)
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('Etiket geçmişi (${gecmis.length})',
                      style: const TextStyle(fontSize: 14)),
                  children: [
                    for (final h in gecmis)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          h.islem == EtiketIslemi.uyusmazlik
                              ? Icons.report_gmailerrorred
                              : (h.islem == EtiketIslemi.dogrulandi
                                  ? Icons.verified_outlined
                                  : Icons.label_outline),
                          color: h.islem == EtiketIslemi.uyusmazlik
                              ? Colors.red.shade700
                              : null,
                          size: 20,
                        ),
                        title: Text(h.islem.etiket),
                        subtitle: Text([
                          _tarih.format(h.tarih),
                          if (h.kullaniciAdi != null) h.kullaniciAdi!,
                          if (h.aciklama != null && h.aciklama!.isNotEmpty)
                            h.aciklama!,
                        ].join(' · ')),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Depolar ekranının üst çubuğunda kurum etiketleri düğmesi. Rozet:
/// bilgisayarda basım kuyruğu, telefonda doğrulama bekleyen + uyuşmazlık.
class EtiketDugmesi extends ConsumerWidget {
  const EtiketDugmesi({super.key, required this.bilgisayar});
  final bool bilgisayar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final say = ref.watch(etiketSayilariProvider).valueOrNull ??
        const <EtiketDurumu, int>{};
    final ayar =
        ref.watch(etiketAyarlariProvider).valueOrNull ?? const EtiketAyarlari();
    final adet = bilgisayar
        ? (say[EtiketDurumu.kuyrukta] ?? 0)
        : (ayar.dogrulama ? (say[EtiketDurumu.basildi] ?? 0) : 0) +
            (say[EtiketDurumu.uyusmazlik] ?? 0);
    final uyusmazlik = (say[EtiketDurumu.uyusmazlik] ?? 0) > 0;
    return IconButton(
      tooltip: 'Kurum etiketleri',
      onPressed: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const EtiketlerScreen())),
      icon: Badge(
        isLabelVisible: adet > 0,
        backgroundColor: uyusmazlik ? Colors.red.shade700 : null,
        label: Text('$adet'),
        child: const Icon(Icons.qr_code_2),
      ),
    );
  }
}
