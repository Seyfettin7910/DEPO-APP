import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Yeni sürüm kontrolü.
/// - Telefon: GitHub'daki en son APK sürümüne bakar, "İndir" ile APK linkini açar.
/// - Web: sitedeki version.json'a bakar, "Yenile" ile sayfayı yeniler.
/// Sürüm numarası derleme sırasında (--dart-define=APP_SURUM=...) gömülür;
/// gömülmemişse (ör. FlutLab derlemesi) kontrol yapılmaz.
class GuncellemeServisi {
  static const mevcutSurum = String.fromEnvironment('APP_SURUM');
  static const _repo = 'Seyfettin7910/DEPO-APP';
  static const apkLinki =
      'https://github.com/$_repo/releases/latest/download/depo-takip.apk';

  static DateTime? _sonKontrol;
  static final _ertelenen = <String>{};

  /// Daha yeni bir sürüm varsa numarasını döndürür.
  static Future<String?> yeniSurum() async {
    if (mevcutSurum.isEmpty) return null;
    try {
      String? enSon;
      if (kIsWeb) {
        final r = await http
            .get(Uri.base.resolve(
                'version.json?t=${DateTime.now().millisecondsSinceEpoch}'))
            .timeout(const Duration(seconds: 10));
        if (r.statusCode == 200) {
          enSon = (jsonDecode(r.body) as Map<String, dynamic>)['surum'] as String?;
        }
      } else {
        final r = await http.get(
          Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
          headers: {'Accept': 'application/vnd.github+json'},
        ).timeout(const Duration(seconds: 10));
        if (r.statusCode == 200) {
          final tag = (jsonDecode(r.body) as Map<String, dynamic>)['tag_name']
              as String?;
          enSon = tag?.replaceFirst(RegExp(r'^v'), '');
        }
      }
      if (enSon != null && _dahaYeni(enSon, mevcutSurum)) return enSon;
    } catch (_) {
      // İnternet yoksa sessizce geç.
    }
    return null;
  }

  /// "1.10.0" > "1.9.2" gibi parça parça karşılaştırma.
  static bool _dahaYeni(String a, String b) {
    List<int> parca(String s) => s
        .split('+')
        .first
        .split('.')
        .map((p) => int.tryParse(p.trim()) ?? 0)
        .toList();
    final x = parca(a), y = parca(b);
    for (var i = 0; i < 3; i++) {
      final xi = i < x.length ? x[i] : 0;
      final yi = i < y.length ? y[i] : 0;
      if (xi != yi) return xi > yi;
    }
    return false;
  }

  /// Gerekirse kontrol eder ve yeni sürüm varsa kullanıcıya sorar.
  /// En fazla 6 saatte bir sunucuya sorar (zorla = true hariç).
  static Future<void> kontrolEtVeSor(BuildContext context,
      {bool zorla = false}) async {
    final simdi = DateTime.now();
    if (!zorla &&
        _sonKontrol != null &&
        simdi.difference(_sonKontrol!) < const Duration(hours: 6)) {
      return;
    }
    _sonKontrol = simdi;

    final yeni = await yeniSurum();
    if (yeni == null || _ertelenen.contains(yeni) || !context.mounted) return;

    final sonuc = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.system_update),
        title: const Text('Yeni sürüm var'),
        content: Text(kIsWeb
            ? 'Depo Takip $yeni yayınlandı (şu an: $mevcutSurum).\n'
                'Sayfayı yenileyerek güncel sürüme geçebilirsiniz.'
            : 'Depo Takip $yeni hazır (telefondaki: $mevcutSurum).\n\n'
                'İndirdikten sonra açıp "Güncelle"ye basın; uygulama '
                'silinmeden güncellenir, verileriniz kalır.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Sonra')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: Icon(kIsWeb ? Icons.refresh : Icons.download),
            label: Text(kIsWeb ? 'Yenile' : 'İndir'),
          ),
        ],
      ),
    );

    if (sonuc != true) {
      _ertelenen.add(yeni); // bu oturumda bir daha sorma
      return;
    }
    if (kIsWeb) {
      await launchUrl(Uri.base.removeFragment(), webOnlyWindowName: '_self');
    } else {
      await launchUrl(Uri.parse(apkLinki),
          mode: LaunchMode.externalApplication);
    }
  }
}
