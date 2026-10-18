import 'package:flutter/material.dart';

import '../../services/excel_rapor_service.dart';
import '../../services/pdf_report_service.dart';
import '../../services/rapor/rapor_modeli.dart';

/// Bir raporu uygulama içinde gösterir; üstteki düğmelerle aynı raporu
/// PDF veya Excel olarak dışa aktarır (ikisi de aynı başlıklarla).
class RaporOnizlemeScreen extends StatefulWidget {
  const RaporOnizlemeScreen({super.key, required this.rapor});

  final Rapor rapor;

  @override
  State<RaporOnizlemeScreen> createState() => _RaporOnizlemeScreenState();
}

class _RaporOnizlemeScreenState extends State<RaporOnizlemeScreen> {
  bool _calisiyor = false;

  /// Önizlemede bölüm başına gösterilen en fazla satır (tamamı dosyada).
  static const _onizlemeSiniri = 200;

  Future<void> _disaAktar(bool pdf) async {
    if (_calisiyor) return;
    setState(() => _calisiyor = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (pdf) {
        await PdfReportService.paylas(widget.rapor);
      } else {
        await ExcelRaporService.paylas(widget.rapor);
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('${pdf ? 'PDF' : 'Excel'} oluşturulamadı: $e'),
        backgroundColor: Colors.red.shade700,
      ));
    } finally {
      if (mounted) setState(() => _calisiyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rapor;
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(r.baslik, overflow: TextOverflow.ellipsis),
        actions: [
          if (_calisiyor)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'PDF olarak al',
              onPressed: () => _disaAktar(true),
            ),
            IconButton(
              icon: const Icon(Icons.grid_on),
              tooltip: 'Excel olarak al',
              onPressed: () => _disaAktar(false),
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          Text(r.altBaslik, style: tema.textTheme.bodySmall),
          if (r.ozet.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in r.ozet)
                  Container(
                    constraints: const BoxConstraints(minWidth: 100),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: tema.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.key, style: tema.textTheme.labelSmall),
                        Text(e.value,
                            style: tema.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          for (final b in r.bolumler) _bolum(context, r, b),
        ],
      ),
    );
  }

  Widget _bolum(BuildContext context, Rapor r, RaporBolumu b) {
    final tema = Theme.of(context);
    final sutunlar = b.sutunlariAl(r);
    final gosterilen = b.satirlar.take(_onizlemeSiniri).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (b.baslik != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: tema.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(b.baslik!,
                  style: tema.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
          if (b.aciklama != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(b.aciklama!, style: tema.textTheme.bodySmall),
            ),
          const SizedBox(height: 4),
          if (b.satirlar.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('Kayıt yok', style: tema.textTheme.bodySmall),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 32,
                dataRowMaxHeight: 48,
                columnSpacing: 18,
                horizontalMargin: 8,
                headingTextStyle: tema.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
                columns: [for (final s in sutunlar) DataColumn(label: Text(s))],
                rows: [
                  for (final satir in gosterilen)
                    DataRow(cells: [
                      for (var i = 0; i < sutunlar.length; i++)
                        DataCell(Text(
                          i < satir.length ? (satir[i]?.toString() ?? '') : '',
                          style: tema.textTheme.bodySmall,
                        )),
                    ]),
                ],
              ),
            ),
          if (b.satirlar.length > gosterilen.length)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+${b.satirlar.length - gosterilen.length} satır daha '
                '(tamamı PDF ve Excel çıktısında)',
                style: tema.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
