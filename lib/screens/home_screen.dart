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
import '../widgets/sync_durum_dugmesi.dart';
import '../widgets/yarim_isler.dart';
import 'depo/depo_list_screen.dart';
import 'urun/urun_list_screen.dart';
import 'cihaz/cihaz_ara_screen.dart';
import 'hareket/barkod_tarama_screen.dart';
import 'rapor/kullanim_rapor_screen.dart';
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
    await GuncellemeServisi.kontrolEt(acilis: true);
  }

  Future<void> _bildirimleriHazirla() async {
    if (kIsWeb) {
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
      // Arka plan görevi oturumu yenilemiş olabilir.
      unawaited(SupabaseService.oturumuDisktenYenile());
      unawaited(GuncellemeServisi.kontrolEt());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(onPlandaIsaretle(false));
    }
  }

  /// Son öğe ("Çıkış") sekme değil; onay sorup oturumu kapatır.
  void _sec(int i) {
    if (i == _screens.length) {
      cikisYapOnayli(context, ref);
      return;
    }
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    // Menü telefonda da bilgisayarda da (web) altta.
    const destinations = [
      NavigationDestination(icon: Icon(Icons.warehouse_outlined), label: 'Depolar'),
      NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Ürünler'),
      NavigationDestination(icon: Icon(Icons.qr_code_scanner), label: 'Okut'),
      NavigationDestination(icon: Icon(Icons.search), label: 'Ara'),
      NavigationDestination(icon: Icon(Icons.bar_chart_outlined), label: 'Raporlar'),
      NavigationDestination(icon: Icon(Icons.logout), label: 'Çıkış'),
    ];

    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _sec,
        destinations: destinations,
      ),
    );
  }
}
