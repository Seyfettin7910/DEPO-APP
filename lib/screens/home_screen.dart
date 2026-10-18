import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../widgets/sync_durum_dugmesi.dart';
import 'depo/depo_list_screen.dart';
import 'urun/urun_list_screen.dart';
import 'cihaz/cihaz_ara_screen.dart';
import 'hareket/barkod_tarama_screen.dart';
import 'rapor/kullanim_rapor_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _index = 0;

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
    // Geniş ekranlarda (Windows masaüstü) yan menü, dar ekranlarda
    // (telefon) alt gezinme çubuğu kullanılır.
    final genisEkran = MediaQuery.of(context).size.width >= 700;

    final destinations = const [
      NavigationDestination(icon: Icon(Icons.warehouse_outlined), label: 'Depolar'),
      NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Ürünler'),
      NavigationDestination(icon: Icon(Icons.qr_code_scanner), label: 'Tarama'),
      NavigationDestination(icon: Icon(Icons.search), label: 'Ara'),
      NavigationDestination(icon: Icon(Icons.bar_chart_outlined), label: 'Raporlar'),
      NavigationDestination(icon: Icon(Icons.logout), label: 'Çıkış'),
    ];

    if (genisEkran) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: _sec,
              labelType: NavigationRailLabelType.all,
              destinations: destinations
                  .map((d) => NavigationRailDestination(
                        icon: d.icon,
                        label: Text(d.label),
                      ))
                  .toList(),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _screens[_index]),
          ],
        ),
      );
    }

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
