import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/models.dart';

final _gun = DateFormat('dd.MM.yyyy');

/// Garanti bitiş tarihine göre kısa durum metni.
String garantiDurumMetni(DateTime? bitis) {
  if (bitis == null) return 'Garanti bilgisi yok';
  final bugun = DateUtils.dateOnly(DateTime.now());
  final kalan = DateUtils.dateOnly(bitis).difference(bugun).inDays;
  if (kalan < 0) return 'Garanti bitti (${_gun.format(bitis)})';
  if (kalan == 0) return 'Garanti bugün bitiyor';
  if (kalan <= 90) return 'Garanti bitiyor: $kalan gün kaldı (${_gun.format(bitis)})';
  return 'Garantide (${_gun.format(bitis)} tarihine kadar)';
}

Color garantiRengi(DateTime? bitis) {
  if (bitis == null) return Colors.grey;
  final kalan = DateUtils.dateOnly(bitis)
      .difference(DateUtils.dateOnly(DateTime.now()))
      .inDays;
  if (kalan < 0) return Colors.red.shade700;
  if (kalan <= 90) return Colors.orange.shade800;
  return Colors.green.shade700;
}

/// Alım tarihi, firma, ihale ve garanti alanları. [bilgi] nesnesini
/// doğrudan günceller. Firma ve ihale yazılırken daha önce girilenler
/// önerilir (aynı firmanın farklı yazılmasını önler).
class AlimBilgisiAlanlari extends StatefulWidget {
  const AlimBilgisiAlanlari({
    super.key,
    required this.bilgi,
    this.firmalar = const [],
    this.ihaleler = const [],
  });

  final AlimBilgisi bilgi;
  final List<String> firmalar;
  final List<String> ihaleler;

  @override
  State<AlimBilgisiAlanlari> createState() => _AlimBilgisiAlanlariState();
}

class _AlimBilgisiAlanlariState extends State<AlimBilgisiAlanlari> {
  AlimBilgisi get b => widget.bilgi;

  Future<DateTime?> _tarihSec(DateTime? ilk) {
    final simdi = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: ilk ?? simdi,
      firstDate: DateTime(simdi.year - 20),
      lastDate: DateTime(simdi.year + 15),
    );
  }

  void _garantiAy(int ay) {
    final baz = b.alimTarihi ?? DateTime.now();
    setState(() => b.garantiBitis = DateTime(baz.year, baz.month + ay, baz.day));
  }

  Widget _oneriliAlan({
    required String etiket,
    required IconData ikon,
    required String deger,
    required List<String> oneriler,
    required ValueChanged<String> degisti,
  }) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: deger),
      optionsBuilder: (v) {
        final q = v.text.trim().toLowerCase();
        if (q.isEmpty) return oneriler.take(20);
        return oneriler.where((o) => o.toLowerCase().contains(q)).take(20);
      },
      onSelected: degisti,
      fieldViewBuilder: (context, ctrl, odak, gonder) => TextField(
        controller: ctrl,
        focusNode: odak,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: etiket, prefixIcon: Icon(ikon)),
        onChanged: degisti,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Alım tarihi
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Alım tarihi',
            prefixIcon: Icon(Icons.event),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(b.alimTarihi == null
                    ? 'Seçilmedi'
                    : _gun.format(b.alimTarihi!)),
              ),
              TextButton(
                onPressed: () async {
                  final t = await _tarihSec(b.alimTarihi);
                  if (t != null) setState(() => b.alimTarihi = t);
                },
                child: const Text('Seç'),
              ),
              if (b.alimTarihi != null)
                IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: 'Temizle',
                  onPressed: () => setState(() => b.alimTarihi = null),
                ),
            ],
          ),
        ),
        _oneriliAlan(
          etiket: 'Alınan firma',
          ikon: Icons.store_outlined,
          deger: b.firma,
          oneriler: widget.firmalar,
          degisti: (v) => b.firma = v,
        ),
        _oneriliAlan(
          etiket: 'İhale / sipariş no',
          ikon: Icons.gavel_outlined,
          deger: b.ihale,
          oneriler: widget.ihaleler,
          degisti: (v) => b.ihale = v,
        ),
        const SizedBox(height: 8),
        // Garanti
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Garanti bitişi',
            prefixIcon: Icon(Icons.verified_user_outlined),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      b.garantiBitis == null
                          ? 'Seçilmedi'
                          : garantiDurumMetni(b.garantiBitis),
                      style: TextStyle(color: garantiRengi(b.garantiBitis)),
                    ),
                  ),
                  if (b.garantiBitis != null)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      tooltip: 'Temizle',
                      onPressed: () => setState(() => b.garantiBitis = null),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final ay in const [12, 24, 36, 60])
                    ActionChip(
                      label: Text('$ay ay'),
                      onPressed: () => _garantiAy(ay),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.calendar_month, size: 16),
                    label: const Text('Tarih seç'),
                    onPressed: () async {
                      final t = await _tarihSec(b.garantiBitis);
                      if (t != null) setState(() => b.garantiBitis = t);
                    },
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Ay seçince bitiş, alım tarihinden (yoksa bugünden) hesaplanır.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Alım bilgilerini bir pencerede düzenletir. Kopya üzerinde çalışır;
/// "Kaydet" denirse yeni bilgiyi, vazgeçilirse null döndürür.
Future<AlimBilgisi?> alimBilgisiPenceresi(
  BuildContext context, {
  required AlimBilgisi mevcut,
  required List<String> firmalar,
  required List<String> ihaleler,
  String baslik = 'Alım / garanti bilgileri',
  String? aciklama,
}) {
  final kopya = AlimBilgisi(
    alimTarihi: mevcut.alimTarihi,
    firma: mevcut.firma,
    ihale: mevcut.ihale,
    garantiBitis: mevcut.garantiBitis,
  );
  return showDialog<AlimBilgisi>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(baslik),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (aciklama != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(aciklama,
                    style: Theme.of(ctx).textTheme.bodySmall),
              ),
            AlimBilgisiAlanlari(
              bilgi: kopya,
              firmalar: firmalar,
              ihaleler: ihaleler,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, kopya),
            child: const Text('Tamam')),
      ],
    ),
  );
}

/// Alım bilgisinin tek satırlık özeti (liste/başlık altı için).
String alimOzeti(AlimBilgisi b) {
  if (b.bos) return 'Girilmedi';
  return [
    if (b.alimTarihi != null) 'Alım ${_gun.format(b.alimTarihi!)}',
    if (b.firmaVeyaNull != null) b.firmaVeyaNull!,
    if (b.ihaleVeyaNull != null) 'İhale: ${b.ihaleVeyaNull}',
    if (b.garantiBitis != null) 'Garanti ${_gun.format(b.garantiBitis!)}',
  ].join(' · ');
}
