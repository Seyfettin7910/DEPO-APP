import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../database/app_database.dart' show BildirimAlici;
import '../../database/models.dart';
import '../../providers/app_providers.dart';
import '../../services/bildirim/bildirim_ayarlari.dart';
import '../../services/hesap_servisi.dart';
import '../bildirim/bildirimler_screen.dart' show bildirimIkonu, bildirimRengi;

/// 1.36.0: Kullanıcılar → Roller ve yetkiler (yalnız kullanıcı yönetimi).
///
/// Yetkiler: her rol için açılıp kapatılabilen tablo (kilitli hücreler
/// değişmez). Bildirim alıcıları: her bildirimi hangi roller / kişiler alır.
/// Denetim: sunucu yetkisiz işlemi yalnız kaydetsin mi, engellesin mi.
class RollerScreen extends ConsumerWidget {
  const RollerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final yetki = ref.watch(yetkilerimProvider);
    if (!yetki.yonetici || yetki.eskiDuzen) {
      return Scaffold(
        appBar: AppBar(title: const Text('Roller ve yetkiler')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              yetki.eskiDuzen
                  ? 'Sunucuda yetki tablosu yok. Supabase güncelleme SQL\'ini '
                      '(1.36.0) çalıştırın; tablo senkronlanınca bu ekran açılır.'
                  : 'Bu ekran için kullanıcı yönetimi yetkisi gerekir.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Roller ve yetkiler'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Yetkiler'),
            Tab(text: 'Bildirim alıcıları'),
            Tab(text: 'Denetim'),
          ]),
        ),
        body: const TabBarView(children: [
          _YetkiTablosu(),
          _BildirimAlicilari(),
          _Denetim(),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Yetki tablosu
// ---------------------------------------------------------------------
class _YetkiTablosu extends ConsumerStatefulWidget {
  const _YetkiTablosu();

  @override
  ConsumerState<_YetkiTablosu> createState() => _YetkiTablosuState();
}

class _YetkiTablosuState extends ConsumerState<_YetkiTablosu> {
  KullaniciRol _rol = KullaniciRol.depoSorumlusu;
  final _degisen = <(KullaniciRol, Yetki), bool>{};

  bool _deger(Map<String, bool> tablo, KullaniciRol rol, Yetki y) {
    final d = _degisen[(rol, y)] ??
        tablo[yetkiKimligi(rol, y)] ??
        y.varsayilan(rol);
    return kilitliDeger(rol, y, d);
  }

  Future<void> _kaydet() async {
    await ref.read(appDatabaseProvider).yetkileriKaydet(Map.of(_degisen));
    setState(_degisen.clear);
    ref.read(syncServiceProvider).syncNow(tablolar: {'yetkiler'});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Yetkiler kaydedildi. Kullanıcıların telefonuna '
              'senkronla gider.')));
    }
  }

  void _varsayilana(Map<String, bool> tablo) {
    setState(() {
      for (final y in Yetki.values) {
        if (y.kilitli(_rol)) continue;
        final v = y.varsayilan(_rol);
        if ((tablo[yetkiKimligi(_rol, y)] ?? v) != v || _degisen.containsKey((_rol, y))) {
          _degisen[(_rol, y)] = v;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tablo = ref.watch(yetkiTablosuProvider).valueOrNull ?? const {};
    final tema = Theme.of(context);
    final gruplar = <String, List<Yetki>>{};
    for (final y in Yetki.values) {
      gruplar.putIfAbsent(y.grup, () => []).add(y);
    }
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final r in KullaniciRol.values)
                  ChoiceChip(
                    label: Text(r.etiket),
                    selected: _rol == r,
                    onSelected: (_) => setState(() => _rol = r),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_rol.etiket}: yetkisi olmayan düğmeler bu rolde görünmez; '
                    'sunucu da denetler (Denetim sekmesi).',
                    style: tema.textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: () => _varsayilana(tablo),
                  child: const Text('Varsayılana dön'),
                ),
              ],
            ),
          ),
          for (final g in gruplar.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(g.key,
                  style: tema.textTheme.titleSmall
                      ?.copyWith(color: tema.colorScheme.primary)),
            ),
            for (final y in g.value)
              SwitchListTile(
                dense: true,
                title: Text(y.etiket),
                subtitle: y.kilitli(_rol)
                    ? Text(y == Yetki.hareketSilme
                        ? 'Kilitli: hareket kayıtları kimse tarafından silinemez'
                        : 'Kilitli: Yönetici rolünden kaldırılamaz')
                    : (_degisen.containsKey((_rol, y))
                        ? const Text('Değişti (kaydedilmedi)')
                        : null),
                secondary: y.kilitli(_rol)
                    ? const Icon(Icons.lock_outline, size: 20)
                    : null,
                value: _deger(tablo, _rol, y),
                onChanged: y.kilitli(_rol)
                    ? null
                    : (v) => setState(() {
                          final sunucu = tablo[yetkiKimligi(_rol, y)] ?? y.varsayilan(_rol);
                          if (v == sunucu) {
                            _degisen.remove((_rol, y));
                          } else {
                            _degisen[(_rol, y)] = v;
                          }
                        }),
              ),
          ],
        ],
      ),
      floatingActionButton: _degisen.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _kaydet,
              icon: const Icon(Icons.save_outlined),
              label: Text('Kaydet (${_degisen.length})'),
            ),
    );
  }
}

// ---------------------------------------------------------------------
// Bildirim alıcıları
// ---------------------------------------------------------------------
class _BildirimAlicilari extends ConsumerWidget {
  const _BildirimAlicilari();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merkez = ref.watch(bildirimAlicilariProvider).valueOrNull ?? const {};
    final kisiler = ref.watch(kullanicilarProvider).valueOrNull ?? const <Kullanici>[];
    final adlar = {for (final k in kisiler) k.id: k.ad};
    final tema = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            'Her bildirimi kimlerin alacağını seçin. Seçilen kişi bildirimi '
            'kendi telefonunda yalnızca kapatabilir; seçilmeyen görmez. Seçim '
            'yapılmamış bildirimde herkes kendi ayarına göre alır.',
            style: tema.textTheme.bodySmall,
          ),
        ),
        for (final t in BildirimTuru.values)
          if (t.merkezi)
            ListTile(
              leading: Icon(bildirimIkonu(t), color: bildirimRengi(t)),
              title: Text(t.etiket),
              subtitle: Text(_ozet(merkez[t.name], adlar)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _duzenle(context, ref, t, merkez[t.name], kisiler),
            ),
      ],
    );
  }

  static String _ozet(BildirimAlici? a, Map<String, String> adlar) {
    if (a == null) return 'Seçim yok: herkes kendi ayarına göre';
    final p = [
      for (final r in KullaniciRol.values)
        if (a.roller.contains(r)) r.etiket,
      for (final k in a.kisiler) adlar[k] ?? 'bilinmeyen kişi',
    ];
    return p.isEmpty ? 'Kimse almıyor' : p.join(', ');
  }

  Future<void> _duzenle(BuildContext context, WidgetRef ref, BildirimTuru t,
      BildirimAlici? mevcut, List<Kullanici> kisiler) async {
    final roller = {...?mevcut?.roller};
    final secili = {...?mevcut?.kisiler};
    final kaydet = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, yenile) => AlertDialog(
          title: Text(t.etiket),
          contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text('Roller', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                for (final r in KullaniciRol.values)
                  CheckboxListTile(
                    dense: true,
                    title: Text(r.etiket),
                    value: roller.contains(r),
                    onChanged: (v) => yenile(() => v == true ? roller.add(r) : roller.remove(r)),
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text('Ayrıca şu kişiler',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                for (final k in kisiler)
                  if (k.aktif)
                    CheckboxListTile(
                      dense: true,
                      title: Text(k.ad),
                      subtitle: Text(k.rol.etiket),
                      value: secili.contains(k.id),
                      onChanged: (v) =>
                          yenile(() => v == true ? secili.add(k.id) : secili.remove(k.id)),
                    ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Kaydet')),
          ],
        ),
      ),
    );
    if (kaydet != true) return;
    await ref.read(appDatabaseProvider).bildirimAlicisiKaydet(
        BildirimAlici(tur: t.name, roller: roller, kisiler: secili));
    ref.read(syncServiceProvider).syncNow(tablolar: {'bildirim_alicilari'});
  }
}

// ---------------------------------------------------------------------
// Denetim kipi ve ihlaller
// ---------------------------------------------------------------------
class _Denetim extends ConsumerStatefulWidget {
  const _Denetim();

  @override
  ConsumerState<_Denetim> createState() => _DenetimState();
}

class _DenetimState extends ConsumerState<_Denetim> {
  static final _tarih = DateFormat('dd.MM.yyyy HH:mm');
  List<Map<String, dynamic>>? _ihlaller;
  String? _hata;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final l = await HesapServisi.ihlaller();
      if (mounted) setState(() => _ihlaller = l);
    } catch (_) {
      if (mounted) setState(() => _hata = 'İhlal kayıtları için internet gerekir');
    }
  }

  Future<void> _kip(String k) async {
    await ref.read(appDatabaseProvider).kurumAyariYaz('yetki_denetimi', k);
    ref.read(syncServiceProvider).syncNow(tablolar: {'kurum_ayarlari'});
  }

  @override
  Widget build(BuildContext context) {
    final ayar = ref.watch(_kurumAyarlariProvider).valueOrNull ?? const {};
    final kip = switch (ayar['yetki_denetimi']) {
      'engel' => 'engel',
      'kapali' => 'kapali',
      _ => 'kayit',
    };
    final kisiler = ref.watch(kullanicilarProvider).valueOrNull ?? const <Kullanici>[];
    final adlar = {for (final k in kisiler) k.id: k.ad};
    final tema = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _yukle,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Uygulama yetkisi olmayan düğmeyi zaten göstermez. Sunucu ayrıca '
              'her kaydı denetler. Önce bir süre "Yalnız kaydet" kipinde '
              'aşağıdaki listeyi izleyin; liste boş kalıyorsa "Engelle"ye geçin.',
              style: tema.textTheme.bodySmall,
            ),
          ),
          for (final (v, b, a) in const [
            ('kayit', 'Yalnız kaydet (önerilen başlangıç)',
                'Yetkisiz işlem yapılır ama aşağıya yazılır'),
            ('engel', 'Engelle',
                'Yetkisiz işlem sunucuya hiç girmez; telefondaki kayıt geri alınır'),
            ('kapali', 'Kapalı', 'Sunucu denetlemez (önerilmez)'),
          ])
            RadioListTile<String>(
              value: v,
              groupValue: kip,
              title: Text(b),
              subtitle: Text(a),
              onChanged: (x) {
                if (x != null) _kip(x);
              },
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Yetki ihlalleri (son 300)',
                style: tema.textTheme.titleSmall),
          ),
          if (_hata != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(_hata!))
          else if (_ihlaller == null)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()))
          else if (_ihlaller!.isEmpty)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Text('İhlal yok', textAlign: TextAlign.center))
          else
            for (final r in _ihlaller!)
              ListTile(
                dense: true,
                leading: Icon(r['engellendi'] == true ? Icons.block : Icons.visibility,
                    color: r['engellendi'] == true ? Colors.red.shade700 : null),
                title: Text('${adlar[r['kullanici_id']] ?? r['kullanici_id'] ?? '-'} · '
                    '${_yetkiAdi(r['gereken'])}'),
                subtitle: Text([
                  if (DateTime.tryParse('${r['tarih']}') case final t?)
                    _tarih.format(t.toLocal()),
                  '${r['tablo']}',
                  if (r['engellendi'] == true) 'engellendi',
                ].join(' · ')),
              ),
        ],
      ),
    );
  }

  static String _yetkiAdi(Object? a) {
    final ad = '${a ?? ''}';
    final parca = [
      for (final p in ad.split('/'))
        Yetki.anahtardan(p.trim())?.etiket ?? p.trim()
    ];
    return parca.join(' / ');
  }
}

final _kurumAyarlariProvider = StreamProvider<Map<String, String>>((ref) {
  return ref.watch(appDatabaseProvider).kurumAyarlariStream();
});
