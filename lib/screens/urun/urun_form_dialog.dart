import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart';
import '../../database/models.dart';
import '../../providers/app_providers.dart';
import '../../services/ses_servisi.dart';
import '../../widgets/barkod_okuyucu_sayfasi.dart';
import '../../widgets/depo_secici.dart';
import '../../widgets/buyuk_harf.dart';
import '../../services/urun_adi.dart';
import '../../widgets/benzer_urun.dart';
import '../../widgets/urun_birlestir.dart';
import '../../services/kurum_barkodu.dart';

/// Yeni ürün (model) ekler; [mevcut] verilirse o ürünü düzenler.
///
/// Takip türü: "Seri no" (her cihaz seri numarasıyla) ya da "Miktar"
/// (kablo, adaptör gibi seri numarasız malzemeler: adet, metre, paket…).
/// Malzemede fabrika barkodu kaydedilirse girişte okutularak seçilir.
///
/// Yeni üründe seri numarası (kamerayla okutulabilir) ve depo seçilirse,
/// ürün kaydedilirken o cihaz da seçilen depoya girilir. Aynı model adı
/// zaten varsa yeni model açılmaz, seri no mevcut modele eklenir.
///
/// [malzeme]: Okut'tan "+ Yeni malzeme tanımla" (Miktarla seçili, [barkod]
/// hazır). Kaydedilen ürünün id'si döner (vazgeçilirse null).
///
/// [sadeceModel] (1.30.1): Depoya girişteki "+ Yeni" düğmesi: yalnız seri no
/// ile takip edilen model tanımlanır (ad, kategori, uyarı sayısı); seri no ve
/// depo alanları gizli (giriş ekranı onları zaten biliyor).
Future<String?> urunFormDialog(BuildContext context, WidgetRef ref,
    {Urun? mevcut,
    bool malzeme = false,
    String? barkod,
    bool sadeceModel = false}) {
  final adCtrl = TextEditingController(text: mevcut?.ad ?? '');
  final seriCtrl = TextEditingController();
  // 1.30.3: kategori açılır listeden (ürünlerdeki kategoriler, alfabetik)
  // ya da "+ Yeni" ile.
  String? kategori =
      (mevcut?.kategori ?? '').trim().isEmpty ? null : mevcut!.kategori!.trim();
  final kategoriler = <String>{
    for (final u in ref.read(urunlerStreamProvider).valueOrNull ?? <Urun>[])
      if ((u.kategori ?? '').trim().isNotEmpty) u.kategori!.trim(),
    if (kategori != null) kategori,
  }.toList()
    ..sort(trKarsilastir);
  final minStokCtrl =
      TextEditingController(text: '${mevcut?.minStokSeviyesi ?? 0}');
  final barkodCtrl =
      TextEditingController(text: mevcut?.barkod ?? barkod ?? '');
  final kutuCtrl = TextEditingController(
      text: mevcut?.kutuIcerigi == null ? '' : '${mevcut!.kutuIcerigi}');
  var miktarli = mevcut?.miktarli ?? malzeme;
  var birim = mevcut != null && malzemeBirimleri.contains(mevcut.birim)
      ? mevcut.birim
      : 'adet';
  final depolar = ref.read(depolarStreamProvider).valueOrNull ?? <Depo>[];
  String? depoId = ref.read(seciliDepoIdProvider);
  if (!depolar.any((d) => d.id == depoId)) {
    depoId = depolar.isEmpty ? null : depolar.first.id;
  }
  String? hata;

  return showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(mevcut != null
            ? 'Ürünü Düzenle'
            : (sadeceModel ? 'Yeni Model' : 'Yeni Ürün')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                textCapitalization: TextCapitalization.characters,
                // 1.29.3: ürün / model adı Latin kuralla (hikvision →
                // HIKVISION); Türkçe İ isteyen klavyeden kendisi yazar.
                inputFormatters: kodBuyuk,
                controller: adCtrl,
                decoration:
                    const InputDecoration(labelText: 'Ürün / model adı'),
                autofocus: mevcut == null,
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: kategori,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: 'Kategori / tür'),
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('Kategorisiz')),
                        for (final k in kategoriler)
                          DropdownMenuItem<String?>(
                              value: k,
                              child: Text(k, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => kategori = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Yeni'),
                    onPressed: () async {
                      final k = await _yeniKategori(ctx, kategoriler);
                      if (k == null) return;
                      setState(() {
                        if (!kategoriler.contains(k)) {
                          kategoriler
                            ..add(k)
                            ..sort(trKarsilastir);
                        }
                        kategori = k;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (mevcut == null && !malzeme && !sadeceModel)
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
                  controller: kutuCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Bir kutu / top içeriği ($birim, isteğe bağlı)',
                    hintText: 'Örn: 305',
                    helperText: 'Barkodu her okutuşta bu kadar eklenir '
                        '(boşsa 1)',
                  ),
                ),
                TextField(
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: kodBuyuk,
                  controller: barkodCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Barkod (boşsa stok kodu üretilir)',
                    helperText: kurumBarkoduMu(barkodCtrl.text.trim())
                        ? 'Stok kodu (266…): kutulara bu etiket basılır'
                        : 'Girişte okutularak seçilir',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      tooltip: 'Kamera ile oku',
                      onPressed: () async {
                        final kod = await Navigator.of(ctx).push<String>(
                          MaterialPageRoute(
                            builder: (_) => const BarkodOkuyucuSayfasi(urunBarkodu: true),
                          ),
                        );
                        if (kod != null) {
                          barkodCtrl.text = kod.trim().toUpperCase();
                          setState(() {});
                        }
                      },
                    ),
                  ),
                ),
                // 1.30.2 / 1.30.3: 266'lı stok kodu (kurum içi EAN-13);
                // fabrika barkodu girildiyse onun yerine de verilebilir.
                if (!kurumBarkoduMu(barkodCtrl.text.trim()))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.qr_code_2),
                      label: Text(barkodCtrl.text.trim().isEmpty
                          ? 'Stok kodunu şimdi üret (266…)'
                          : 'Fabrika barkodu yerine stok kodu (266…)'),
                      onPressed: () async {
                        try {
                          final k = await ref
                              .read(appDatabaseProvider)
                              .benzersizKurumBarkodu();
                          barkodCtrl.text = k;
                          setState(() => hata = null);
                        } catch (e) {
                          setState(() => hata = '$e');
                        }
                      },
                    ),
                  ),
              ],
              if (mevcut == null && !miktarli && !sadeceModel) ...[
                TextField(
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: kodBuyuk,
                  controller: seriCtrl,
                  autocorrect: false,
                  enableSuggestions: false,
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
                        ? 'Minimum miktar uyarısı ($birim, isteğe bağlı)'
                        : 'Minimum adet uyarısı (isteğe bağlı)',
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
              final minStok = int.tryParse(minStokCtrl.text.trim()) ?? 0;
              final seri = miktarli ? '' : seriCtrl.text.trim().toUpperCase();
              var barkod =
                  barkodCtrl.text.trim().isEmpty ? null : barkodCtrl.text.trim();
              final kutu = int.tryParse(kutuCtrl.text.trim());
              final kutuIcerigi =
                  miktarli && kutu != null && kutu > 1 ? kutu : null;

              try {
                // 1.30.3: barkodu boş malzemeye kaydederken stok kodu.
                if (miktarli && barkod == null) {
                  barkod = await db.benzersizKurumBarkodu();
                }
                if (barkod != null && barkod != mevcut?.barkod) {
                  final ayni = await db.barkodIleUrunBul(barkod);
                  if (ayni != null && !ayni.deleted && ayni.id != mevcut?.id) {
                    setState(() =>
                        hata = 'Bu barkod zaten ${ayni.ad} için kayıtlı');
                    return;
                  }
                }
                if (mevcut != null) {
                  // Ad değiştiyse ve aynı adda (İ / I, boşluk farkı hariç)
                  // başka ürün varsa uyar (birleştirme sonraki sürümde).
                  if (ad != mevcut.ad) {
                    final anahtar = urunAdiAnahtari(ad);
                    final cakisan = (await db.tumUrunler())
                        .where((u) =>
                            u.id != mevcut.id &&
                            urunAdiAnahtari(u.ad) == anahtar)
                        .toList();
                    if (cakisan.isNotEmpty) {
                      if (!ctx.mounted) return;
                      final karar = await benzerAdUyarisi(ctx, cakisan);
                      if (karar == null || !ctx.mounted) return;
                      if (karar == 'birlestir') {
                        // 1.30.0: bu ürün çakışan ürüne katılır.
                        final hedefId = await urunBirlestirAkisi(
                            ctx, ref, mevcut,
                            adaylar: cakisan);
                        if (hedefId != null && dialogContext.mounted) {
                          Navigator.pop(dialogContext, hedefId);
                        }
                        return;
                      }
                    }
                  }
                  await db.urunGuncelle(
                    id: mevcut.id,
                    ad: ad,
                    barkod: miktarli ? barkod : mevcut.barkod,
                    birim: miktarli ? birim : mevcut.birim,
                    kategori: kategori,
                    minStokSeviyesi: minStok,
                    kutuIcerigi: miktarli ? kutuIcerigi : mevcut.kutuIcerigi,
                  );
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, mevcut.id);
                  }
                  return;
                }

                // 1.29.3: aynı / benzer adlı ürün var mı? (İ / I, büyük /
                // küçük harf, boşluk farkı yok sayılır) Varsa seçim ekranı.
                final anahtar = urunAdiAnahtari(ad);
                final benzerler = (await db.tumUrunler())
                    .where((u) => urunAdiAnahtari(u.ad) == anahtar)
                    .toList();
                Urun? ayniAd;
                if (benzerler.isNotEmpty) {
                  if (!ctx.mounted) return;
                  final secim = await benzerUrunSec(ctx, benzerler);
                  if (secim == null) return; // forma dönülür
                  if (secim is Urun) ayniAd = secim;
                }
                if (ayniAd != null) {
                  if (ayniAd.miktarli != miktarli) {
                    setState(() => hata = 'Seçilen ürünün takip türü farklı '
                        '(${ayniAd!.miktarli ? 'miktarla' : 'seri no ile'}). '
                        'Takip türünü değiştirin ya da yeni ürün oluşturun.');
                    return;
                  }
                  if (seri.isEmpty) {
                    // Var olan ürün kullanılır; malzemede barkodu yoksa
                    // girilen barkod ona yazılır.
                    if (ayniAd.miktarli &&
                        barkod != null &&
                        (ayniAd.barkod ?? '').isEmpty) {
                      await db.urunGuncelle(
                        id: ayniAd.id,
                        ad: ayniAd.ad,
                        barkod: barkod,
                        birim: ayniAd.birim,
                        kategori: ayniAd.kategori,
                        minStokSeviyesi: ayniAd.minStokSeviyesi,
                        kutuIcerigi: ayniAd.kutuIcerigi ?? kutuIcerigi,
                      );
                    }
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext, ayniAd.id);
                    }
                    return;
                  }
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
                      kutuIcerigi: kutuIcerigi,
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
                if (dialogContext.mounted) Navigator.pop(dialogContext, urunId);
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

/// 1.30.3: yeni kategori adı; aynı / benzer (İ / I, boşluk farkı) kategori
/// varsa uyarır ve onu seçmeyi önerir.
Future<String?> _yeniKategori(BuildContext context, List<String> mevcutlar) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final ad = ctrl.text.trim();
      final anahtar = urunAdiAnahtari(ad);
      final benzer = ad.isEmpty
          ? null
          : mevcutlar
              .where((k) => urunAdiAnahtari(k) == anahtar)
              .firstOrNull;
      return AlertDialog(
        title: const Text('Yeni kategori'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: metinBuyuk,
              decoration: const InputDecoration(
                  labelText: 'Kategori adı', hintText: 'ÖRN: KAYIT CİHAZLARI'),
              onChanged: (_) => setState(() {}),
            ),
            if (benzer != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Bu kategori zaten var: $benzer',
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç')),
          if (benzer != null)
            FilledButton(
                onPressed: () => Navigator.pop(ctx, benzer),
                child: const Text('Var olanı seç'))
          else
            FilledButton(
                onPressed: ad.isEmpty ? null : () => Navigator.pop(ctx, ad),
                child: const Text('Ekle')),
        ],
      );
    }),
  );
}
