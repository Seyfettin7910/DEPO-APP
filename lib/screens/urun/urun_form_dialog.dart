import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/models.dart';
import '../../providers/app_providers.dart';
import '../../services/ses_servisi.dart';
import '../../widgets/barkod_okuyucu_sayfasi.dart';
import '../../widgets/depo_secici.dart';

/// Yeni ürün (model) ekler; [mevcut] verilirse o ürünü düzenler.
///
/// Takip türü: "Seri no" (her cihaz seri numarasıyla) ya da "Miktar"
/// (kablo, adaptör gibi seri numarasız malzemeler: adet, metre, paket…).
/// Malzemede fabrika barkodu kaydedilirse girişte okutularak seçilir.
///
/// Yeni üründe seri numarası (kamerayla okutulabilir) ve depo seçilirse,
/// ürün kaydedilirken o cihaz da seçilen depoya girilir. Aynı model adı
/// zaten varsa yeni model açılmaz, seri no mevcut modele eklenir.
Future<void> urunFormDialog(BuildContext context, WidgetRef ref,
    {Urun? mevcut}) {
  final adCtrl = TextEditingController(text: mevcut?.ad ?? '');
  final seriCtrl = TextEditingController();
  final kategoriCtrl = TextEditingController(text: mevcut?.kategori ?? '');
  final minStokCtrl =
      TextEditingController(text: '${mevcut?.minStokSeviyesi ?? 0}');
  final barkodCtrl = TextEditingController(text: mevcut?.barkod ?? '');
  var miktarli = mevcut?.miktarli ?? false;
  var birim = mevcut != null && malzemeBirimleri.contains(mevcut.birim)
      ? mevcut.birim
      : 'adet';
  final depolar = ref.read(depolarStreamProvider).value ?? <Depo>[];
  String? depoId = ref.read(seciliDepoIdProvider);
  if (!depolar.any((d) => d.id == depoId)) {
    depoId = depolar.isEmpty ? null : depolar.first.id;
  }
  String? hata;

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(mevcut == null ? 'Yeni Ürün' : 'Ürünü Düzenle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: adCtrl,
                decoration:
                    const InputDecoration(labelText: 'Ürün / model adı'),
                autofocus: mevcut == null,
              ),
              TextField(
                controller: kategoriCtrl,
                decoration: const InputDecoration(
                    labelText: 'Kategori / tür (ör. Kayıt Cihazları)'),
              ),
              const SizedBox(height: 12),
              if (mevcut == null)
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                        value: false,
                        icon: Icon(Icons.qr_code_2),
                        label: Text('Seri no ile')),
                    ButtonSegment(
                        value: true,
                        icon: Icon(Icons.cable_outlined),
                        label: Text('Miktarla')),
                  ],
                  selected: {miktarli},
                  onSelectionChanged: (v) => setState(() {
                    miktarli = v.first;
                    hata = null;
                  }),
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      miktarli
                          ? 'Takip: miktarla ($birim)'
                          : 'Takip: seri numarasıyla',
                      style: Theme.of(ctx).textTheme.bodySmall),
                ),
              if (miktarli) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Kablo, adaptör gibi seri numarası olmayan malzemeler. '
                    'Giriş, Araca Yükle ve montajda miktar girilir.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ),
                DropdownButtonFormField<String>(
                  value: birim,
                  decoration: const InputDecoration(labelText: 'Birim'),
                  items: [
                    for (final b in malzemeBirimleri)
                      DropdownMenuItem(value: b, child: Text(b)),
                  ],
                  onChanged: (v) => setState(() => birim = v ?? birim),
                ),
                TextField(
                  controller: barkodCtrl,
                  decoration: InputDecoration(
                    labelText: 'Fabrika barkodu (isteğe bağlı)',
                    helperText: 'Kaydedilirse girişte okutularak seçilir',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      tooltip: 'Kamera ile oku',
                      onPressed: () async {
                        final kod = await Navigator.of(ctx).push<String>(
                          MaterialPageRoute(
                            builder: (_) => const BarkodOkuyucuSayfasi(urunBarkodu: true),
                          ),
                        );
                        if (kod != null) barkodCtrl.text = kod.trim();
                      },
                    ),
                  ),
                ),
              ],
              if (mevcut == null && !miktarli) ...[
                TextField(
                  controller: seriCtrl,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Seri numarası',
                    helperText: 'Okut veya yaz. Daha fazlası için Depo → '
                        '"Seri no ile giriş"',
                    helperMaxLines: 2,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      tooltip: 'Kamera ile oku',
                      onPressed: () async {
                        final kod = await Navigator.of(ctx).push<String>(
                          MaterialPageRoute(
                            builder: (_) => const BarkodOkuyucuSayfasi(),
                          ),
                        );
                        if (kod != null) {
                          seriCtrl.text = kod.trim().toUpperCase();
                          setState(() {});
                        }
                      },
                    ),
                  ),
                ),
                if (seriCtrl.text.trim().isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: depoId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Hangi depo / araca girilecek?'),
                    items: depoDropdownOgeleri(depolar),
                    onChanged: (v) => setState(() => depoId = v),
                  ),
              ],
              TextField(
                controller: minStokCtrl,
                decoration: InputDecoration(
                    labelText: miktarli
                        ? 'Minimum miktar uyarısı ($birim, opsiyonel)'
                        : 'Minimum adet uyarısı (opsiyonel)',
                    helperText: 'Depolar + araçlardaki toplam bu sayıya inince uyarır',
                ),
                keyboardType: TextInputType.number,
              ),
              if (hata != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    hata!,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () async {
              final ad = adCtrl.text.trim();
              if (ad.isEmpty) {
                setState(() => hata = 'Ürün adı boş olamaz');
                return;
              }
              final db = ref.read(appDatabaseProvider);
              final kategori = kategoriCtrl.text.trim().isEmpty
                  ? null
                  : kategoriCtrl.text.trim();
              final minStok = int.tryParse(minStokCtrl.text.trim()) ?? 0;
              final seri = miktarli ? '' : seriCtrl.text.trim().toUpperCase();
              final barkod =
                  barkodCtrl.text.trim().isEmpty ? null : barkodCtrl.text.trim();

              try {
                if (barkod != null && barkod != mevcut?.barkod) {
                  final ayni = await db.barkodIleUrunBul(barkod);
                  if (ayni != null && !ayni.deleted && ayni.id != mevcut?.id) {
                    setState(() =>
                        hata = 'Bu barkod zaten ${ayni.ad} için kayıtlı');
                    return;
                  }
                }
                if (mevcut != null) {
                  await db.urunGuncelle(
                    id: mevcut.id,
                    ad: ad,
                    barkod: miktarli ? barkod : mevcut.barkod,
                    birim: miktarli ? birim : mevcut.birim,
                    kategori: kategori,
                    minStokSeviyesi: minStok,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  return;
                }

                // Aynı adlı model var mı?
                final tumu = await db.tumUrunler();
                Urun? ayniAd;
                for (final u in tumu) {
                  if (u.ad.toLowerCase() == ad.toLowerCase()) {
                    ayniAd = u;
                    break;
                  }
                }
                if (ayniAd != null && (seri.isEmpty || (ayniAd?.miktarli ?? false))) {
                  setState(() => hata = (ayniAd?.miktarli ?? false)
                      ? 'Bu malzeme zaten kayıtlı. Miktarı Depolar → '
                          'İşlemler → "Malzeme girişi" ile ekleyin.'
                      : 'Bu model zaten kayıtlı. Seri numarası girerek '
                          'mevcut modele ekleyebilirsiniz.');
                  return;
                }

                if (seri.isNotEmpty) {
                  if (depoId == null) {
                    setState(() => hata = depolar.isEmpty
                        ? 'Önce Depolar sekmesinden bir depo ekleyin'
                        : 'Depo seçin');
                    return;
                  }
                  final kayitli = await db.seriNoIleCihazBilgi(seri);
                  if (kayitli != null) {
                    final ayniModel =
                        ayniAd != null && kayitli.cihaz.urunId == ayniAd.id;
                    if (kayitli.cihaz.durum == CihazDurumu.depoda) {
                      setState(() => hata =
                          '$seri zaten kayıtlı: ${kayitli.urunAdi} (${kayitli.depoAdi ?? '-'})');
                      return;
                    }
                    if (!ayniModel) {
                      setState(() =>
                          hata = '$seri başka modele ait: ${kayitli.urunAdi}');
                      return;
                    }
                  }
                }

                final urunId = ayniAd?.id ??
                    await db.urunEkle(
                      ad: ad,
                      kategori: kategori,
                      minStokSeviyesi: minStok,
                      seriTakipli: !miktarli,
                      birim: miktarli ? birim : 'adet',
                      barkod: miktarli ? barkod : null,
                    );

                if (seri.isNotEmpty) {
                  await db.cihazlariGirisYap(
                    urunId: urunId,
                    depoId: depoId!,
                    seriNolar: [seri],
                    kullaniciId:
                        ref.read(aktifKullaniciIdProvider) ?? 'demo-kullanici',
                  );
                  SesServisi.basari();
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (e) {
                SesServisi.hata();
                setState(() => hata =
                    e is StateError ? e.message : 'Kaydedilemedi: $e');
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    ),
  );
}
