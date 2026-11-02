import 'package:flutter/material.dart';

import '../services/zimmet_onayi.dart';
import 'buyuk_harf.dart';

/// Pencerenin sonucu: seçim yapıldı (kaydedilebilir) ya da onay yok
/// (kaydedilmez, girişim kaydedilir). Vazgeçilirse null döner.
class ZimmetSonucu {
  const ZimmetSonucu.secim(ZimmetSecimi this.secim) : engellendi = false;
  const ZimmetSonucu.engel()
      : secim = null,
        engellendi = true;

  final ZimmetSecimi? secim;
  final bool engellendi;
}

/// Ürün BELEDİYE ZİMMETİ deposundan montaja çıkarken sorulur
/// (1.32.0, bkz. services/zimmet_onayi.dart).
///   ○ Belediye hizmet yerine         → devam
///   ○ Kırsal mahalleye
///       ○ Onay var → Evrak sayısı (zorunlu) → devam
///       ○ Onay yok → "onay olmadan kullanılamaz", kaydedilmez
/// [urunler]: zimmetteki ürünlerin kısa listesi ("KAMERA · SN123").
Future<ZimmetSonucu?> zimmetOnayiSor(
  BuildContext context, {
  required List<String> urunler,
}) {
  String? yer;
  bool? onayVar;
  String? hata;
  final evrakCtrl = TextEditingController();

  return showDialog<ZimmetSonucu>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final engel = yer == zimmetYeriKirsal && onayVar == false;
      final renk = Theme.of(ctx).colorScheme;

      void devam() {
        if (engel) {
          Navigator.pop(ctx, const ZimmetSonucu.engel());
          return;
        }
        if (yer == zimmetYeriKirsal && onayVar == null) {
          setState(() => hata = 'Başkanlık onayı var mı, seçin');
          return;
        }
        final h = zimmetSecimiHatasi(
            zimmet: true, yer: yer, evrakSayisi: evrakCtrl.text);
        if (h != null) {
          setState(() => hata = h);
          return;
        }
        Navigator.pop(
            ctx,
            ZimmetSonucu.secim(ZimmetSecimi(
                yer!,
                yer == zimmetYeriKirsal ? evrakCtrl.text.trim() : null)));
      }

      return AlertDialog(
        icon: Icon(Icons.account_balance, color: renk.primary),
        title: const Text('Belediye Zimmeti'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                urunler.length == 1
                    ? 'Bu ürün Belediye Zimmeti deposunda:'
                    : 'Bu ürünler Belediye Zimmeti deposunda:',
              ),
              const SizedBox(height: 4),
              for (final u in urunler.take(4))
                Text('• $u', style: const TextStyle(fontWeight: FontWeight.w600)),
              if (urunler.length > 4) Text('• ve ${urunler.length - 4} ürün daha'),
              const SizedBox(height: 8),
              const Text('Kırsal mahallede kullanımı Başkanlık onayı gerektirir. '
                  'Nereye takılıyor?'),
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: const Text('Belediye hizmet yerine'),
                value: zimmetYeriHizmet,
                groupValue: yer,
                onChanged: (v) => setState(() {
                  yer = v;
                  hata = null;
                }),
              ),
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: const Text('Kırsal mahalleye'),
                value: zimmetYeriKirsal,
                groupValue: yer,
                onChanged: (v) => setState(() {
                  yer = v;
                  hata = null;
                }),
              ),
              if (yer == zimmetYeriKirsal) ...[
                const Divider(),
                const Text('Başkanlık onayı var mı?'),
                RadioListTile<bool>(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Var'),
                  value: true,
                  groupValue: onayVar,
                  onChanged: (v) => setState(() {
                    onayVar = v;
                    hata = null;
                  }),
                ),
                RadioListTile<bool>(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Yok'),
                  value: false,
                  groupValue: onayVar,
                  onChanged: (v) => setState(() {
                    onayVar = v;
                    hata = null;
                  }),
                ),
                if (onayVar == true)
                  TextField(
                    controller: evrakCtrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: metinBuyuk,
                    decoration: const InputDecoration(
                      labelText: 'Onay yazısının evrak sayısı (zorunlu)',
                      hintText: 'Örn. E-12345678-010.06-1234',
                    ),
                    onChanged: (_) {
                      if (hata != null) setState(() => hata = null);
                    },
                    onSubmitted: (_) => devam(),
                  ),
                if (engel)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: renk.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.block, color: renk.onErrorContainer),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$zimmetEngelMetni\nOnay yazısı geldikten sonra '
                            'montajı kaydedebilirsiniz.',
                            style: TextStyle(
                                color: renk.onErrorContainer,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              if (hata != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(hata!, style: TextStyle(color: renk.error)),
                ),
            ],
          ),
        ),
        actions: [
          if (!engel)
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Vazgeç')),
          FilledButton(
            onPressed: yer == null ? null : devam,
            child: Text(engel ? 'Tamam' : 'Devam'),
          ),
        ],
      );
    }),
  );
}
