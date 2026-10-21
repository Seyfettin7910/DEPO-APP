import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../database/app_database.dart';
import '../../providers/app_providers.dart';
import '../../services/etiket/etiket_pdf.dart';
import '../../services/etiket/etiket_sablonu.dart';
import '../../widgets/kod_yardimci.dart';
import 'etiket_sablon_screen.dart';
import '../../widgets/pdf_onizleme.dart';

/// Basım kuyruğu: etiketler yalnızca bilgisayardan (web sürümü) basılır.
/// Baskıdan sonra düzgün çıkanlar "basıldı" olarak işaretlenir; bozuk
/// çıkanlar kuyrukta kalır.
class EtiketBasimScreen extends ConsumerStatefulWidget {
  const EtiketBasimScreen({super.key});

  @override
  ConsumerState<EtiketBasimScreen> createState() => _EtiketBasimScreenState();
}

class _EtiketBasimScreenState extends ConsumerState<EtiketBasimScreen> {
  final _secili = <String>{};
  bool _ilkSecim = true;
  EtiketSablonu? _sablon;
  int _basSatir = 1;
  int _basSutun = 1;
  bool _calisiyor = false;

  static final _gun = DateFormat('dd.MM.yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    EtiketSablonu.yukle().then((s) {
      if (mounted) setState(() => _sablon = s);
    });
  }

  Future<void> _sablonDegistir() async {
    final s = await Navigator.of(context).push<EtiketSablonu>(
        MaterialPageRoute(builder: (_) => const EtiketSablonScreen()));
    final yeni = s ?? await EtiketSablonu.yukle();
    if (mounted) {
      setState(() {
        _sablon = yeni;
        _basSatir = 1;
        _basSutun = 1;
      });
    }
  }

  int get _baslangic {
    final s = _sablon;
    if (s == null || s.rulo) return 0;
    return (_basSatir - 1) * s.sutun + (_basSutun - 1);
  }

  Future<void> _bas(List<EtiketBilgi> liste, {required bool indir}) async {
    final s = _sablon;
    if (s == null) return;
    final secilen = liste.where((e) => _secili.contains(e.id)).toList();
    if (secilen.isEmpty) return;
    setState(() => _calisiyor = true);
    try {
      final Uint8List pdf =
          await EtiketPdf.olustur(secilen, s, baslangic: _baslangic);
      final ad = 'etiketler_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}';
      if (indir) {
        await Printing.sharePdf(bytes: pdf, filename: '$ad.pdf');
      } else {
        // 1.29.2: önce büyütülebilir önizleme; vazgeçilirse "basıldı mı?"
        // sorulmaz.
        if (!mounted) return;
        final yapildi = await PdfOnizleme.ac(context,
            bytes: pdf, ad: ad, format: EtiketPdf.sayfaFormati(s));
        if (!yapildi) return;
      }
      if (!mounted) return;
      await _basildiSor(secilen);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('PDF hazırlanamadı: $e'),
          backgroundColor: Colors.red.shade700,
        ));
      }
    } finally {
      if (mounted) setState(() => _calisiyor = false);
    }
  }

  /// Baskı sonrası: düzgün çıkanlar işaretlenir, bozuklar kuyrukta kalır.
  Future<void> _basildiSor(List<EtiketBilgi> basilan) async {
    final iyi = {for (final e in basilan) e.id};
    final onay = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Hangileri düzgün basıldı?'),
          content: SizedBox(
            width: 460,
            height: 380,
            child: Column(
              children: [
                const Text(
                    'İşaretini kaldırdıklarınız (sıkışan, bozuk çıkan) kuyrukta '
                    'kalır ve tekrar basılabilir.'),
                Row(
                  children: [
                    TextButton(
                        onPressed: () => setState(() =>
                            iyi.addAll(basilan.map((e) => e.id))),
                        child: const Text('Hepsi')),
                    TextButton(
                        onPressed: () => setState(iyi.clear),
                        child: const Text('Hiçbiri')),
                    const Spacer(),
                    Text('${iyi.length} / ${basilan.length}'),
                  ],
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final e in basilan)
                        CheckboxListTile(
                          dense: true,
                          value: iyi.contains(e.id),
                          title: Text(e.kod),
                          subtitle: Text('${e.urunAdi} · ${e.seriNosuz ? 'seri nosuz' : e.seriNo}'),
                          onChanged: (v) => setState(() =>
                              v == true ? iyi.add(e.id) : iyi.remove(e.id)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Daha sonra')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Kaydet')),
          ],
        ),
      ),
    );
    if (onay != true || iyi.isEmpty || !mounted) return;
    await ref.read(appDatabaseProvider).basildiIsaretle(
          etiketIdleri: iyi.toList(),
          kullaniciId: ref.read(aktifKullaniciIdProvider) ?? 'demo-kullanici',
        );
    if (!mounted) return;
    setState(() => _secili.removeAll(iyi));
    final dogrulama = ref.read(etiketAyarlariProvider).valueOrNull?.dogrulama ?? true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${iyi.length} etiket basıldı olarak işaretlendi'
          '${dogrulama ? '. Yapıştırdıktan sonra telefondan "Etiket doğrula" ile doğrulayın.' : ''}'),
      duration: const Duration(seconds: 5),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(etiketListesiProvider(EtiketDurumu.kuyrukta));
    final liste = async.value ?? const <EtiketBilgi>[];
    final masaustu = bilgisayarTarayicisi;

    // İlk açılışta hepsi seçili; kuyruktan çıkanlar seçimden düşer.
    if (async.hasValue) {
      final idler = {for (final e in liste) e.id};
      if (_ilkSecim) {
        _secili.addAll(idler);
        _ilkSecim = false;
      } else {
        _secili.removeWhere((id) => !idler.contains(id));
      }
    }

    // Ürün · depo grupları
    final gruplar = <String, List<EtiketBilgi>>{};
    for (final e in liste) {
      gruplar.putIfAbsent('${e.urunAdi} · ${e.depoAdi ?? '-'}', () => []).add(e);
    }
    final s = _sablon;

    return Scaffold(
      appBar: AppBar(
        title: Text('Etiket basımı (${liste.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.straighten),
            tooltip: 'Etiket kağıdı ve hizalama',
            onPressed: _sablonDegistir,
          ),
        ],
      ),
      body: Column(
        children: [
          if (!masaustu)
            MaterialBanner(
              content: const Text(
                  'Etiketler bilgisayardan basılır: bilgisayarda web sürümünü '
                  'açıp Etiketler → Etiket basımı. Telefonda yalnızca kuyruk '
                  'görüntülenir.'),
              leading: const Icon(Icons.computer),
              actions: [const SizedBox.shrink()],
            ),
          if (masaustu)
            Card(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.description_outlined),
                        const SizedBox(width: 8),
                        Text(s == null ? 'Şablon yükleniyor…' : s.ad,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        TextButton(
                            onPressed: _sablonDegistir,
                            child: const Text('Değiştir / hizala')),
                      ],
                    ),
                    if (s != null && !s.rulo)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Başlangıç: '),
                          DropdownButton<int>(
                            value: _basSatir.clamp(1, s.satir),
                            items: [
                              for (var i = 1; i <= s.satir; i++)
                                DropdownMenuItem(value: i, child: Text('$i. satır')),
                            ],
                            onChanged: (v) => setState(() => _basSatir = v ?? 1),
                          ),
                          const SizedBox(width: 8),
                          DropdownButton<int>(
                            value: _basSutun.clamp(1, s.sutun),
                            items: [
                              for (var i = 1; i <= s.sutun; i++)
                                DropdownMenuItem(value: i, child: Text('$i. etiket')),
                            ],
                            onChanged: (v) => setState(() => _basSutun = v ?? 1),
                          ),
                        ],
                      ),
                    Text(
                      'Yazdırırken ölçek: "Gerçek boyut" / %100 '
                      '("Sayfaya sığdır" kapalı)',
                      style: TextStyle(
                          color: Colors.orange.shade900, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: async.isLoading && !async.hasValue
                ? const Center(child: CircularProgressIndicator())
                : liste.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Basım kuyruğunda etiket yok.',
                              textAlign: TextAlign.center),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 16),
                        children: [
                          for (final g in gruplar.entries) ...[
                            CheckboxListTile(
                              tristate: true,
                              enabled: masaustu,
                              value: g.value.every((e) => _secili.contains(e.id))
                                  ? true
                                  : (g.value.any((e) => _secili.contains(e.id))
                                      ? null
                                      : false),
                              title: Text('${g.key} (${g.value.length})',
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              onChanged: (_) => setState(() {
                                final hepsi =
                                    g.value.every((e) => _secili.contains(e.id));
                                for (final e in g.value) {
                                  hepsi ? _secili.remove(e.id) : _secili.add(e.id);
                                }
                              }),
                            ),
                            for (final e in g.value)
                              CheckboxListTile(
                                dense: true,
                                enabled: masaustu,
                                contentPadding:
                                    const EdgeInsets.only(left: 40, right: 16),
                                value: _secili.contains(e.id),
                                title: Text(e.kod),
                                subtitle: Text([
                                  e.seriNosuz ? 'Seri nosuz' : 'SN ${e.seriNo}',
                                  if (e.surum > 1) 'yeniden basım (sürüm ${e.surum})',
                                  _gun.format(e.olusturma),
                                ].join(' · ')),
                                onChanged: (v) => setState(() => v == true
                                    ? _secili.add(e.id)
                                    : _secili.remove(e.id)),
                              ),
                          ],
                        ],
                      ),
          ),
          if (masaustu)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Row(
                  children: [
                    Text('Seçili: ${_secili.length}'
                        '${s == null || s.rulo || _secili.isEmpty ? '' : ' · ${((_secili.length + _baslangic) / s.sayfadakiEtiket).ceil()} sayfa'}'),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: _calisiyor || _secili.isEmpty || s == null
                          ? null
                          : () => _bas(liste, indir: true),
                      icon: const Icon(Icons.download),
                      label: const Text('PDF indir'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _calisiyor || _secili.isEmpty || s == null
                          ? null
                          : () => _bas(liste, indir: false),
                      icon: const Icon(Icons.print),
                      label: Text('Yazdır (${_secili.length})'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
