import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/app_providers.dart';
import '../../services/hesap_servisi.dart';
import '../kullanicilar_screen.dart' show geciciSifreGoster;

/// 1.36.0: Hesap işlemleri kaydı (yalnız kullanıcı yönetimi yetkisi).
///
/// [yalnizTalepler]: "Şifremi unuttum" talepleri; her talebin yanında
/// "Şifre sıfırla" düğmesi. Talepten sonra sıfırlama yapıldıysa "Sıfırlandı"
/// yazar. Kayıtlar sunucudadır; kimse değiştiremez, silemez.
class HesapIslemleriScreen extends ConsumerStatefulWidget {
  const HesapIslemleriScreen({super.key, this.yalnizTalepler = false});
  final bool yalnizTalepler;

  @override
  ConsumerState<HesapIslemleriScreen> createState() =>
      _HesapIslemleriScreenState();
}

class _HesapIslemleriScreenState extends ConsumerState<HesapIslemleriScreen> {
  static final _tarih = DateFormat('dd.MM.yyyy HH:mm');
  List<Map<String, dynamic>>? _liste;
  String? _hata;
  String? _filtre; // tür

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    setState(() => _hata = null);
    try {
      final gun = widget.yalnizTalepler ? 30 : 180;
      final l = await HesapServisi.islemler(
        tur: widget.yalnizTalepler ? null : _filtre,
        baslangic: DateTime.now().subtract(Duration(days: gun)),
        limit: 1000,
      );
      if (mounted) setState(() => _liste = l);
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Kayıtlar okunamadı. İnternet gerekir '
            '(ya da sunucuda 1.36.0 güncellemesi yok).');
      }
    }
  }

  Future<void> _sifirla(String id, String kim) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Şifre sıfırlansın mı?'),
        content: Text('$kim için 15 dakika geçerli 6 haneli geçici şifre '
            'oluşturulur. Talebin gerçekten bu kişiden geldiğinden emin olun '
            '(telefonla arayın ya da yüz yüze teyit edin).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sıfırla')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final g = await HesapServisi.sifirla(id);
      ref.read(syncServiceProvider).syncNow(tablolar: {'kullanicilar'});
      if (mounted) await geciciSifreGoster(context, g, kim);
      await _yukle();
    } on HesapHatasi catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.mesaj), backgroundColor: Colors.red.shade700));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final yetki = ref.watch(yetkilerimProvider);
    final tema = Theme.of(context);
    final baslik = widget.yalnizTalepler ? 'Şifre talepleri' : 'Hesap işlemleri kaydı';
    if (!yetki.yonetici) {
      return Scaffold(
        appBar: AppBar(title: Text(baslik)),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Bu ekran için kullanıcı yönetimi yetkisi gerekir.',
                textAlign: TextAlign.center),
          ),
        ),
      );
    }
    final l = _liste;
    final gosterilen = l == null
        ? null
        : widget.yalnizTalepler
            ? [for (final r in l) if (r['tur'] == 'sifre_talebi') r]
            : l;
    return Scaffold(
      appBar: AppBar(
        title: Text(baslik),
        actions: [
          IconButton(
              tooltip: 'Yenile',
              onPressed: _yukle,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _hata != null
          ? Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_hata!, textAlign: TextAlign.center)))
          : gosterilen == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _yukle,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      if (!widget.yalnizTalepler)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                          child: Row(children: [
                            for (final t in const [
                              null,
                              'sifre_talebi',
                              'sifre_sifirlama',
                              'sifre_degisti',
                              'kullanici_ekleme',
                              'rol_degisti',
                              'pasif',
                              'aktif',
                              'gecici_suresi_doldu',
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(t == null ? 'Tümü' : hesapIslemAdi(t)),
                                  selected: _filtre == t,
                                  onSelected: (_) {
                                    setState(() {
                                      _filtre = t;
                                      _liste = null;
                                    });
                                    _yukle();
                                  },
                                ),
                              ),
                          ]),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text(
                          widget.yalnizTalepler
                              ? 'Son 30 gün · ${gosterilen.length} talep. Şifreyi '
                                  'sıfırlamadan önce kişiyi arayıp teyit edin.'
                              : 'Son 180 gün · ${gosterilen.length} kayıt. Şifre '
                                  've geçici kodlar hiçbir yere yazılmaz.',
                          style: tema.textTheme.bodySmall,
                        ),
                      ),
                      if (gosterilen.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('Kayıt yok', textAlign: TextAlign.center),
                        ),
                      for (final r in gosterilen) _satir(r, l!),
                    ],
                  ),
                ),
    );
  }

  /// Talepten sonra aynı kişi için sıfırlama yapılmış mı?
  bool _islendi(Map<String, dynamic> talep, List<Map<String, dynamic>> l) {
    final id = talep['hedef_id'];
    final t = DateTime.tryParse('${talep['tarih']}');
    if (id == null || t == null) return false;
    return l.any((r) =>
        r['tur'] == 'sifre_sifirlama' &&
        r['hedef_id'] == id &&
        (DateTime.tryParse('${r['tarih']}')?.isAfter(t) ?? false));
  }

  Widget _satir(Map<String, dynamic> r, List<Map<String, dynamic>> l) {
    final tarih = DateTime.tryParse('${r['tarih']}')?.toLocal();
    final hedef = (r['hedef_ad'] as String?) ?? (r['hedef_email'] as String?) ?? '-';
    final yapan = r['yapan_email'] as String?;
    final talep = r['tur'] == 'sifre_talebi';
    final islendi = talep && _islendi(r, l);
    final hedefId = r['hedef_id'] as String?;
    return ListTile(
      leading: Icon(_ikon('${r['tur']}')),
      title: Text('${hesapIslemAdi(r['tur'])} · $hedef'),
      subtitle: Text([
        [
          if (tarih != null) _tarih.format(tarih),
          if (r['hedef_email'] != null && r['hedef_ad'] != null) '${r['hedef_email']}',
        ].join(' · '),
        if (yapan != null && yapan != r['hedef_email']) 'Yapan: $yapan',
        if (r['aciklama'] != null) '${r['aciklama']}',
        if (r['ip'] != null) 'IP: ${r['ip']}',
      ].join('\n')),
      isThreeLine: true,
      trailing: !talep
          ? null
          : islendi
              ? const Chip(label: Text('Sıfırlandı'))
              : hedefId == null
                  ? null
                  : FilledButton.tonal(
                      onPressed: () => _sifirla(hedefId, hedef),
                      child: const Text('Şifre sıfırla'),
                    ),
    );
  }

  static IconData _ikon(String tur) => switch (tur) {
        'sifre_talebi' => Icons.lock_reset,
        'sifre_sifirlama' => Icons.password,
        'gecici_giris' => Icons.login,
        'sifre_degisti' => Icons.check_circle_outline,
        'gecici_suresi_doldu' => Icons.timer_off_outlined,
        'kullanici_ekleme' => Icons.person_add_alt,
        'rol_degisti' => Icons.badge_outlined,
        'pasif' => Icons.block,
        'aktif' => Icons.how_to_reg,
        'ad_degisti' => Icons.drive_file_rename_outline,
        _ => Icons.history,
      };
}
