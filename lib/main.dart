import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'database/platform/db_fabrika.dart';

import 'services/cihaz_tercihleri.dart';
import 'services/gorunum_ayari.dart';
import 'services/ses_servisi.dart';
import 'services/guncelleme_servisi.dart';
import 'services/oturum_kilidi.dart';
import 'services/supabase_service.dart';
import 'screens/giris/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Yayın sürümünde bir ekran çizilirken hata olursa gri/beyaz kutu yerine
  // hatanın kendisi görünsün (ekran görüntüsüyle bildirilebilsin).
  ErrorWidget.builder = (details) => Material(
        color: Colors.white,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Ekran hatası:\n${details.exceptionAsString()}',
            style: const TextStyle(color: Colors.red, fontSize: 13),
          ),
        ),
      );

  // Uygulama hemen açılır; Supabase ve veritabanı hazırlığı açılış
  // ekranında yapılır. Böylece takılan/çöken bir adım beyaz ekran yerine
  // anlaşılır bir hata mesajı olarak görünür.
  // Web duman testi (tool/web_duman_testi.py): ?semantik=1 ile ekrandaki
  // yazılar tarayıcıda okunabilir olsun.
  if (kIsWeb && Uri.base.queryParameters['semantik'] == '1') {
    SemanticsBinding.instance.ensureSemantics();
  }
  await GorunumAyari.yukle();
  await CihazTercihleri.yukle();
  runApp(const ProviderScope(child: DepoApp()));
}

class DepoApp extends StatelessWidget {
  const DepoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DEPO YÖNETİM SİSTEMİ',
      debugShowCheckedModeBanner: false,
      // Güncelleme penceresi hangi ekranda olunursa olsun açılabilsin.
      navigatorKey: GuncellemeServisi.navigatorKey,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E6F40),
        useMaterial3: true,
      ),
      // Her dokunuş "kullanıcı aktif" sayılır (5 dk hareketsizlik kilidi).
      builder: (context, child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          OturumKilidi.instance.etkinlik();
          SesServisi.ilkDokunus(); // iPhone: ilk okutmada da ses çıksın
        },
        child: GorunumAyari.uygula(
            context, altCubukPayi(context, child ?? const SizedBox())),
      ),
      home: const BaslangicEkrani(),
    );
  }
}

/// 1.29.2: Yeni Android sürümleri uygulamayı ekranın en altına kadar çiziyor;
/// alttaki düğmeler (Kaydet, PDF / Excel…) telefonun geri / ana ekran
/// tuşlarının arkasında kalmasın diye bütün ekranlara alt pay verilir. Pay
/// alt menü rengindedir; klavye açıkken pay kendiliğinden kalkar.
Widget altCubukPayi(BuildContext context, Widget child) => ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(top: false, left: false, right: false, child: child),
    );

/// Açılış hazırlığını yapar, bitince giriş/ana ekrana geçer.
class BaslangicEkrani extends StatefulWidget {
  const BaslangicEkrani({super.key});

  @override
  State<BaslangicEkrani> createState() => _BaslangicEkraniState();
}

class _BaslangicEkraniState extends State<BaslangicEkrani> {
  bool _hazir = false;
  String? _hata;
  String _adim = 'Başlatılıyor...';

  @override
  void initState() {
    super.initState();
    _baslat();
  }

  Future<void> _baslat() async {
    setState(() {
      _hata = null;
      _adim = 'Başlatılıyor...';
    });
    try {
      // Türkçe tarih biçimleri (ay adları vb.) raporlarda kullanılır.
      await initializeDateFormatting('tr_TR');

      setState(() => _adim = 'Yerel veritabanı hazırlanıyor...');
      veritabaniFabrikasiniAyarla();

      setState(() => _adim = 'Sunucu bağlantısı hazırlanıyor...');
      await SupabaseService.init().timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException(
            'Sunucu bağlantısı hazırlanırken 20 sn içinde yanıt gelmedi'),
      );

      await OturumKilidi.instance.baslat();

      if (mounted) setState(() => _hazir = true);
    } catch (e, st) {
      debugPrint('Açılış hatası: $e\n$st');
      if (mounted) {
        setState(() => _hata = '$_adim\n\n$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hazir) return const AuthGate();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/logo.png',
                    width: 80, height: 80, filterQuality: FilterQuality.medium),
                const SizedBox(height: 16),
                if (_hata == null) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_adim, textAlign: TextAlign.center),
                ] else ...[
                  const Text('Uygulama başlatılamadı',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SelectableText(
                    _hata!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _baslat,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tekrar dene'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
