import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../services/etiket/etiket_pdf.dart';
import '../../services/etiket/etiket_sablonu.dart';

/// Etiket kağıdı / rulo ölçüleri ve hizalama. Bu bilgisayarda saklanır.
class EtiketSablonScreen extends StatefulWidget {
  const EtiketSablonScreen({super.key});

  @override
  State<EtiketSablonScreen> createState() => _EtiketSablonScreenState();
}

class _EtiketSablonScreenState extends State<EtiketSablonScreen> {
  EtiketSablonu? _s;
  final _c = <String, TextEditingController>{};
  final _kurumCtrl = TextEditingController();

  static const _alanlar = <String, String>{
    'etiketGenislik': 'Etiket genişliği (mm)',
    'etiketYukseklik': 'Etiket yüksekliği (mm)',
    'sutun': 'Sütun (yan yana)',
    'satir': 'Satır (alt alta)',
    'ustKenar': 'Üst kenar boşluğu (mm)',
    'solKenar': 'Sol kenar boşluğu (mm)',
    'yatayAra': 'Etiketler arası yatay boşluk (mm)',
    'dikeyAra': 'Etiketler arası dikey boşluk (mm)',
    'sayfaGenislik': 'Sayfa genişliği (mm)',
    'sayfaYukseklik': 'Sayfa yüksekliği (mm)',
    'kaydirX': 'Kaydır: sağa + / sola − (mm)',
    'kaydirY': 'Kaydır: aşağı + / yukarı − (mm)',
  };

  @override
  void initState() {
    super.initState();
    EtiketSablonu.yukle().then((s) {
      if (mounted) _doldur(s);
    });
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    _kurumCtrl.dispose();
    super.dispose();
  }

  String _yaz(num v) {
    final d = v.toDouble();
    return d == d.roundToDouble()
        ? d.toStringAsFixed(0)
        : d.toString().replaceAll('.', ',');
  }

  void _doldur(EtiketSablonu s) {
    final j = s.toJson();
    for (final k in _alanlar.keys) {
      (_c[k] ??= TextEditingController()).text = _yaz(j[k] as num);
    }
    _kurumCtrl.text = s.kurumAdi;
    setState(() => _s = s);
  }

  double _sayi(String k, double eski) =>
      double.tryParse(_c[k]!.text.trim().replaceAll(',', '.')) ?? eski;

  EtiketSablonu _oku() {
    final s = _s!;
    return s.kopya(
      etiketGenislik: _sayi('etiketGenislik', s.etiketGenislik),
      etiketYukseklik: _sayi('etiketYukseklik', s.etiketYukseklik),
      sutun: _sayi('sutun', s.sutun.toDouble()).round(),
      satir: _sayi('satir', s.satir.toDouble()).round(),
      ustKenar: _sayi('ustKenar', s.ustKenar),
      solKenar: _sayi('solKenar', s.solKenar),
      yatayAra: _sayi('yatayAra', s.yatayAra),
      dikeyAra: _sayi('dikeyAra', s.dikeyAra),
      sayfaGenislik: _sayi('sayfaGenislik', s.sayfaGenislik),
      sayfaYukseklik: _sayi('sayfaYukseklik', s.sayfaYukseklik),
      kaydirX: _sayi('kaydirX', s.kaydirX),
      kaydirY: _sayi('kaydirY', s.kaydirY),
      kurumAdi: _kurumCtrl.text.trim(),
    );
  }

  Future<void> _kaydet({bool kapat = true}) async {
    final s = _oku();
    final h = s.hata();
    if (h != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(h), backgroundColor: Colors.red.shade700));
      return;
    }
    await s.kaydet();
    if (!mounted) return;
    setState(() => _s = s);
    if (kapat) Navigator.pop(context, s);
  }

  Future<void> _yazdir(Future<Uint8List> Function(EtiketSablonu) pdf,
      String ad) async {
    final s = _oku();
    final h = s.hata();
    if (h != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(h), backgroundColor: Colors.red.shade700));
      return;
    }
    final bytes = await pdf(s);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: ad,
      format: EtiketPdf.sayfaFormati(s),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Etiket kağıdı ve hizalama'),
        actions: [
          TextButton(
            onPressed: s == null ? null : () => _kaydet(),
            child: const Text('Kaydet'),
          ),
        ],
      ),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: EtiketSablonu.hazirlar.any((h) => h.ad == s.ad)
                      ? s.ad
                      : null,
                  hint: Text(s.ad),
                  decoration: const InputDecoration(
                      labelText: 'Hazır ölçü (paketteki ölçüyle karşılaştırın)'),
                  items: [
                    for (final h in EtiketSablonu.hazirlar)
                      DropdownMenuItem(value: h.ad, child: Text(h.ad)),
                  ],
                  onChanged: (ad) {
                    final h = EtiketSablonu.hazirlar.firstWhere((x) => x.ad == ad);
                    // Kaydırma, çizgi barkod ve kurum adı korunur.
                    _doldur(h.kopya(
                      kaydirX: _sayi('kaydirX', s.kaydirX),
                      kaydirY: _sayi('kaydirY', s.kaydirY),
                      cizgiBarkod: s.cizgiBarkod,
                      kurumAdi: _kurumCtrl.text.trim(),
                    ));
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: s.rulo,
                  title: const Text('Rulo etiket (etiket yazıcısı)'),
                  subtitle: const Text(
                      'Her etiket ayrı sayfa; sayfa boyutu = etiket boyutu'),
                  onChanged: (v) => setState(() =>
                      _s = _oku().kopya(rulo: v, ad: 'Özel ölçü')),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: s.cizgiBarkod,
                  title: const Text('Çizgi barkod da bas'),
                  subtitle: const Text(
                      'El tipi lazer okuyucular için (etiket en az 45×28 mm ise)'),
                  onChanged: (v) =>
                      setState(() => _s = _oku().kopya(cizgiBarkod: v)),
                ),
                TextField(
                  controller: _kurumCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Etiket üst yazısı (isteğe bağlı)',
                    hintText: 'Ör. T.C. ... Belediyesi Bilgi İşlem',
                    helperText: 'Etiket en az 30 mm yüksekse basılır',
                  ),
                ),
                const SizedBox(height: 16),
                Text('Ölçüler',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    for (final e in _alanlar.entries)
                      if (!s.rulo ||
                          {'etiketGenislik', 'etiketYukseklik', 'kaydirX', 'kaydirY'}
                              .contains(e.key))
                        SizedBox(
                          width: 240,
                          child: TextField(
                            controller: _c[e.key],
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: true),
                            decoration: InputDecoration(labelText: e.value),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                  ],
                ),
                const SizedBox(height: 8),
                Builder(builder: (_) {
                  final h = _oku().hata();
                  return Text(
                    h ?? _oku().olcuMetni,
                    style: TextStyle(
                        color: h == null
                            ? Theme.of(context).colorScheme.primary
                            : Colors.red.shade700),
                  );
                }),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Hizalama',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        const Text(
                          '1. Test sayfasını DÜZ kağıda basın (yazdırırken '
                          'ölçek: "Gerçek boyut" / %100, "Sayfaya sığdır" kapalı).\n'
                          '2. Etiket kağıdının üstüne koyup ışığa tutun: kırmızı '
                          'çerçeveler etiketlerin üstüne denk gelmeli.\n'
                          '3. Kayma varsa "Kaydır" değerlerini düzeltip tekrar deneyin.',
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _yazdir(
                                  EtiketPdf.hizalamaTesti, 'hizalama_testi'),
                              icon: const Icon(Icons.grid_on),
                              label: const Text('Hizalama test sayfası'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _yazdir(EtiketPdf.ornek, 'ornek_etiketler'),
                              icon: const Icon(Icons.qr_code_2),
                              label: const Text('Örnek etiketler'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _kaydet(),
                  icon: const Icon(Icons.save),
                  label: const Text('Kaydet'),
                ),
              ],
            ),
    );
  }
}
