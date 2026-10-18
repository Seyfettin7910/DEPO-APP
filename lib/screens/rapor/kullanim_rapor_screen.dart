import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../database/app_database.dart';
import '../../providers/app_providers.dart';
import '../../services/pdf_report_service.dart';

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
          bitis: _tarihAraligi?.end,
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

  Future<void> _pdfOlusturVePaylas() async {
    final satirlar = await _future;
    final doc = await PdfReportService.kullanimRaporuOlustur(
      satirlar: satirlar,
      baslangic: _tarihAraligi?.start,
      bitis: _tarihAraligi?.end,
    );

    // Layout callback: kullanıcı sistemin yazdır/PDF-olarak-kaydet/paylaş
    // diyaloğunu görür. iOS/Android'de paylaş menüsü, Windows'ta yazıcı
    // veya "PDF olarak kaydet" seçeneği olarak çıkar.
    await Printing.layoutPdf(
      onLayout: (format) => doc.save(),
      name: 'kullanim_raporu_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kullanım Raporu'),
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
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'PDF olarak dışa aktar',
            onPressed: _pdfOlusturVePaylas,
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
