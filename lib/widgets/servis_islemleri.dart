import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../database/app_database.dart';
import '../database/models.dart';
import '../providers/app_providers.dart';
import '../services/ses_servisi.dart';
import '../services/taslak_servisi.dart';
import 'alim_bilgisi_alanlari.dart';
import 'barkod_okuyucu_sayfasi.dart';
import 'depo_secici.dart';
import 'iade_sebebi.dart';
import 'kod_yardimci.dart';

final _tarihSaat = DateFormat('dd.MM.yyyy HH:mm');

const hurdaSebepleri = [
  'Teknolojik ömrünü doldurdu',
  'Onarılamaz arıza',
  'Fiziksel hasar',
  'Diğer',
];

Color servisRengi(ServisDurumu d) => switch (d) {
      ServisDurumu.tamirGerekli => Colors.orange.shade800,
      ServisDurumu.degisimGerekli => Colors.deepOrange.shade700,
      ServisDurumu.garantide => Colors.indigo.shade600,
      ServisDurumu.onarimda => Colors.blue.shade700,
      ServisDurumu.hurda => Colors.brown.shade600,
      ServisDurumu.degistirildi => Colors.blueGrey.shade600,
    };

IconData servisIkonu(ServisDurumu d) => switch (d) {
      ServisDurumu.tamirGerekli => Icons.build_outlined,
      ServisDurumu.degisimGerekli => Icons.sync_problem,
      ServisDurumu.garantide => Icons.local_post_office_outlined,
      ServisDurumu.onarimda => Icons.handyman_outlined,
      ServisDurumu.hurda => Icons.recycling,
      ServisDurumu.degistirildi => Icons.published_with_changes,
    };

/// Listelerde seri numarasının yanında küçük durum rozeti.
class ServisRozeti extends StatelessWidget {
  const ServisRozeti(this.durum, {super.key});
  final ServisDurumu durum;

  @override
  Widget build(BuildContext context) {
    final renk = servisRengi(durum);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: renk.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: renk.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(servisIkonu(durum), size: 13, color: renk),
          const SizedBox(width: 3),
          Text(durum.kisa,
              style: TextStyle(
                  fontSize: 11, color: renk, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

String _kullanici(WidgetRef ref) =>
    ref.read(aktifKullaniciIdProvider) ?? 'demo-kullanici';

Future<bool> _calistir(BuildContext context, Future<void> Function() islem,
    String basariMesaji) async {
  try {
    await islem();
    SesServisi.basari();
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(basariMesaji)));
    }
    return true;
  } catch (e) {
    SesServisi.hata();
    if (context.mounted) {
      final mesaj = e is StateError ? e.message : 'İşlem başarısız: $e';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(mesaj), backgroundColor: Colors.red.shade700));
    }
    return false;
  }
}

/// Tarih + saat seçimi. Vazgeçilirse null.
Future<DateTime?> tarihSaatSec(BuildContext context, DateTime ilk) async {
  final simdi = DateTime.now();
  final gun = await showDatePicker(
    context: context,
    initialDate: ilk,
    firstDate: DateTime(simdi.year - 5),
    lastDate: simdi.add(const Duration(days: 1)),
  );
  if (gun == null || !context.mounted) return null;
  final saat = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(ilk),
  );
  if (saat == null) return null;
  return DateTime(gun.year, gun.month, gun.day, saat.hour, saat.minute);
}

/// Tıklanınca tarih ve saat seçtiren alan.
class TarihSaatAlani extends StatelessWidget {
  const TarihSaatAlani({
    super.key,
    required this.etiket,
    required this.deger,
    required this.degisti,
  });

  final String etiket;
  final DateTime deger;
  final ValueChanged<DateTime> degisti;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final t = await tarihSaatSec(context, deger);
        if (t != null) degisti(t);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: etiket,
          prefixIcon: const Icon(Icons.schedule),
          suffixIcon: const Icon(Icons.edit_calendar_outlined),
        ),
        child: Text(_tarihSaat.format(deger)),
      ),
    );
  }
}

Widget _hataMetni(BuildContext ctx, String? hata) => hata == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(hata,
            style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
      );

// ---------------------------------------------------------------------
// Arızalı olarak işaretle (depodaki sağlam cihaz)
// ---------------------------------------------------------------------

Future<void> arizaliIsaretleAkisi(
    BuildContext context, WidgetRef ref, CihazBilgi b) async {
  final taslak = await PencereTaslagi.ac('ariza', b.cihaz.id,
      baslik: 'Arıza kaydı · SN ${b.cihaz.seriNo}');
  if (!context.mounted) {
    taslak.birak();
    return;
  }
  String? karar = taslak.deger<String>('karar');
  String? hata;
  final notCtrl = TextEditingController(text: taslak.deger<String>('not'));
  void taslakYaz() => taslak.yaz({'karar': karar, 'not': notCtrl.text},
      ozet: notCtrl.text.trim(),
      bos: karar == null && notCtrl.text.trim().isEmpty);
  notCtrl.addListener(taslakYaz);
  final onay = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        taslakYaz();
        return AlertDialog(
        scrollable: true,
        icon: Icon(Icons.build_outlined, color: Colors.orange.shade800),
        title: const Text('Arızalı olarak işaretle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (taslak.geriYuklendi) const GeriYuklendiNotu(),
            Text('${b.urunAdi} · SN: ${b.cihaz.seriNo}\n'
                '${b.depoAdi ?? '-'} içinde'),
            ArizaKarariSecici(
              secili: karar,
              onSecildi: (v) => setState(() {
                karar = v;
                hata = null;
              }),
            ),
            TextField(
              controller: notCtrl,
              decoration: const InputDecoration(
                labelText: 'Arıza açıklaması',
                hintText: 'Örn: görüntü gelmiyor, açılmıyor',
              ),
            ),
            _hataMetni(ctx, hata),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
            onPressed: () {
              if (karar == null) {
                setState(() => hata = 'Arıza durumunu seçin');
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Kaydet'),
          ),
        ],
      );
      },
    ),
  );
  await taslak.kapat();
  if (onay != true || !context.mounted) return;
  await _calistir(
    context,
    () => ref.read(appDatabaseProvider).arizaKaydiAc(
          cihazId: b.cihaz.id,
          karar: karar!,
          aciklama: notCtrl.text,
          kullaniciId: _kullanici(ref),
        ),
    'Arıza kaydı açıldı',
  );
}

// ---------------------------------------------------------------------
// Servise gönder (garanti / kendi bünyemiz)
// ---------------------------------------------------------------------

Future<void> servisGonderAkisi(
    BuildContext context, WidgetRef ref, CihazBilgi b) async {
  final db = ref.read(appDatabaseProvider);
  final firmalar = await db.oncekiServisFirmalari();
  if (!context.mounted) return;

  final c = b.cihaz;
  final taslak = await PencereTaslagi.ac('servis_gonder', c.id,
      baslik: 'Servise gönder · SN ${c.seriNo}');
  if (!context.mounted) {
    taslak.birak();
    return;
  }
  final garantiVar = c.garantiBitis != null &&
      !DateUtils.dateOnly(c.garantiBitis!)
          .isBefore(DateUtils.dateOnly(DateTime.now()));
  var yer = taslak.deger<String>('yer') ?? (garantiVar ? 'garanti' : 'ic');
  var tarih = taslak.tarih('tarih') ?? DateTime.now();
  var firma =
      taslak.deger<String>('firma') ?? (garantiVar ? (c.firma ?? '') : '');
  String? hata;
  final notCtrl = TextEditingController(text: taslak.deger<String>('not'));
  final degisim = c.servisDurumu == ServisDurumu.degisimGerekli;
  final ilkFirma = firma;
  void taslakYaz() => taslak.yaz({
        'yer': yer,
        'tarih': tarih.millisecondsSinceEpoch,
        'firma': firma,
        'not': notCtrl.text,
      },
          ozet: firma.trim(),
          bos: !taslak.geriYuklendi &&
              firma == ilkFirma &&
              notCtrl.text.trim().isEmpty);
  notCtrl.addListener(taslakYaz);

  final onay = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        taslakYaz();
        return AlertDialog(
        scrollable: true,
        title: Text(degisim ? 'Değişim için gönder' : 'Onarıma gönder'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (taslak.geriYuklendi) const GeriYuklendiNotu(),
            Text('${b.urunAdi} · SN: ${c.seriNo}'),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.verified_user_outlined,
                    size: 18, color: garantiRengi(c.garantiBitis)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(garantiDurumMetni(c.garantiBitis),
                      style: TextStyle(
                          color: garantiRengi(c.garantiBitis),
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            if (c.firma != null)
              Padding(
                padding: const EdgeInsets.only(left: 24, top: 2),
                child: Text('Alındığı firma: ${c.firma}',
                    style: Theme.of(ctx).textTheme.bodySmall),
              ),
            const SizedBox(height: 12),
            Text('Onarım nerede yapılacak?',
                style: Theme.of(ctx).textTheme.labelLarge),
            const SizedBox(height: 4),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'garanti',
                    icon: Icon(Icons.local_post_office_outlined),
                    label: Text('Garanti (firma)')),
                ButtonSegment(
                    value: 'ic',
                    icon: Icon(Icons.handyman_outlined),
                    label: Text('Kendi bünyemiz')),
              ],
              selected: {yer},
              onSelectionChanged: (s) => setState(() {
                yer = s.first;
                hata = null;
                if (yer == 'garanti' && firma.isEmpty) firma = c.firma ?? '';
              }),
            ),
            if (yer == 'garanti' && !garantiVar)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  c.garantiBitis == null
                      ? 'Garanti bilgisi girilmemiş; firmayla teyit edin.'
                      : 'Garanti süresi dolmuş görünüyor; ücretli onarım olabilir.',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                ),
              ),
            const SizedBox(height: 8),
            Autocomplete<String>(
              key: ValueKey(yer),
              initialValue: TextEditingValue(text: firma),
              optionsBuilder: (v) {
                final q = v.text.trim().toLowerCase();
                if (q.isEmpty) return firmalar.take(20);
                return firmalar
                    .where((o) => o.toLowerCase().contains(q))
                    .take(20);
              },
              onSelected: (v) {
                firma = v;
                taslakYaz();
              },
              fieldViewBuilder: (context, ctrl, odak, gonder) => TextField(
                controller: ctrl,
                focusNode: odak,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: yer == 'garanti'
                      ? 'Gönderilen firma (zorunlu)'
                      : 'Onarımı yapan birim / kişi (opsiyonel)',
                  prefixIcon: const Icon(Icons.store_outlined),
                ),
                onChanged: (v) {
                  firma = v;
                  taslakYaz();
                  if (hata != null) setState(() => hata = null);
                },
              ),
            ),
            const SizedBox(height: 8),
            TarihSaatAlani(
              etiket: yer == 'garanti'
                  ? 'Gönderim tarihi ve saati'
                  : 'Onarıma alma tarihi ve saati',
              deger: tarih,
              degisti: (t) => setState(() => tarih = t),
            ),
            TextField(
              controller: notCtrl,
              decoration: const InputDecoration(
                labelText: 'Not (opsiyonel)',
                hintText: 'Örn: kargo takip no, servis fiş no',
              ),
            ),
            _hataMetni(ctx, hata),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
            onPressed: () {
              if (yer == 'garanti' && firma.trim().isEmpty) {
                setState(() => hata = 'Gönderilen firmayı yazın');
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: Text(yer == 'garanti' ? 'Gönderildi' : 'Onarıma al'),
          ),
        ],
      );
      },
    ),
  );
  await taslak.kapat();
  if (onay != true || !context.mounted) return;
  await _calistir(
    context,
    () => db.servisGonder(
      cihazId: c.id,
      yer: yer,
      firma: firma,
      tarih: tarih,
      not_: notCtrl.text,
      kullaniciId: _kullanici(ref),
    ),
    yer == 'garanti'
        ? 'Garanti servisine gönderildi'
        : 'Onarıma alındı',
  );
}

// ---------------------------------------------------------------------
// Servis sonucu
// ---------------------------------------------------------------------

Future<void> servisSonucuAkisi(BuildContext context, WidgetRef ref,
    CihazBilgi b, ServisKaydi? kayit) async {
  final depolar = (ref.read(depolarStreamProvider).valueOrNull ?? <Depo>[])
      .where((d) => !d.arac)
      .toList();
  if (depolar.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Önce depo ekleyin')));
    return;
  }
  final c = b.cihaz;
  final taslak = await PencereTaslagi.ac('servis_sonuc', c.id,
      baslik: 'Onarım sonucu · SN ${c.seriNo}');
  if (!context.mounted) {
    taslak.birak();
    return;
  }
  final kayitliHedef = taslak.deger<String>('hedef');
  String? hedef = kayitliHedef != null && depolar.any((d) => d.id == kayitliHedef)
      ? kayitliHedef
      : (depolar.any((d) => d.id == c.depoId) ? c.depoId : depolar.first.id);
  var donus = taslak.tarih('donus') ?? DateTime.now();
  String? sonuc = taslak.deger<String>('sonuc');
  var hurda = taslak.deger<bool>('hurda') ?? true;
  String? hata;
  final aciklamaCtrl =
      TextEditingController(text: taslak.deger<String>('aciklama'));
  final yeniSeriCtrl =
      TextEditingController(text: taslak.deger<String>('yeniSeri'));
  final gonderim = kayit?.gonderimTarihi;
  void taslakYaz() => taslak.yaz({
        'hedef': hedef,
        'donus': donus.millisecondsSinceEpoch,
        'sonuc': sonuc,
        'hurda': hurda,
        'aciklama': aciklamaCtrl.text,
        'yeniSeri': yeniSeriCtrl.text,
      },
          ozet: servisSonucAdlari[sonuc] ?? '',
          bos: sonuc == null && aciklamaCtrl.text.trim().isEmpty);
  aciklamaCtrl.addListener(taslakYaz);
  yeniSeriCtrl.addListener(taslakYaz);

  final onay = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        taslakYaz();
        return AlertDialog(
        scrollable: true,
        title: const Text('Onarım sonucu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (taslak.geriYuklendi) const GeriYuklendiNotu(),
            Text('${b.urunAdi} · SN: ${c.seriNo}'),
            if (kayit?.firma != null)
              Text('${onarimYeriAdlari[kayit!.onarimYeri] ?? 'Servis'}: '
                  '${kayit.firma}',
                  style: Theme.of(ctx).textTheme.bodySmall),
            if (gonderim != null)
              Text('Gönderim: ${_tarihSaat.format(gonderim)}',
                  style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 8),
            TarihSaatAlani(
              etiket: 'Dönüş tarihi ve saati',
              deger: donus,
              degisti: (t) => setState(() {
                donus = t;
                hata = null;
              }),
            ),
            if (gonderim != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Onarım süresi: ${sureMetni(donus.difference(gonderim))}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(height: 12),
            Text('Sonuç', style: Theme.of(ctx).textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final e in servisSonucAdlari.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: sonuc == e.key,
                    onSelected: (s) => setState(() {
                      sonuc = s ? e.key : null;
                      hata = null;
                    }),
                  ),
              ],
            ),
            if (sonuc == 'onarildi' || sonuc == 'degistirildi') ...[
              if (sonuc == 'degistirildi')
                Builder(builder: (_) {
                  Future<void> kameraAc() async {
                    final kod = await Navigator.of(ctx).push<String>(
                      MaterialPageRoute(
                          builder: (_) => const BarkodOkuyucuSayfasi()),
                    );
                    if (kod == null || kod.trim().isEmpty) return;
                    final seriler = seriNolariAyir(kod);
                    setState(() {
                      if (seriler.length > 1) {
                        yeniSeriCtrl.clear();
                        hata = 'Koli karekodu okutuldu (${seriler.length} '
                            'seri no). Yeni cihazın kendi seri numarasını okutun.';
                      } else {
                        yeniSeriCtrl.text = seriler.first;
                        hata = null;
                      }
                    });
                  }

                  // Telefonda hatalı girişi önlemek için yalnızca kamerayla
                  // okutulur; bilgisayarda USB barkod okuyucu yazabilir.
                  return TextField(
                    controller: yeniSeriCtrl,
                    readOnly: !bilgisayarTarayicisi,
                    onTap: bilgisayarTarayicisi ? null : kameraAc,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Yeni cihazın seri numarası',
                      hintText: bilgisayarTarayicisi
                          ? 'Barkod okuyucuyla okutun'
                          : 'Okutmak için dokunun',
                      prefixIcon: const Icon(Icons.qr_code_2),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.photo_camera_outlined),
                        tooltip: 'Kamerayla okut',
                        onPressed: kameraAc,
                      ),
                    ),
                    onChanged: (_) {
                      if (hata != null) setState(() => hata = null);
                    },
                  );
                }),
              DropdownButtonFormField<String>(
                value: hedef,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText: sonuc == 'onarildi'
                        ? 'Hangi depoya eklensin?'
                        : 'Yeni cihaz hangi depoya girsin?'),
                items: depoDropdownOgeleri(depolar),
                onChanged: (v) => setState(() => hedef = v),
              ),
              if (sonuc == 'degistirildi')
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Eski cihaz firmaya teslim edilmiş sayılır ve stoktan düşer. '
                    'Yeni cihaz aynı model ve alım / garanti bilgileriyle girer '
                    '(cihaz kartından değiştirilebilir).',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ),
            ],
            if (sonuc == 'onarilamadi') ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    avatar: const Icon(Icons.recycling, size: 18),
                    label: const Text('Hurdaya ayır'),
                    selected: hurda,
                    onSelected: (_) => setState(() => hurda = true),
                  ),
                  ChoiceChip(
                    avatar: const Icon(Icons.sync_problem, size: 18),
                    label: const Text('Değişim için depoda beklet'),
                    selected: !hurda,
                    onSelected: (_) => setState(() => hurda = false),
                  ),
                ],
              ),
              if (!hurda)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Arızalı olarak kalır, tekrar gönderilebilir.',
                      style: Theme.of(ctx).textTheme.bodySmall),
                ),
            ],
            TextField(
              controller: aciklamaCtrl,
              decoration: const InputDecoration(
                labelText: 'Açıklama (opsiyonel)',
                hintText: 'Örn: anakart değişti, servis raporu no',
              ),
            ),
            _hataMetni(ctx, hata),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
            onPressed: () async {
              if (sonuc == null) {
                setState(() => hata = 'Sonucu seçin');
                return;
              }
              if (gonderim != null && donus.isBefore(gonderim)) {
                setState(() => hata = 'Dönüş, gönderimden önce olamaz');
                return;
              }
              if (sonuc == 'degistirildi' &&
                  yeniSeriCtrl.text.trim().isEmpty) {
                setState(() => hata = 'Yeni cihazın seri numarasını okutun');
                return;
              }
              if (sonuc == 'degistirildi') {
                // Yeni seri no sistemde kayıtlıysa kaydetmeden önce uyar.
                final yeni = yeniSeriCtrl.text.trim().toUpperCase();
                if (yeni == c.seriNo) {
                  setState(() => hata = 'Yeni seri no eskisiyle aynı olamaz');
                  return;
                }
                final kayitli = await ref
                    .read(appDatabaseProvider)
                    .seriNoIleCihazBilgi(yeni);
                if (!ctx.mounted) return;
                if (kayitli != null &&
                    (kayitli.cihaz.durum == CihazDurumu.depoda ||
                        kayitli.cihaz.urunId != c.urunId)) {
                  setState(() => hata = kayitli.cihaz.urunId != c.urunId
                      ? '$yeni başka bir modele kayıtlı (${kayitli.urunAdi})'
                      : '$yeni zaten depoda kayıtlı');
                  return;
                }
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Kaydet'),
          ),
        ],
      );
      },
    ),
  );
  await taslak.kapat();
  if (onay != true || !context.mounted) return;

  final mesaj = switch (sonuc) {
    'onarildi' => 'Onarıldı, depoya eklendi',
    'degistirildi' => 'Yeni cihaz depoya eklendi',
    _ => hurda ? 'Hurdaya ayrıldı' : 'Değişim için bekletiliyor',
  };
  await _calistir(
    context,
    () => ref.read(appDatabaseProvider).servisSonucu(
          cihazId: c.id,
          sonuc: sonuc!,
          donusTarihi: donus,
          aciklama: aciklamaCtrl.text,
          depoId: hedef,
          yeniSeriNo: yeniSeriCtrl.text,
          hurda: hurda,
          kullaniciId: _kullanici(ref),
        ),
    mesaj,
  );
}

// ---------------------------------------------------------------------
// Hurdaya ayır
// ---------------------------------------------------------------------

/// true: hurdaya ayrıldı.
Future<bool> hurdayaAyirAkisi(
    BuildContext context, WidgetRef ref, CihazBilgi b) async {
  final taslak = await PencereTaslagi.ac('hurda', b.cihaz.id,
      baslik: 'Hurdaya ayır · SN ${b.cihaz.seriNo}');
  if (!context.mounted) {
    taslak.birak();
    return false;
  }
  final ilkSebep = b.cihaz.arizali ? 'Onarılamaz arıza' : null;
  String? sebep = taslak.geriYuklendi ? taslak.deger<String>('sebep') : ilkSebep;
  String? hata;
  final notCtrl = TextEditingController(text: taslak.deger<String>('not'));
  void taslakYaz() => taslak.yaz({'sebep': sebep, 'not': notCtrl.text},
      ozet: sebep ?? '',
      bos: sebep == ilkSebep && notCtrl.text.trim().isEmpty);
  notCtrl.addListener(taslakYaz);
  final onay = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        taslakYaz();
        return AlertDialog(
        scrollable: true,
        icon: Icon(Icons.recycling, color: Colors.brown.shade600, size: 32),
        title: const Text('Hurdaya ayır'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (taslak.geriYuklendi) const GeriYuklendiNotu(),
            Text('${b.urunAdi} · SN: ${b.cihaz.seriNo}\n'
                '${b.depoAdi ?? '-'} stoğundan düşülecek. Kayıt ve geçmişi '
                'silinmez; raporlarda "Hurda" olarak görünür.'),
            const SizedBox(height: 12),
            Text('Hurda nedeni', style: Theme.of(ctx).textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final s in hurdaSebepleri)
                  ChoiceChip(
                    label: Text(s),
                    selected: sebep == s,
                    onSelected: (sec) => setState(() {
                      sebep = sec ? s : null;
                      hata = null;
                    }),
                  ),
              ],
            ),
            TextField(
              controller: notCtrl,
              decoration: InputDecoration(
                labelText: sebep == 'Diğer'
                    ? 'Açıklama (zorunlu)'
                    : 'Açıklama (opsiyonel)',
                hintText: 'Örn: hurda tutanağı no',
              ),
            ),
            _hataMetni(ctx, hata),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.brown.shade600),
            onPressed: () {
              if (sebep == null) {
                setState(() => hata = 'Hurda nedenini seçin');
                return;
              }
              if (sebep == 'Diğer' && notCtrl.text.trim().isEmpty) {
                setState(() => hata = '"Diğer" için açıklama yazın');
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Hurdaya ayır'),
          ),
        ],
      );
      },
    ),
  );
  await taslak.kapat();
  if (onay != true || !context.mounted) return false;
  return _calistir(
    context,
    () => ref.read(appDatabaseProvider).hurdayaAyir(
          cihazId: b.cihaz.id,
          sebep: sebep!,
          not_: notCtrl.text,
          kullaniciId: _kullanici(ref),
        ),
    'Hurdaya ayrıldı',
  );
}

// ---------------------------------------------------------------------
// Cihaz kartındaki servis bölümü
// ---------------------------------------------------------------------

/// Arızalı / serviste / hurda cihaz için durum, açık servis dosyası ve
/// yapılabilecek işlemler; ayrıca geçmiş servis dosyalarının özeti.
class ServisKarti extends ConsumerWidget {
  const ServisKarti({super.key, required this.bilgi});
  final CihazBilgi bilgi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = bilgi.cihaz;
    final kayitlar =
        ref.watch(cihazServisKayitlariProvider(c.id)).valueOrNull ?? const [];
    final durum = c.servisDurumu;
    if (durum == null && kayitlar.isEmpty) return const SizedBox.shrink();
    final acik = kayitlar.where((k) => k.acik).firstOrNull;
    final gecmis = kayitlar.where((k) => !k.acik).toList();
    final tema = Theme.of(context);

    Widget satir(String etiket, String deger, {Color? renk}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                  width: 110,
                  child: Text(etiket,
                      style: TextStyle(color: Colors.grey.shade700))),
              Expanded(
                  child: Text(deger,
                      style: TextStyle(
                          color: renk, fontWeight: FontWeight.w500))),
            ],
          ),
        );

    return Card(
      margin: const EdgeInsets.only(top: 12),
      shape: durum != null && durum.arizali
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: servisRengi(durum), width: 1.5))
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(durum == null ? Icons.history : servisIkonu(durum),
                    color: durum == null ? null : servisRengi(durum)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    durum == null ? 'Servis geçmişi' : durum.etiket,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: durum == null ? null : servisRengi(durum)),
                  ),
                ),
              ],
            ),
            if (acik != null) ...[
              const SizedBox(height: 8),
              satir('Arıza kaydı', _tarihSaat.format(acik.acilisTarihi)),
              satir('Karar', servisKararAdlari[acik.karar] ?? acik.karar),
              if (acik.arizaAciklama != null)
                satir('Arıza', acik.arizaAciklama!),
              if (acik.onarimYeri != null)
                satir('Onarım yeri',
                    onarimYeriAdlari[acik.onarimYeri] ?? acik.onarimYeri!),
              if (acik.firma != null)
                satir(acik.onarimYeri == 'garanti' ? 'Firma' : 'Onaran',
                    acik.firma!),
              if (acik.gonderimTarihi != null)
                satir('Gönderim', _tarihSaat.format(acik.gonderimTarihi!)),
              if (acik.onarimSuresi != null)
                satir('Geçen süre', sureMetni(acik.onarimSuresi!),
                    renk: Colors.indigo),
            ],
            if (durum != null && durum.arizali) ...[
              const SizedBox(height: 4),
              Text(
                'Bu cihaz servis işlemi bitene kadar transfer edilemez, '
                'araca yüklenemez ve montajda kullanılamaz.',
                style: tema.textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!durum.serviste)
                    FilledButton.icon(
                      onPressed: () => servisGonderAkisi(context, ref, bilgi),
                      icon: const Icon(Icons.send_outlined),
                      label: Text(durum == ServisDurumu.degisimGerekli
                          ? 'Değişime gönder'
                          : 'Onarıma gönder'),
                    ),
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        servisSonucuAkisi(context, ref, bilgi, acik),
                    icon: const Icon(Icons.assignment_turned_in_outlined),
                    label: Text(durum.serviste
                        ? 'Servisten döndü'
                        : 'Sonucu gir'),
                  ),
                  if (durum != ServisDurumu.garantide)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.brown.shade600),
                      onPressed: () => hurdayaAyirAkisi(context, ref, bilgi),
                      icon: const Icon(Icons.recycling),
                      label: const Text('Hurdaya ayır'),
                    ),
                ],
              ),
            ],
            if (gecmis.isNotEmpty) ...[
              const Divider(height: 20),
              Text('Önceki servis dosyaları (${gecmis.length})',
                  style: tema.textTheme.labelLarge),
              for (final k in gecmis)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    [
                      _tarihSaat.format(k.acilisTarihi),
                      servisKararAdlari[k.karar] ?? k.karar,
                      if (k.onarimYeri != null)
                        onarimYeriAdlari[k.onarimYeri] ?? k.onarimYeri!,
                      if (k.firma != null) k.firma!,
                      if (k.onarimSuresi != null && k.donusTarihi != null)
                        'Süre: ${sureMetni(k.onarimSuresi!)}',
                      if (k.sonuc != null) servisSonucAdlari[k.sonuc] ?? k.sonuc!,
                      if (k.yeniSeriNo != null) 'Yeni SN: ${k.yeniSeriNo}',
                      if (k.kapanis != null)
                        servisKapanisAdlari[k.kapanis] ?? k.kapanis!,
                    ].join(' · '),
                    style: tema.textTheme.bodySmall,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
