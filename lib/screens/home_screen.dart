import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/bildirim/arka_plan.dart';
import '../services/bildirim/bildirim_ayarlari.dart';
import '../services/bildirim/bildirim_gosterici.dart';
import '../services/bildirim/web_bildirim.dart';
import '../services/guncelleme_servisi.dart';
import '../services/supabase_service.dart';
import '../services/tarayici.dart';
import '../widgets/iphone_rehberi.dart';
import '../widgets/renkler.dart';
import '../widgets/yarim_isler.dart';
import 'depo/depo_list_screen.dart';
import 'urun/urun_list_screen.dart';
import 'cihaz/cihaz_ara_screen.dart';
import 'hareket/barkod_tarama_screen.dart';
import 'rapor/kullanim_rapor_screen.dart';
import 'ayarlar_screen.dart';
import 'yenilikler_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  // Açılış ekranı: telefonda (uygulama veya iPhone/Android tarayıcısı)
  // seri no okutma; bilgisayar tarayıcısında Depolar.
  int _index = _bilgisayarTarayicisi ? 0 : 2;

  static bool get _bilgisayarTarayicisi =>
      kIsWeb &&
      defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS;

  static const _screens = [
    DepoListScreen(),
    UrunListScreen(),
    BarkodTaramaScreen(),
    CihazAraScreen(),
    KullanimRaporScreen(),
    AyarlarScreen(),
  ];

  /// Alt menü: her bölüm kendi renginde; seçili olanın simgesi dolu.
  static const _menu = [
    (Icons.warehouse_outlined, Icons.warehouse, 'Depolar', Renkler.depo, Renkler.depoZemin),
    (Icons.inventory_2_outlined, Icons.inventory_2, 'Ürünler', Renkler.urun, Renkler.urunZemin),
    (Icons.qr_code_scanner, Icons.qr_code_scanner, 'Okut', Renkler.okut, Renkler.okutZemin),
    (Icons.search, Icons.search, 'Ara', Renkler.ara, Renkler.araZemin),
    (Icons.bar_chart_outlined, Icons.bar_chart, 'Raporlar', Renkler.rapor, Renkler.raporZemin),
    (Icons.settings_outlined, Icons.settings, 'Ayarlar', Renkler.ayar, Renkler.ayarZemin),
  ];

  @override
  void initState() {
    super.initState();
    // Sync servisini başlat (provider okunduğu an .start() tetiklenir).
    Future.microtask(() => ref.read(syncServiceProvider));

    // Açılış sırası: güncellemeden sonraki ilk açılışta "Yenilikler",
    // sonra yarım kalan işler, sonra yeni sürüm kontrolü. Uygulamaya
    // dönüşte ve açık kaldıkça 30 dakikada bir sürüm yeniden denetlenir.
    WidgetsBinding.instance.addObserver(this);
    unawaited(_acilisSirasi());
    GuncellemeServisi.baslat();

    // Bildirimler: izin (Android 13+), uygulama kapalıyken arka plan
    // kontrolü ve "uygulama açık" işareti (arka plan görevi o sırada durur).
    unawaited(_bildirimleriHazirla());
    _onPlanZamanlayici = Timer.periodic(
        const Duration(seconds: 45), (_) => onPlandaIsaretle(true));
  }

  Timer? _onPlanZamanlayici;

  Future<void> _acilisSirasi() async {
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    await yenilikleriGerekirseGoster(context);
    if (!mounted) return;
    await yarimIsleriGoster(context);
    if (!mounted) return;
    await anaEkranRehberiGerekirseGoster(context);
    if (!mounted) return;
    await GuncellemeServisi.kontrolEt(acilis: true);
  }

  Future<void> _bildirimleriHazirla() async {
    if (kIsWeb) {
      // Safari kullanılmayan sitelerin verisini silebilir: kalıcı saklama.
      unawaited(kaliciSaklamaIste());
      // Bu tarayıcı bildirime aboneyse kullanıcı ve ayarlar sunucuda tazelenir.
      unawaited(BildirimAyarlari.yukle().then(WebBildirim.guncelle));
      return;
    }
    await onPlandaIsaretle(true);
    await Future.delayed(const Duration(seconds: 5));
    await bildirimIzniIste();
    await arkaPlanBaslat();
  }

  @override
  void dispose() {
    _onPlanZamanlayici?.cancel();
    GuncellemeServisi.durdur();
    unawaited(onPlandaIsaretle(false));
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(onPlandaIsaretle(true));
      // Arka plan görevi oturumu yenilemiş olabilir; sonra tam senkron
      // (uygulama kapalıyken kaçan değişiklikler).
      unawaited(() async {
        try {
          await SupabaseService.oturumuDisktenYenile();
        } catch (_) {}
        if (mounted) unawaited(ref.read(syncServiceProvider).syncNow());
      }());
      unawaited(GuncellemeServisi.kontrolEt());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(onPlandaIsaretle(false));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Menü telefonda da bilgisayarda da (web) altta. Çıkış: Ayarlar'da.
    final secili = _menu[_index];
    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // iPhone'da Safari dışı tarayıcıda: "Safari'de açın" şeridi.
          const SafariUyarisi(),
          NavigationBar(
        selectedIndex: _index,
        indicatorColor: secili.$5,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final m in _menu)
            NavigationDestination(
              icon: Icon(m.$1, color: m.$4, size: 27),
              selectedIcon: Icon(m.$2, color: m.$4, size: 27),
              label: m.$3,
            ),
        ],
      ),
        ],
      ),
    );
  }
}
