import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../database/app_database.dart';
import '../../providers/app_providers.dart';
import '../../database/models.dart';
import '../../services/rapor/rapor_modeli.dart';
import '../../services/rapor/rapor_olusturucu.dart';
import 'rapor_onizleme_screen.dart';
import 'sayim_screen.dart';

class KullanimRaporScreen extends ConsumerStatefulWidget {
  const KullanimRaporScreen({super.key});

  @override
  ConsumerState<KullanimRaporScreen> createState() => _KullanimRaporScreenState();
}

class _KullanimRaporScreenState extends ConsumerState<KullanimRaporScreen> {
  late Future<List<KullanimRaporSatiri>> _future;
  final _tarihFormat = DateFormat('dd.MM.yyyy HH:mm');
  DateTimeRange? _tarihAraligi;

  @override
  void initState() {
    super.initState();
    _yenile();
  }

  void _yenile() {
    _future = ref.read(appDatabaseProvider).kullanimRaporu(
          baslangic: _tarihAraligi?.start,
          bitis: _bitisGunSonu(),
        );
  }

  Future<void> _tarihAraligiSec() async {
    final simdi = DateTime.now();
    final secilen = await showDateRangePicker(
      context: context,
      firstDate: DateTime(simdi.year - 2),
      lastDate: simdi,
      initialDateRange: _tarihAraligi,
    );
    if (secilen != null) {
      setState(() {
        _tarihAraligi = secilen;
        _yenile();
      });
    }
  }

  /// Rapor türünü seçtirir, raporu hazırlar ve önizleme ekranını açar.
  /// PDF ve Excel çıktısı önizleme ekranındaki düğmelerden alınır.
  Future<void> _raporSec() async {
    final aralik = _tarihAraligi == null
        ? 'Tüm zamanlar'
        : '${DateFormat('dd.MM.yyyy').format(_tarihAraligi!.start)} - '
            '${DateFormat('dd.MM.yyyy').format(_tarihAraligi!.end)}';
    final tur = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
         child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Rapor oluştur',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: const Text('Ürünler'),
              subtitle: const Text('Ürün çeşidine göre ayrılmış cihaz listesi'),
              onTap: () => Navigator.pop(ctx, 'urunler'),
            ),
            ListTile(
              leading: const Icon(Icons.inventory_outlined),
              title: const Text('Ürün stok durumu'),
              subtitle: const Text(
                  'Seçilen ürün: depoda, araçta, sahada kullanılan, çıkan'),
              onTap: () => Navigator.pop(ctx, 'stok'),
            ),
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('Garanti durumu'),
              subtitle: const Text(
                  'Garantisi biten, yakında bitecek ve devam eden cihazlar'),
              onTap: () => Navigator.pop(ctx, 'garanti'),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Alımlar (ihale / firma)'),
              subtitle: const Text('İhale ve firmaya göre ayrılmış cihazlar'),
              onTap: () => Navigator.pop(ctx, 'alimlar'),
            ),
            ListTile(
              leading: const Icon(Icons.local_shipping_outlined),
              title: const Text('Kullanım raporu'),
              subtitle: Text('Sahada kullanılanlar · $aralik'),
              onTap: () => Navigator.pop(ctx, 'kullanim'),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Hareket geçmişi'),
              subtitle: Text('Giriş, transfer, kullanım, iade, çıkış · $aralik'),
              onTap: () => Navigator.pop(ctx, 'hareketler'),
            ),
          ],
         ),
        ),
      ),
    );
    if (tur == null || !mounted) return;

    final db = ref.read(appDatabaseProvider);
    Urun? urun;
    if (tur == 'stok') {
      urun = await _urunSec();
      if (urun == null || !mounted) return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final Rapor rapor;
      switch (tur) {
        case 'urunler':
          rapor = await RaporOlusturucu.urunler(db);
          break;
        case 'stok':
          rapor = await RaporOlusturucu.urunStokDurumu(db, urun!);
          break;
        case 'garanti':
          rapor = await RaporOlusturucu.garanti(db);
          break;
        case 'alimlar':
          rapor = await RaporOlusturucu.alimlar(db);
          break;
        case 'hareketler':
          rapor = await RaporOlusturucu.hareketler(db,
              baslangic: _tarihAraligi?.start, bitis: _bitisGunSonu());
          break;
        default:
          rapor = await RaporOlusturucu.kullanim(db,
              baslangic: _tarihAraligi?.start, bitis: _bitisGunSonu());
      }
      navigator.push(MaterialPageRoute(
          builder: (_) => RaporOnizlemeScreen(rapor: rapor)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Rapor hazırlanamadı: $e'),
        backgroundColor: Colors.red.shade700,
      ));
    }
  }

  /// Aranabilir ürün seçme penceresi.
  Future<Urun?> _urunSec() async {
    final urunler = List<Urun>.of(
        await ref.read(appDatabaseProvider).tumUrunler())
      ..sort((a, b) => a.ad.toLowerCase().compareTo(b.ad.toLowerCase()));
    if (!mounted) return null;
    if (urunler.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Henüz ürün tanımlanmamış')));
      return null;
    }
    var filtre = '';
    return showDialog<Urun>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final liste = urunler
              .where((u) =>
                  filtre.isEmpty ||
                  u.ad.toLowerCase().contains(filtre) ||
                  (u.kategori ?? '').toLowerCase().contains(filtre))
              .toList();
          return AlertDialog(
            title: const Text('Ürün seçin'),
            contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            content: SizedBox(
              width: 400,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Ürün veya kategori ara',
                    ),
                    onChanged: (v) =>
                        setState(() => filtre = v.trim().toLowerCase()),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: liste.length,
                      itemBuilder: (_, i) => ListTile(
                        dense: true,
                        title: Text(liste[i].ad),
                        subtitle: liste[i].kategori == null
                            ? null
                            : Text(liste[i].kategori!),
                        onTap: () => Navigator.pop(ctx, liste[i]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('İptal')),
            ],
          );
        },
      ),
    );
  }

  /// Tarih aralığının son gününü de kapsasın (23:59'a kadar).
  DateTime? _bitisGunSonu() {
    final b = _tarihAraligi?.end;
    if (b == null) return null;
    return DateTime(b.year, b.month, b.day, 23, 59, 59, 999);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Raporlar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: 'Tarih aralığı seç',
            onPressed: _tarihAraligiSec,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(_yenile),
          ),
          IconButton(
            icon: const Icon(Icons.fact_check_outlined),
            tooltip: 'Sayım',
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SayimScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.summarize_outlined),
            tooltip: 'Rapor oluştur (PDF / Excel)',
            onPressed: _raporSec,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_tarihAraligi != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.filter_alt_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${DateFormat('dd.MM.yyyy').format(_tarihAraligi!.start)} - '
                      '${DateFormat('dd.MM.yyyy').format(_tarihAraligi!.end)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _tarihAraligi = null;
                      _yenile();
                    }),
                    child: const Text('Temizle'),
                  ),
                ],
              ),
            ),
          Expanded(child: _raporListesi()),
        ],
      ),
    );
  }

  Widget _raporListesi() {
    return FutureBuilder<List<KullanimRaporSatiri>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Hata: ${snapshot.error}'));
          }
          final satirlar = snapshot.data ?? [];
          if (satirlar.isEmpty) {
            return const Center(child: Text('Henüz kullanım kaydı yok'));
          }

          return ListView.separated(
            itemCount: satirlar.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final s = satirlar[i];
              final hedef = s.aracPlaka ?? s.kullanimYeri ?? 'Belirtilmedi';
              return ListTile(
                leading: const Icon(Icons.local_shipping_outlined),
                title: Text(s.seriNo == null ? '${s.urunAdi} · ${s.miktar} adet' : s.urunAdi),
                subtitle: Text([
                  if (s.seriNo != null) 'SN: ${s.seriNo}',
                  '${s.depoAdi} → $hedef',
                ].join('\n')),
                isThreeLine: s.seriNo != null,
                trailing: Text(
                  _tarihFormat.format(s.tarih),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              );
            },
          );
        },
      );
  }
}
