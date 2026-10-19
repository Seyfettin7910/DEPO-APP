import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../database/app_database.dart';
import '../../database/models.dart';
import '../../providers/app_providers.dart';
import '../../services/ses_servisi.dart';
import '../../widgets/depo_secici.dart';
import '../../widgets/alim_bilgisi_alanlari.dart';
import '../../widgets/iade_sebebi.dart';
import '../../services/konum_servisi.dart';
import '../../services/adres_servisi.dart';
import '../../widgets/silme_islemleri.dart';
import '../../widgets/servis_islemleri.dart';
import '../../widgets/etiket_karti.dart';

/// Cihazın şu anki konumunu tek satırda anlatır.
String cihazKonumMetni(CihazBilgi b) {
  final s = b.cihaz.servisDurumu;
  switch (b.cihaz.durum) {
    case CihazDurumu.depoda:
      if (s == ServisDurumu.garantide) {
        return 'Garanti servisinde (${b.depoAdi ?? '-'} stoğundan)';
      }
      if (s != null) return '${s.kisa}: ${b.depoAdi ?? '-'}';
      return '${b.depoArac ? 'Araçta' : 'Depoda'}: ${b.depoAdi ?? '-'}';
    case CihazDurumu.kullanimda:
      return 'Kullanımda: ${b.aracPlaka ?? b.cihaz.kullanimYeri ?? '-'}';
    case CihazDurumu.cikti:
      if (s == ServisDurumu.hurda) return 'Hurdaya ayrıldı';
      if (s == ServisDurumu.degistirildi) return 'Değiştirildi (firmaya teslim)';
      return 'Çıkış yapıldı';
  }
}

Color cihazRengi(Cihaz c) =>
    c.servisDurumu != null ? servisRengi(c.servisDurumu!) : cihazDurumRengi(c.durum);

IconData cihazIkonu(Cihaz c) =>
    c.servisDurumu != null ? servisIkonu(c.servisDurumu!) : cihazDurumIkonu(c.durum);

Color cihazDurumRengi(CihazDurumu d) {
  switch (d) {
    case CihazDurumu.depoda:
      return Colors.green.shade700;
    case CihazDurumu.kullanimda:
      return Colors.orange.shade800;
    case CihazDurumu.cikti:
      return Colors.red.shade700;
  }
}

IconData cihazDurumIkonu(CihazDurumu d) {
  switch (d) {
    case CihazDurumu.depoda:
      return Icons.warehouse;
    case CihazDurumu.kullanimda:
      return Icons.local_shipping_outlined;
    case CihazDurumu.cikti:
      return Icons.logout;
  }
}

/// Bir seri numaralı cihazın kartı: hangi model, şu an nerede (depo / araç),
/// ve cihaz üzerinde transfer / kullanıma verme / çıkış / iade işlemleri.
class CihazDetayScreen extends ConsumerWidget {
  final String cihazId;
  const CihazDetayScreen({super.key, required this.cihazId});

  static final _tarihFormat = DateFormat('dd.MM.yyyy HH:mm');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bilgiAsync = ref.watch(cihazBilgiProvider(cihazId));
    final gecmisAsync = ref.watch(cihazGecmisiProvider(cihazId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cihaz'),
        actions: [
          if (bilgiAsync.value != null && !bilgiAsync.value!.cihaz.deleted)
            PopupMenuButton<String>(
              onSelected: (v) async {
                final b = bilgiAsync.value!;
                if (v == 'sil') {
                  final silindi = await cihazSilAkisi(context, ref, b);
                  if (silindi && context.mounted) Navigator.of(context).pop();
                } else if (v == 'ariza') {
                  await arizaliIsaretleAkisi(context, ref, b);
                } else if (v == 'hurda') {
                  await hurdayaAyirAkisi(context, ref, b);
                }
              },
              itemBuilder: (_) => [
                if (bilgiAsync.value!.cihaz.durum == CihazDurumu.depoda &&
                    !bilgiAsync.value!.cihaz.arizali) ...[
                  const PopupMenuItem(
                    value: 'ariza',
                    child: ListTile(
                      leading: Icon(Icons.build_outlined),
                      title: Text('Arızalı olarak işaretle'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'hurda',
                    child: ListTile(
                      leading: Icon(Icons.recycling),
                      title: Text('Hurdaya ayır'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
                const PopupMenuItem(
                  value: 'sil',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('Cihazı sil'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
        ],
      ),
      body: bilgiAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Hata: $e')),
        data: (bilgi) {
          if (bilgi == null) {
            return const Center(child: Text('Cihaz bulunamadı'));
          }
          final durum = bilgi.cihaz.durum;
          final renk = cihazRengi(bilgi.cihaz);
          final servis = bilgi.cihaz.servisDurumu;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(bilgi.urunAdi,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      SelectableText('Seri No: ${bilgi.cihaz.seriNo}',
                          style: const TextStyle(fontSize: 16)),
                      const Divider(height: 24),
                      Row(
                        children: [
                          Icon(cihazIkonu(bilgi.cihaz), color: renk, size: 32),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              cihazKonumMetni(bilgi),
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: renk),
                            ),
                          ),
                        ],
                      ),
                      if (durum == CihazDurumu.kullanimda)
                        Builder(builder: (context) {
                          final gecmis = gecmisAsync.value ?? const [];
                          final k = gecmis
                              .where((h) =>
                                  h.tip == HareketTipi.kullanim &&
                                  h.enlem != null &&
                                  h.boylam != null)
                              .firstOrNull;
                          if (k == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  KonumServisi.haritadaAc(k.enlem!, k.boylam!),
                              icon: const Icon(Icons.place),
                              label: Text(
                                  Adres(il: k.il, ilce: k.ilce, mahalle: k.mahalle)
                                          .ozet
                                          .isNotEmpty
                                      ? 'Kurulum: ${Adres(il: k.il, ilce: k.ilce, mahalle: k.mahalle).ozet}'
                                      : 'Kurulum konumu: '
                                          '${KonumServisi.koordinat(k.enlem!, k.boylam!)}'),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
              ServisKarti(bilgi: bilgi),
              EtiketKarti(bilgi: bilgi),
              _alimKarti(context, ref, bilgi),
              const SizedBox(height: 12),
              if (bilgi.cihaz.deleted)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: const ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('Bu cihaz silindi'),
                    subtitle: Text('Silme nedeni aşağıdaki geçmişte yazıyor. '
                        'Aynı seri no ile yeniden giriş yapılabilir.'),
                  ),
                )
              else if (servis == ServisDurumu.hurda ||
                  servis == ServisDurumu.degistirildi)
                const SizedBox.shrink()
              else if (durum == CihazDurumu.depoda && bilgi.cihaz.arizali)
                const SizedBox.shrink() // işlemler servis kartında
              else if (durum == CihazDurumu.depoda)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _transfer(context, ref, bilgi),
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Transfer'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _kullanima(context, ref, bilgi),
                      icon: const Icon(Icons.local_shipping_outlined),
                      label: const Text('Kullanıma ver'),
                    ),
                    FilledButton.icon(
                      onPressed: () => _sahada(context, ref, bilgi),
                      icon: const Icon(Icons.task_alt),
                      label: const Text('Sahada kullanıldı'),
                    ),
                    if (bilgi.depoArac)
                      FilledButton.tonalIcon(
                        onPressed: () => _iadeEt(context, ref, bilgi),
                        icon: const Icon(Icons.assignment_return_outlined),
                        label: const Text('İade'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => _cikis(context, ref, bilgi),
                      icon: const Icon(Icons.logout),
                      label: const Text('Çıkış'),
                    ),
                  ],
                )
              else
                FilledButton.icon(
                  onPressed: () => _iade(context, ref, bilgi),
                  icon: const Icon(Icons.assignment_return_outlined),
                  label: const Text('Depoya geri al'),
                ),
              const SizedBox(height: 20),
              const Text('Geçmiş',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              gecmisAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('Hata: $e'),
                data: (liste) {
                  if (liste.isEmpty) return const Text('Henüz hareket yok');
                  return Column(
                    children: [
                      for (final h in liste)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(_ikon(h.tip)),
                          trailing: (h.enlem != null && h.boylam != null)
                              ? IconButton(
                                  icon: const Icon(Icons.place),
                                  tooltip: 'Haritada aç',
                                  onPressed: () => KonumServisi.haritadaAc(
                                      h.enlem!, h.boylam!),
                                )
                              : null,
                          title: Text(_baslik(h)),
                          subtitle: Text([
                            _tarihFormat.format(h.tarih),
                            if (h.kullaniciAdi != null) h.kullaniciAdi!,
                            if (h.sebep != null && h.tip != HareketTipi.servis)
                              h.tip == HareketTipi.hurda
                                  ? 'Neden: ${h.sebep}'
                                  : 'Sebep: ${h.sebep}',
                            if (Adres(il: h.il, ilce: h.ilce, mahalle: h.mahalle)
                                .ozet
                                .isNotEmpty)
                              Adres(il: h.il, ilce: h.ilce, mahalle: h.mahalle)
                                  .ozet,
                            if (h.not_ != null &&
                                h.not_!.isNotEmpty &&
                                h.not_ != 'İade')
                              h.not_!,
                          ].join(' · ')),
                        ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  static IconData _ikon(HareketTipi t) {
    switch (t) {
      case HareketTipi.servis:
        return Icons.build_outlined;
      case HareketTipi.hurda:
        return Icons.recycling;
      case HareketTipi.silme:
        return Icons.delete_outline;
      case HareketTipi.girisi:
        return Icons.arrow_downward;
      case HareketTipi.cikis:
        return Icons.arrow_upward;
      case HareketTipi.transfer:
        return Icons.swap_horiz;
      case HareketTipi.kullanim:
        return Icons.local_shipping_outlined;
      case HareketTipi.iade:
        return Icons.assignment_return_outlined;
    }
  }

  static String _baslik(CihazHareketSatiri h) {
    switch (h.tip) {
      case HareketTipi.servis:
        if (h.hedefDepoAdi != null && h.hedefDepoId != h.depoId) {
          return '${h.sebep ?? 'Servis'}: ${h.hedefDepoAdi}';
        }
        return h.sebep ?? 'Servis işlemi';
      case HareketTipi.hurda:
        return 'Hurdaya ayrıldı${h.depoAdi == null ? '' : ' (${h.depoAdi})'}';
      case HareketTipi.silme:
        return 'Cihaz silindi${h.depoAdi == null ? '' : ' (${h.depoAdi})'}';
      case HareketTipi.girisi:
        if (h.sebep != null || h.not_ == 'İade') {
          return 'Sahadan geri alındı: ${h.depoAdi ?? '-'}';
        }
        return 'Depoya giriş: ${h.depoAdi ?? '-'}';
      case HareketTipi.cikis:
        return 'Çıkış: ${h.depoAdi ?? '-'}';
      case HareketTipi.transfer:
        return 'Transfer: ${h.depoAdi ?? '-'} → ${h.hedefDepoAdi ?? '-'}';
      case HareketTipi.iade:
        return 'İade: ${h.depoAdi ?? '-'} → ${h.hedefDepoAdi ?? '-'}';
      case HareketTipi.kullanim:
        if (h.hedefDepoAdi != null) {
          return 'Kullanıma verildi: ${h.depoAdi ?? '-'} → ${h.hedefDepoAdi}';
        }
        return 'Sahada kullanıldı: ${h.aracPlaka ?? h.kullanimYeri ?? '-'}'
            ' (${h.depoAdi ?? '-'} stoğundan)';
    }
  }

  // -------------------------------------------------------------------
  // İşlemler
  // -------------------------------------------------------------------
  Future<void> _calistir(
      BuildContext context, WidgetRef ref, Future<void> Function() islem,
      String basariMesaji) async {
    try {
      await islem();
      SesServisi.basari();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(basariMesaji)));
      }
    } catch (e) {
      SesServisi.hata();
      if (context.mounted) {
        final mesaj = e is StateError ? e.message : 'İşlem başarısız: $e';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
              content: Text(mesaj), backgroundColor: Colors.red.shade700));
      }
    }
  }

  String get _kullanici => 'demo-kullanici';

  Future<void> _transfer(
          BuildContext context, WidgetRef ref, CihazBilgi bilgi) =>
      _hedefeTasi(context, ref, bilgi, HareketTipi.transfer);

  Future<void> _kullanima(
          BuildContext context, WidgetRef ref, CihazBilgi bilgi) =>
      _hedefeTasi(context, ref, bilgi, HareketTipi.kullanim);

  Future<void> _iadeEt(
          BuildContext context, WidgetRef ref, CihazBilgi bilgi) =>
      _hedefeTasi(context, ref, bilgi, HareketTipi.iade);

  /// Transfer, "Kullanıma ver" ve "İade" aynı mantıkla çalışır: hedef bir depo veya
  /// araç (seyyar depo) seçilir, cihaz oraya geçer.
  Future<void> _hedefeTasi(BuildContext context, WidgetRef ref,
      CihazBilgi bilgi, HareketTipi tip) async {
    final kullanim = tip == HareketTipi.kullanim;
    final iade = tip == HareketTipi.iade;
    final hedefler = (ref.read(depolarStreamProvider).value ?? <Depo>[])
        .where((d) => d.id != bilgi.cihaz.depoId)
        .toList();
    if (kullanim) {
      // Kullanıma verirken araçlar öncelikli gösterilir.
      hedefler.sort((a, b) => (a.arac ? 0 : 1).compareTo(b.arac ? 0 : 1));
    }
    if (iade) {
      // İadede sabit depolar önde gösterilir.
      hedefler.sort((a, b) => (a.arac ? 1 : 0).compareTo(b.arac ? 1 : 0));
    }
    if (hedefler.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Seçilebilecek başka depo veya araç yok')));
      return;
    }
    String? hedef = hedefler.first.id;
    if (iade) {
      // Varsayılan: cihazın bu araca geldiği depo (geçmişteki kaynak).
      final gecmis =
          ref.read(cihazGecmisiProvider(bilgi.cihaz.id)).value ?? const [];
      for (final h in gecmis) {
        if (h.hedefDepoId == bilgi.cihaz.depoId &&
            h.depoId != null &&
            hedefler.any((d) => d.id == h.depoId)) {
          hedef = h.depoId;
          break;
        }
      }
    }
    final notCtrl = TextEditingController();
    String? sebep;
    String? arizaKarari;
    String? hata;

    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          scrollable: true,
          title: Text(kullanim
              ? 'Kullanıma ver'
              : (iade ? 'İade' : 'Başka yere transfer')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: hedef,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText: kullanim
                        ? 'Hangi depo / araca verilsin?'
                        : (iade
                            ? 'Hangi depoya iade edilsin?'
                            : 'Hedef depo / araç')),
                items: depoDropdownOgeleri(hedefler),
                onChanged: (v) => setState(() => hedef = v),
              ),
              if (iade)
                IadeSebebiSecici(
                  secili: sebep,
                  zorunlu: false,
                  onSecildi: (v) => setState(() {
                    sebep = v;
                    hata = null;
                  }),
                  arizaKarari: arizaKarari,
                  onArizaKarari: (v) => setState(() {
                    arizaKarari = v;
                    hata = null;
                  }),
                ),
              TextField(
                controller: notCtrl,
                decoration: const InputDecoration(labelText: 'Not (opsiyonel)'),
              ),
              if (hata != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(hata!,
                      style:
                          TextStyle(color: Theme.of(ctx).colorScheme.error)),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('İptal')),
            FilledButton(
                onPressed: () {
                  if (iade) {
                    final h = iadeSebebiHatasi(sebep, notCtrl.text,
                        zorunlu: false,
                        arizaKarari: arizaKarari,
                        arizaSor: true);
                    if (h != null) {
                      setState(() => hata = h);
                      return;
                    }
                    if (sebep == 'Arıza' &&
                        hedefler.any((d) => d.id == hedef && d.arac)) {
                      setState(() =>
                          hata = 'Arızalı cihaz bir depoya iade edilmeli');
                      return;
                    }
                  }
                  Navigator.pop(ctx, true);
                },
                child: Text(kullanim
                    ? 'Kullanıma ver'
                    : (iade ? 'İade et' : 'Transfer et'))),
          ],
        ),
      ),
    );
    if (onay != true || hedef == null || !context.mounted) return;

    final db = ref.read(appDatabaseProvider);
    await _calistir(
      context,
      ref,
      () => db.cihazlariTopluHareketKaydet(
        cihazIdleri: [bilgi.cihaz.id],
        tip: tip,
        kullaniciId: ref.read(aktifKullaniciIdProvider) ?? _kullanici,
        hedefDepoId: hedef,
        not_: notCtrl.text.trim().isEmpty ? null : notCtrl.text.trim(),
        sebep: iade ? sebep : null,
        arizaKarari: iade && sebep == 'Arıza' ? arizaKarari : null,
      ),
      kullanim
          ? 'Kullanıma verildi'
          : (iade ? 'İade edildi' : 'Transfer edildi'),
    );
  }

  /// Cihaz sahada kullanıldı (müşteriye takıldı vb.): bulunduğu depo veya
  /// araç stoğundan düşer, kullanım yeri kaydedilir ve kullanım raporuna girer.
  Future<void> _sahada(
      BuildContext context, WidgetRef ref, CihazBilgi bilgi) async {
    final yerCtrl = TextEditingController();
    final notCtrl = TextEditingController();
    String? hata;
    // Konum, pencere açılır açılmaz arka planda okunmaya başlar.
    final konumIstegi = KonumServisi.konumAl();
    var konumKaydet = true;
    final ilCtrl = TextEditingController();
    final ilceCtrl = TextEditingController();
    final mahalleCtrl = TextEditingController();
    var adresDurumu = 'Konum bekleniyor...';
    var adresIstendi = false;

    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          // Konum gelince adresi (il/ilçe/mahalle) bir kez sor ve boş alanları doldur.
          if (!adresIstendi) {
            adresIstendi = true;
            konumIstegi.then((k) async {
              if (!k.basarili) {
                if (ctx.mounted) {
                  setState(() => adresDurumu =
                      'Konum yok: bölgeyi elle yazabilirsiniz');
                }
                return;
              }
              if (ctx.mounted) setState(() => adresDurumu = 'Adres bulunuyor...');
              final a = await AdresServisi.konumdanAdres(k.enlem!, k.boylam!);
              if (!ctx.mounted) return;
              setState(() {
                if (a == null) {
                  adresDurumu = 'İnternet yok: adres sonra otomatik bulunacak';
                } else {
                  if (ilCtrl.text.isEmpty) ilCtrl.text = a.il ?? '';
                  if (ilceCtrl.text.isEmpty) ilceCtrl.text = a.ilce ?? '';
                  if (mahalleCtrl.text.isEmpty) {
                    mahalleCtrl.text = a.mahalle ?? '';
                  }
                  adresDurumu = a.bos
                      ? 'Bu konum için adres bulunamadı'
                      : 'Konumdan bulundu, gerekirse düzeltin';
                }
              });
            });
          }
          return AlertDialog(
          scrollable: true,
          title: const Text('Sahada kullanıldı'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${bilgi.urunAdi}\nSN: ${bilgi.cihaz.seriNo}\n'
                  '${bilgi.depoAdi ?? '-'} stoğundan düşülecek.'),
              TextField(
                controller: yerCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nerede kullanıldı?',
                  hintText: 'Örn: Zabıta Müdürlüğü, Park Cad. 12',
                ),
              ),
              TextField(
                controller: notCtrl,
                decoration: const InputDecoration(labelText: 'Not (opsiyonel)'),
              ),
              const SizedBox(height: 12),
              FutureBuilder<KonumSonucu>(
                future: konumIstegi,
                builder: (ctx, snap) {
                  if (!snap.hasData) {
                    return const Row(
                      children: [
                        SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 10),
                        Expanded(child: Text('Konum alınıyor...')),
                      ],
                    );
                  }
                  final k = snap.data!;
                  if (!k.basarili) {
                    return Row(
                      children: [
                        Icon(Icons.location_off,
                            color: Colors.orange.shade800, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(
                                '${k.hata}. Konumsuz kaydedilecek.',
                                style: const TextStyle(fontSize: 13))),
                      ],
                    );
                  }
                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: konumKaydet,
                    onChanged: (v) => setState(() => konumKaydet = v ?? true),
                    secondary: Icon(Icons.place, color: Colors.green.shade700),
                    title: const Text('Konumu kaydet'),
                    subtitle: Text(
                        '${KonumServisi.koordinat(k.enlem!, k.boylam!)}'
                        '${k.hassasiyet == null ? '' : ' (±${k.hassasiyet!.round()} m)'}'),
                  );
                },
              ),
              const SizedBox(height: 4),
              Text(adresDurumu,
                  style: Theme.of(ctx).textTheme.bodySmall),
              TextField(
                controller: mahalleCtrl,
                textCapitalization: TextCapitalization.words,
                decoration:
                    const InputDecoration(labelText: 'Mahalle / köy'),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: ilceCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'İlçe'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: ilCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'İl'),
                    ),
                  ),
                ],
              ),
              if (hata != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(hata!,
                      style:
                          TextStyle(color: Theme.of(ctx).colorScheme.error)),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('İptal')),
            FilledButton(
              onPressed: () {
                if (yerCtrl.text.trim().isEmpty) {
                  setState(() => hata = 'Kullanım yerini yazın');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
        },
      ),
    );
    if (onay != true || !context.mounted) return;

    String? bosIseNull(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    final il = bosIseNull(ilCtrl);
    final ilce = bosIseNull(ilceCtrl);
    final mahalle = bosIseNull(mahalleCtrl);

    final db = ref.read(appDatabaseProvider);
    await _calistir(
      context,
      ref,
      () async {
        // Konum henüz gelmediyse (en fazla ~20 sn) beklenir.
        final k = konumKaydet ? await konumIstegi : null;
        final konumVar = k != null && k.basarili;
        await db.cihazlariTopluHareketKaydet(
          cihazIdleri: [bilgi.cihaz.id],
          tip: HareketTipi.kullanim,
          kullaniciId: ref.read(aktifKullaniciIdProvider) ?? _kullanici,
          kullanimYeri: yerCtrl.text.trim(),
          not_: notCtrl.text.trim().isEmpty ? null : notCtrl.text.trim(),
          enlem: konumVar ? k?.enlem : null,
          boylam: konumVar ? k?.boylam : null,
          konumHassasiyet: konumVar ? k?.hassasiyet : null,
          il: il,
          ilce: ilce,
          mahalle: mahalle,
        );
        // İnternet varsa eksik adres hemen tamamlanır.
        unawaited(AdresTamamlayici.calistir(db));
      },
      'Kullanım kaydedildi, stoktan düşüldü',
    );
  }

  /// Alım tarihi, firma, ihale ve garanti bilgisi kartı (düzenlenebilir).
  Widget _alimKarti(BuildContext context, WidgetRef ref, CihazBilgi bilgi) {
    final c = bilgi.cihaz;
    final gun = DateFormat('dd.MM.yyyy');
    final bos = c.alimTarihi == null &&
        c.firma == null &&
        c.ihale == null &&
        c.garantiBitis == null;
    Widget satir(IconData ikon, String etiket, String deger, {Color? renk}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(ikon, size: 18, color: renk ?? Colors.grey.shade700),
              const SizedBox(width: 8),
              SizedBox(
                  width: 92,
                  child: Text(etiket,
                      style: TextStyle(color: Colors.grey.shade700))),
              Expanded(
                  child: Text(deger,
                      style: TextStyle(
                          color: renk, fontWeight: FontWeight.w500))),
            ],
          ),
        );

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Alım / garanti',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Düzenle',
                  onPressed: () => _alimDuzenle(context, ref, bilgi),
                ),
              ],
            ),
            if (bos)
              const Text('Alım bilgisi girilmemiş. Düzenle ile ekleyebilirsiniz.')
            else ...[
              satir(Icons.event, 'Alım tarihi',
                  c.alimTarihi == null ? '-' : gun.format(c.alimTarihi!)),
              satir(Icons.store_outlined, 'Firma', c.firma ?? '-'),
              satir(Icons.gavel_outlined, 'İhale / sipariş', c.ihale ?? '-'),
              satir(Icons.verified_user_outlined, 'Garanti',
                  garantiDurumMetni(c.garantiBitis),
                  renk: garantiRengi(c.garantiBitis)),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _alimDuzenle(
      BuildContext context, WidgetRef ref, CihazBilgi bilgi) async {
    final db = ref.read(appDatabaseProvider);
    final firmalar = await db.oncekiAlimDegerleri('firma');
    final ihaleler = await db.oncekiAlimDegerleri('ihale');
    if (!context.mounted) return;
    final yeni = await alimBilgisiPenceresi(
      context,
      mevcut: AlimBilgisi.cihazdan(bilgi.cihaz),
      firmalar: firmalar,
      ihaleler: ihaleler,
      aciklama: 'SN: ${bilgi.cihaz.seriNo}',
    );
    if (yeni == null || !context.mounted) return;
    await _calistir(
      context,
      ref,
      () => db.cihazAlimGuncelle(bilgi.cihaz.id, yeni),
      'Alım bilgileri kaydedildi',
    );
  }

  Future<void> _cikis(
      BuildContext context, WidgetRef ref, CihazBilgi bilgi) async {
    final notCtrl = TextEditingController();
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Çıkış yap'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${bilgi.urunAdi}\nSN: ${bilgi.cihaz.seriNo}\n'
                '${bilgi.depoAdi ?? '-'} deposundan çıkış yapılacak.'),
            TextField(
              controller: notCtrl,
              decoration:
                  const InputDecoration(labelText: 'Not (örn. kime verildi)'),
            ),
          ],
        ),
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
    if (onay != true || !context.mounted) return;

    final db = ref.read(appDatabaseProvider);
    await _calistir(
      context,
      ref,
      () => db.cihazlariTopluHareketKaydet(
        cihazIdleri: [bilgi.cihaz.id],
        tip: HareketTipi.cikis,
        kullaniciId: ref.read(aktifKullaniciIdProvider) ?? _kullanici,
        not_: notCtrl.text.trim().isEmpty ? null : notCtrl.text.trim(),
      ),
      'Çıkış kaydedildi',
    );
  }

  /// Sahada kullanılmış veya çıkışı yapılmış cihazı depoya geri alır.
  /// Geri alma sebebi sorulur ve geçmişe yazılır. Arızada tamir / değişim
  /// kararı sorulur ve arıza kaydı açılır (cihaz kullanılamaz olur);
  /// "Ömrünü doldurdu" seçilirse cihaz alınıp hurdaya ayrılır.
  Future<void> _iade(
      BuildContext context, WidgetRef ref, CihazBilgi bilgi) async {
    final depolar = ref.read(depolarStreamProvider).value ?? <Depo>[];
    if (depolar.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Önce depo ekleyin')));
      return;
    }
    // Sabit depolar önce
    final sirali = List<Depo>.of(depolar)
      ..sort((a, b) => (a.arac ? 1 : 0).compareTo(b.arac ? 1 : 0));
    final sabitler = sirali.where((d) => !d.arac).toList();
    String? hedef = sirali.first.id;
    String? sebep;
    String? arizaKarari;
    String? hata;
    final notCtrl = TextEditingController();

    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          // Arızalı ve hurda cihazlar araca alınmaz; sabit depoya girer.
          final yalnizDepo = (sebep == 'Arıza' || sebep == omruDolduSebebi) &&
              sabitler.isNotEmpty;
          final secenekler = yalnizDepo ? sabitler : sirali;
          if (!secenekler.any((d) => d.id == hedef)) {
            hedef = secenekler.first.id;
          }
          return AlertDialog(
            scrollable: true,
            title: const Text('Depoya geri al'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${bilgi.urunAdi} · SN: ${bilgi.cihaz.seriNo}'
                  '${bilgi.cihaz.kullanimYeri == null ? '' : '\nKullanım yeri: ${bilgi.cihaz.kullanimYeri}'}',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey(yalnizDepo),
                  value: hedef,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText:
                          yalnizDepo ? 'Hangi depoya?' : 'Hangi depo / araca?'),
                  items: depoDropdownOgeleri(secenekler),
                  onChanged: (v) => setState(() => hedef = v),
                ),
                IadeSebebiSecici(
                  secili: sebep,
                  hurdaSecenegi: true,
                  onSecildi: (v) => setState(() {
                    sebep = v;
                    hata = null;
                  }),
                  arizaKarari: arizaKarari,
                  onArizaKarari: (v) => setState(() {
                    arizaKarari = v;
                    hata = null;
                  }),
                ),
                TextField(
                  controller: notCtrl,
                  decoration: InputDecoration(
                    labelText: sebep == 'Diğer'
                        ? 'Açıklama (zorunlu)'
                        : (sebep == 'Arıza'
                            ? 'Arıza açıklaması (opsiyonel)'
                            : 'Not (opsiyonel)'),
                    hintText: sebep == 'Arıza'
                        ? 'Örn: görüntü gelmiyor, açılmıyor'
                        : 'Örn: yerine yenisi takıldı',
                  ),
                  onChanged: (_) {
                    if (hata != null) setState(() => hata = null);
                  },
                ),
                if (hata != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(hata!,
                        style: TextStyle(
                            color: Theme.of(ctx).colorScheme.error)),
                  ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('İptal')),
              FilledButton(
                  onPressed: () {
                    final h = iadeSebebiHatasi(sebep, notCtrl.text,
                        arizaKarari: arizaKarari, arizaSor: true);
                    if (h != null) {
                      setState(() => hata = h);
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  child: Text(sebep == omruDolduSebebi
                      ? 'Geri al ve hurdaya ayır'
                      : 'Geri al')),
            ],
          );
        },
      ),
    );
    if (onay != true || hedef == null || !context.mounted) return;

    final db = ref.read(appDatabaseProvider);
    final hurda = sebep == omruDolduSebebi;
    final ariza = sebep == 'Arıza';
    await _calistir(
      context,
      ref,
      () => db.sahadanGeriAl(
        cihazId: bilgi.cihaz.id,
        depoId: hedef!,
        sebep: hurda ? 'Ömrünü doldurdu' : sebep!,
        kullaniciId: ref.read(aktifKullaniciIdProvider) ?? _kullanici,
        not_: notCtrl.text.trim().isEmpty ? null : notCtrl.text.trim(),
        arizaKarari: ariza ? arizaKarari : null,
        hurda: hurda,
      ),
      hurda
          ? 'Geri alındı ve hurdaya ayrıldı'
          : (ariza
              ? 'Arızalı olarak depoya alındı (${servisKararAdlari[arizaKarari]})'
              : 'Depoya geri alındı ($sebep)'),
    );
  }
}
