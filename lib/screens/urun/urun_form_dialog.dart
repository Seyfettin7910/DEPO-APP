import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/models.dart';
import '../../providers/app_providers.dart';
import '../../services/ses_servisi.dart';
import '../../widgets/barkod_okuyucu_sayfasi.dart';
import '../../widgets/depo_secici.dart';

/// Yeni ürün (model) ekler; [mevcut] verilirse o ürünü düzenler.
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
              if (mevcut == null) ...[
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
                decoration: const InputDecoration(
                    labelText: 'Minimum adet uyarısı (opsiyonel)',
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
              final seri = seriCtrl.text.trim().toUpperCase();

              try {
                if (mevcut != null) {
                  await db.urunGuncelle(
                    id: mevcut.id,
                    ad: ad,
                    barkod: mevcut.barkod,
                    birim: mevcut.birim,
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
                if (ayniAd != null && seri.isEmpty) {
                  setState(() => hata =
                      'Bu model zaten kayıtlı. Seri numarası girerek mevcut modele ekleyebilirsiniz.');
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
