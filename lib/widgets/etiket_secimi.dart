import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/etiket_modelleri.dart';

/// Kurum etiketi tercihi: hangi kurum kodu (null: kod üretilmez) ve
/// etiketlerin basım kuyruğuna alınıp alınmayacağı. Son seçim telefonda
/// hatırlanır.
class EtiketTercihi {
  const EtiketTercihi({this.kurumKoduId, this.kuyruga = true});

  final String? kurumKoduId;
  final bool kuyruga;

  static const _kodAnahtari = 'etiket_kurum_kodu';
  static const _kuyrukAnahtari = 'etiket_kuyruga';

  static Future<EtiketTercihi> yukle(List<KurumKodu> aktifler) async {
    try {
      final p = await SharedPreferences.getInstance();
      final kayitli = p.getString(_kodAnahtari);
      final kuyruga = p.getBool(_kuyrukAnahtari) ?? true;
      String? id;
      if (kayitli == '-') {
        id = null; // kullanıcı "kod üretme"yi seçmiş
      } else if (kayitli != null && aktifler.any((k) => k.id == kayitli)) {
        id = kayitli;
      } else if (aktifler.length == 1) {
        id = aktifler.first.id;
      }
      return EtiketTercihi(kurumKoduId: id, kuyruga: kuyruga);
    } catch (_) {
      return EtiketTercihi(
          kurumKoduId: aktifler.length == 1 ? aktifler.first.id : null);
    }
  }

  Future<void> kaydet() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kodAnahtari, kurumKoduId ?? '-');
      await p.setBool(_kuyrukAnahtari, kuyruga);
    } catch (_) {}
  }

  String ozet(List<KurumKodu> kodlar) {
    final k = kodlar.where((x) => x.id == kurumKoduId).firstOrNull;
    if (k == null) return 'Kod üretilmeyecek';
    return '${k.gorunen} · ${kuyruga ? 'basım kuyruğuna alınacak' : 'yalnızca sisteme kaydedilecek'}';
  }
}

/// Kurum kodu ve "basım kuyruğuna al" seçimi penceresi.
Future<EtiketTercihi?> etiketTercihiSec(
  BuildContext context, {
  required List<KurumKodu> kodlar,
  required EtiketTercihi mevcut,
  bool kodUretmeSecenegi = true,
  String baslik = 'Kurum etiketi',
}) {
  String? secili = mevcut.kurumKoduId;
  var kuyruga = mevcut.kuyruga;
  return showDialog<EtiketTercihi>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(baslik),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Seçilen kurum koduyla her cihaza benzersiz bir kod üretilir '
                  've cihazın seri numarasıyla eşleştirilir.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                if (kodUretmeSecenegi)
                  RadioListTile<String?>(
                    value: null,
                    groupValue: secili,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Kod üretme'),
                    onChanged: (v) => setState(() => secili = v),
                  ),
                for (final k in kodlar)
                  RadioListTile<String?>(
                    value: k.id,
                    groupValue: secili,
                    contentPadding: EdgeInsets.zero,
                    title: Text(k.kod,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: k.ad.isEmpty ? null : Text(k.ad),
                    onChanged: (v) => setState(() => secili = v),
                  ),
                const Divider(),
                SwitchListTile(
                  value: kuyruga,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Etiketleri basım kuyruğuna al'),
                  subtitle: const Text(
                      'Kapalıysa kod yalnızca sisteme kaydedilir; etiket '
                      'gerekirse sonra kuyruğa alınır.'),
                  onChanged: secili == null
                      ? null
                      : (v) => setState(() => kuyruga = v),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: (!kodUretmeSecenegi && secili == null)
                ? null
                : () => Navigator.pop(
                    ctx, EtiketTercihi(kurumKoduId: secili, kuyruga: kuyruga)),
            child: const Text('Tamam'),
          ),
        ],
      ),
    ),
  );
}

/// Etiket durumuna göre renk.
Color etiketDurumRengi(EtiketDurumu d) {
  switch (d) {
    case EtiketDurumu.kayitli:
      return Colors.blueGrey;
    case EtiketDurumu.kuyrukta:
      return Colors.indigo;
    case EtiketDurumu.basildi:
      return Colors.orange.shade800;
    case EtiketDurumu.dogrulandi:
      return Colors.green.shade700;
    case EtiketDurumu.uyusmazlik:
      return Colors.red.shade700;
  }
}

IconData etiketDurumIkonu(EtiketDurumu d) {
  switch (d) {
    case EtiketDurumu.kayitli:
      return Icons.qr_code_2;
    case EtiketDurumu.kuyrukta:
      return Icons.print_outlined;
    case EtiketDurumu.basildi:
      return Icons.label_outline;
    case EtiketDurumu.dogrulandi:
      return Icons.verified_outlined;
    case EtiketDurumu.uyusmazlik:
      return Icons.report_gmailerrorred;
  }
}
