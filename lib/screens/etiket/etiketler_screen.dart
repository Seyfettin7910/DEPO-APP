import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../database/app_database.dart';
import '../../providers/app_providers.dart';
import '../../services/rapor/rapor_olusturucu.dart';
import '../../widgets/etiket_secimi.dart';
import '../../widgets/kod_yardimci.dart';
import '../cihaz/cihaz_detay_screen.dart';
import '../rapor/rapor_onizleme_screen.dart';
import 'etiket_ayarlari_screen.dart';
import 'etiket_basim_screen.dart';
import 'etiket_dogrula_screen.dart';

/// Kurum etiketi işlemlerinin toplandığı ekran.
class EtiketlerScreen extends ConsumerWidget {
  const EtiketlerScreen({super.key});

  void _ac(BuildContext context, Widget ekran) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ekran));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final say =
        ref.watch(etiketSayilariProvider).value ?? const <EtiketDurumu, int>{};
    final ayar = ref.watch(etiketAyarlariProvider).value ?? const EtiketAyarlari();
    final kodlar = ref.watch(kurumKodlariProvider).value ?? const <KurumKodu>[];
    int n(EtiketDurumu d) => say[d] ?? 0;

    Widget adet(int x, Color renk) => x == 0
        ? const Icon(Icons.chevron_right)
        : Badge(
            backgroundColor: renk,
            label: Text('$x'),
            child: const Icon(Icons.chevron_right),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kurum etiketleri'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Etiket ayarları',
            onPressed: () => _ac(context, const EtiketAyarlariScreen()),
          ),
        ],
      ),
      body: ListView(
        children: [
          if (kodlar.isEmpty)
            Card(
              margin: const EdgeInsets.all(12),
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Önce kurum kodu tanımlayın'),
                subtitle: const Text(
                    'Etiket ayarlarından kurum kodu (ör. BLD-BIM) ekleyince '
                    'depoya girişte cihazlara kod üretilir.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _ac(context, const EtiketAyarlariScreen()),
              ),
            ),
          if (ayar.engelEtkin)
            Card(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              color: Colors.orange.shade50,
              child: const ListTile(
                leading: Icon(Icons.lock_outline, color: Colors.orange),
                title: Text('Engel açık'),
                subtitle: Text('Doğrulanmamış etiketli cihazlar transfer '
                    'edilemez, araca yüklenemez, montajda kullanılamaz.'),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.print_outlined),
            title: const Text('Etiket basımı'),
            subtitle: Text(bilgisayarTarayicisi
                ? 'Basım kuyruğu: ${n(EtiketDurumu.kuyrukta)} etiket'
                : 'Kuyruk: ${n(EtiketDurumu.kuyrukta)} · bilgisayardan basılır'),
            trailing: adet(n(EtiketDurumu.kuyrukta), Colors.indigo),
            onTap: () => _ac(context, const EtiketBasimScreen()),
          ),
          if (ayar.dogrulama)
            ListTile(
              leading: const Icon(Icons.verified_outlined),
              title: const Text('Etiket doğrula'),
              subtitle: Text(
                  'Yapıştırma bekleyen: ${n(EtiketDurumu.basildi)} · etiket + '
                  'cihazın seri nosu okutulur'),
              trailing: adet(n(EtiketDurumu.basildi), Colors.orange.shade800),
              onTap: () => _ac(context, const EtiketDogrulaScreen()),
            ),
          const Divider(),
          for (final d in [
            EtiketDurumu.uyusmazlik,
            if (ayar.dogrulama) EtiketDurumu.basildi,
            EtiketDurumu.kayitli,
            EtiketDurumu.kuyrukta,
            EtiketDurumu.dogrulandi,
          ])
            if (n(d) > 0 || d == EtiketDurumu.uyusmazlik)
              ListTile(
                leading: Icon(etiketDurumIkonu(d), color: etiketDurumRengi(d)),
                title: Text(d == EtiketDurumu.basildi && !ayar.dogrulama
                    ? 'Basıldı'
                    : d.etiket),
                subtitle: Text('${n(d)} cihaz'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _ac(context, EtiketListeScreen(durum: d)),
              ),
          ListTile(
            leading: const Icon(Icons.label_off_outlined),
            title: const Text('Etiketsiz cihazlar'),
            subtitle: const Text('Depoda olup kurum kodu olmayanlar · toplu kod üret'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _ac(context, const EtiketsizCihazlarScreen()),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.summarize_outlined),
            title: const Text('Etiket durumu raporu'),
            subtitle: const Text('PDF / Excel'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final rapor =
                  await RaporOlusturucu.etiketDurumu(ref.read(appDatabaseProvider));
              if (context.mounted) _ac(context, RaporOnizlemeScreen(rapor: rapor));
            },
          ),
        ],
      ),
    );
  }
}

/// Belirli durumdaki etiketler. "Kodu var, basılmadı" listesinden toplu
/// olarak basım kuyruğuna alınabilir.
class EtiketListeScreen extends ConsumerStatefulWidget {
  const EtiketListeScreen({super.key, required this.durum});
  final EtiketDurumu durum;

  @override
  ConsumerState<EtiketListeScreen> createState() => _EtiketListeScreenState();
}

class _EtiketListeScreenState extends ConsumerState<EtiketListeScreen> {
  final _secili = <String>{};
  static final _gun = DateFormat('dd.MM.yyyy');

  bool get _secimli => widget.durum == EtiketDurumu.kayitli;

  @override
  Widget build(BuildContext context) {
    final liste =
        ref.watch(etiketListesiProvider(widget.durum)).value ?? const <EtiketBilgi>[];
    _secili.removeWhere((id) => !liste.any((e) => e.id == id));
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.durum.etiket} (${liste.length})'),
        actions: [
          if (_secimli && liste.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _secili.length == liste.length
                  ? _secili.clear()
                  : _secili.addAll(liste.map((e) => e.id))),
              child: Text(_secili.length == liste.length ? 'Hiçbiri' : 'Hepsi'),
            ),
        ],
      ),
      body: liste.isEmpty
          ? const Center(child: Text('Kayıt yok'))
          : ListView.builder(
              itemCount: liste.length,
              itemBuilder: (_, i) {
                final e = liste[i];
                final alt = Text([
                  e.urunAdi,
                  e.seriNosuz ? 'seri nosuz' : 'SN ${e.seriNo}',
                  e.depoAdi ?? '-',
                  _gun.format(e.olusturma),
                ].join(' · '));
                if (_secimli) {
                  return CheckboxListTile(
                    value: _secili.contains(e.id),
                    title: Text(e.kod),
                    subtitle: alt,
                    onChanged: (v) => setState(() =>
                        v == true ? _secili.add(e.id) : _secili.remove(e.id)),
                  );
                }
                return ListTile(
                  leading: Icon(etiketDurumIkonu(e.durum),
                      color: etiketDurumRengi(e.durum)),
                  title: Text(e.kod),
                  subtitle: alt,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => CihazDetayScreen(cihazId: e.cihazId))),
                );
              },
            ),
      bottomNavigationBar: _secimli && _secili.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: () async {
                    final adet = await ref.read(appDatabaseProvider).kuyrugaAl(
                          etiketIdleri: _secili.toList(),
                          kullaniciId: ref.read(aktifKullaniciIdProvider) ??
                              'demo-kullanici',
                        );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('$adet etiket basım kuyruğuna alındı')));
                  },
                  icon: const Icon(Icons.print_outlined),
                  label: Text('Basım kuyruğuna al (${_secili.length})'),
                ),
              ),
            )
          : null,
    );
  }
}

/// Depoda olup kurum kodu olmayan cihazlar: seçilenlere toplu kod üretilir.
class EtiketsizCihazlarScreen extends ConsumerStatefulWidget {
  const EtiketsizCihazlarScreen({super.key});

  @override
  ConsumerState<EtiketsizCihazlarScreen> createState() =>
      _EtiketsizCihazlarScreenState();
}

class _EtiketsizCihazlarScreenState
    extends ConsumerState<EtiketsizCihazlarScreen> {
  final _secili = <String>{};
  bool _calisiyor = false;

  Future<void> _uret() async {
    final kodlar =
        await ref.read(appDatabaseProvider).kurumKodlari(sadeceAktif: true);
    final onceki = await EtiketTercihi.yukle(kodlar);
    if (!mounted) return;
    if (kodlar.isEmpty) {
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const EtiketAyarlariScreen()));
      return;
    }
    final t = await etiketTercihiSec(context,
        kodlar: kodlar,
        mevcut: onceki,
        kodUretmeSecenegi: false,
        baslik: '${_secili.length} cihaza kod üret');
    if (t == null || t.kurumKoduId == null || !mounted) return;
    setState(() => _calisiyor = true);
    try {
      final adet = await ref.read(appDatabaseProvider).etiketUret(
            cihazIdleri: _secili.toList(),
            kurumKoduId: t.kurumKoduId!,
            kuyruga: t.kuyruga,
            kullaniciId: ref.read(aktifKullaniciIdProvider) ?? 'demo-kullanici',
          );
      if (!mounted) return;
      setState(_secili.clear);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$adet cihaza kurum kodu üretildi'
              '${t.kuyruga ? ' · basım kuyruğuna alındı' : ''}')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is StateError ? e.message : 'Üretilemedi: $e'),
            backgroundColor: Colors.red.shade700));
      }
    } finally {
      if (mounted) setState(() => _calisiyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final liste =
        ref.watch(etiketsizCihazlarProvider).value ?? const <CihazBilgi>[];
    _secili.removeWhere((id) => !liste.any((c) => c.cihaz.id == id));
    final gruplar = <String, List<CihazBilgi>>{};
    for (final c in liste) {
      gruplar.putIfAbsent(c.depoAdi ?? '-', () => []).add(c);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('Etiketsiz cihazlar (${liste.length})'),
        actions: [
          if (liste.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _secili.length == liste.length
                  ? _secili.clear()
                  : _secili.addAll(liste.map((c) => c.cihaz.id))),
              child: Text(_secili.length == liste.length ? 'Hiçbiri' : 'Hepsi'),
            ),
        ],
      ),
      body: liste.isEmpty
          ? const Center(child: Text('Depoda etiketsiz cihaz yok'))
          : ListView(
              children: [
                for (final g in gruplar.entries) ...[
                  CheckboxListTile(
                    tristate: true,
                    value: g.value.every((c) => _secili.contains(c.cihaz.id))
                        ? true
                        : (g.value.any((c) => _secili.contains(c.cihaz.id))
                            ? null
                            : false),
                    title: Text('${g.key} (${g.value.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    onChanged: (_) => setState(() {
                      final hepsi =
                          g.value.every((c) => _secili.contains(c.cihaz.id));
                      for (final c in g.value) {
                        hepsi
                            ? _secili.remove(c.cihaz.id)
                            : _secili.add(c.cihaz.id);
                      }
                    }),
                  ),
                  for (final c in g.value)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(left: 40, right: 16),
                      value: _secili.contains(c.cihaz.id),
                      title: Text(c.cihaz.seriNo),
                      subtitle: Text(c.urunAdi),
                      onChanged: (v) => setState(() => v == true
                          ? _secili.add(c.cihaz.id)
                          : _secili.remove(c.cihaz.id)),
                    ),
                ],
              ],
            ),
      bottomNavigationBar: _secili.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _calisiyor ? null : _uret,
                  icon: const Icon(Icons.qr_code_2),
                  label: Text('Kurum kodu üret (${_secili.length})'),
                ),
              ),
            ),
    );
  }
}
