import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../database/models.dart';
import '../providers/app_providers.dart';
import '../services/hesap_servisi.dart';
import '../services/supabase_service.dart';
import '../widgets/buyuk_harf.dart';
import 'yonetim/hesap_islemleri_screen.dart';
import 'yonetim/roller_screen.dart';

/// Ayarlar → Kullanıcılar.
///
/// Herkes listeyi görür (ad, rol, unvan, son giriş). 1.36.0: kullanıcı
/// yönetimi yetkisi olan (Yönetici) kullanıcı ekler, rolünü / unvanını /
/// adını düzenler, şifresini sıfırlar (6 haneli geçici şifre, 15 dk), pasif
/// ya da aktif yapar. Kullanıcı silinmez (hareket geçmişi korunur).
class KullanicilarScreen extends ConsumerStatefulWidget {
  const KullanicilarScreen({super.key});

  @override
  ConsumerState<KullanicilarScreen> createState() => _KullanicilarScreenState();
}

/// Son başarılı giriş: tarih, platform, sürüm.
typedef _SonGiris = (DateTime, String, String);

class _KullanicilarScreenState extends ConsumerState<KullanicilarScreen> {
  static final _tarih = DateFormat('dd.MM.yyyy HH:mm');

  Map<String, _SonGiris>? _sonGirisler; // kullanıcı id ya da e-posta -> son
  String? _girisHatasi;

  @override
  void initState() {
    super.initState();
    _girisleriYukle();
  }

  Future<void> _girisleriYukle() async {
    setState(() => _girisHatasi = null);
    try {
      final r = await SupabaseService.client
          .from('giris_kayitlari')
          .select('kullanici_id, email, tarih, platform, surum')
          .eq('basarili', true)
          .order('tarih', ascending: false)
          .limit(3000);
      final m = <String, _SonGiris>{};
      for (final k in List<Map<String, dynamic>>.from(r)) {
        final t = DateTime.tryParse('${k['tarih']}')?.toLocal();
        if (t == null) continue;
        final g = (t, '${k['platform'] ?? '-'}', '${k['surum'] ?? '-'}');
        // Yeniden eskiye sıralı: ilk görülen en son giriştir.
        final id = k['kullanici_id'] as String?;
        if (id != null) m.putIfAbsent(id, () => g);
        final e = (k['email'] as String?)?.toLowerCase();
        if (e != null) m.putIfAbsent(e, () => g);
      }
      if (mounted) setState(() => _sonGirisler = m);
    } catch (_) {
      if (mounted) {
        setState(() => _girisHatasi =
            'Son giriş bilgisi için internet gerekli (aşağı çekip yenileyin)');
      }
    }
  }

  Future<void> _yenile() async {
    await Future.wait([
      _girisleriYukle(),
      ref.read(syncServiceProvider).syncNow(tablolar: {'kullanicilar'}),
    ]);
  }

  void _mesaj(String m, {bool hata = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m),
        backgroundColor: hata ? Colors.red.shade700 : null));
  }

  /// Hesap işleminden sonra listeyi sunucudan tazeler.
  void _tazele() => ref.read(syncServiceProvider).syncNow(tablolar: {'kullanicilar'});

  // ---------------------------------------------------------------
  // Kendi görünen adı (herkes)
  // ---------------------------------------------------------------
  Future<void> _adDegistir(Kullanici k) async {
    final yeni = await _metinSor('Görünen ad', k.ad, k.email,
        yardim: 'Hareket geçmişinde "kim yaptı" olarak görünür');
    if (yeni == null || yeni.isEmpty || yeni == k.ad || !mounted) return;
    try {
      await ref.read(appDatabaseProvider).kullaniciAdiDegistir(k.id, yeni);
      _mesaj('Ad değiştirildi: $yeni');
    } catch (e) {
      _mesaj(e is StateError ? e.message : '$e', hata: true);
    }
  }

  Future<String?> _metinSor(String baslik, String deger, String ust,
      {String? yardim}) async {
    final ctrl = TextEditingController(text: deger);
    final yeni = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(baslik),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ust, style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: metinBuyuk,
              decoration: InputDecoration(labelText: 'Ad soyad', helperText: yardim),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Kaydet')),
        ],
      ),
    );
    ctrl.dispose();
    return yeni;
  }

  // ---------------------------------------------------------------
  // Yönetici işlemleri
  // ---------------------------------------------------------------
  Future<void> _ekle() async {
    final sonuc = await showDialog<_KullaniciFormu>(
      context: context,
      builder: (_) => const _KullaniciDialog(),
    );
    if (sonuc == null || !mounted) return;
    try {
      final g = await _bekleyerek(() => HesapServisi.ekle(
            email: sonuc.email,
            ad: sonuc.ad,
            rol: sonuc.rol.name,
            unvan: sonuc.unvan,
          ));
      _tazele();
      if (mounted) await geciciSifreGoster(context, g, '${sonuc.ad} eklendi');
    } on HesapHatasi catch (e) {
      _mesaj(e.mesaj, hata: true);
    }
  }

  Future<T> _bekleyerek<T>(Future<T> Function() is_) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      return await is_();
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _yonet(Kullanici k, {required bool benim}) async {
    final secim = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(k.ad, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${k.email}\n${k.rol.etiket}'
                  '${k.unvan == null ? '' : ' · ${k.unvan}'} · ${k.durumMetni}'),
              isThreeLine: true,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Bilgileri düzenle'),
              subtitle: const Text('Ad, unvan, rol'),
              onTap: () => Navigator.pop(ctx, 'duzenle'),
            ),
            if (k.aktif)
              ListTile(
                leading: const Icon(Icons.password),
                title: const Text('Şifre sıfırla'),
                subtitle: const Text('15 dakika geçerli 6 haneli geçici şifre'),
                onTap: () => Navigator.pop(ctx, 'sifirla'),
              ),
            if (!benim)
              ListTile(
                leading: Icon(k.aktif ? Icons.block : Icons.check_circle_outline,
                    color: k.aktif ? Colors.red.shade700 : Colors.green.shade700),
                title: Text(k.aktif ? 'Pasif yap' : 'Aktif yap'),
                subtitle: Text(k.aktif
                    ? 'Giriş yapamaz; açık oturumları kapanır. Kayıtları silinmez.'
                    : 'Yeniden giriş yapabilir'),
                onTap: () => Navigator.pop(ctx, 'durum'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (secim == null || !mounted) return;
    try {
      if (secim == 'duzenle') {
        final f = await showDialog<_KullaniciFormu>(
          context: context,
          builder: (_) => _KullaniciDialog(mevcut: k, benim: benim),
        );
        if (f == null) return;
        await _bekleyerek(() => HesapServisi.guncelle(
              k.id,
              ad: f.ad == k.ad ? null : f.ad,
              unvan: f.unvan == (k.unvan ?? '') ? null : f.unvan,
              rol: f.rol == k.rol ? null : f.rol.name,
            ));
        _tazele();
        _mesaj('Kaydedildi');
      } else if (secim == 'sifirla') {
        final ok = await _onayla(
          'Şifre sıfırlansın mı?',
          '${k.ad} için 15 dakika geçerli geçici şifre oluşturulur. '
              'Kişi bu şifreyle girince kendi şifresini belirler. '
              'Eski şifresi artık çalışmaz.',
          'Sıfırla',
        );
        if (!ok) return;
        final g = await _bekleyerek(() => HesapServisi.sifirla(k.id));
        _tazele();
        if (mounted) await geciciSifreGoster(context, g, k.ad);
      } else if (secim == 'durum') {
        final ok = await _onayla(
          k.aktif ? '${k.ad} pasif yapılsın mı?' : '${k.ad} aktif yapılsın mı?',
          k.aktif
              ? 'Giriş yapamaz, açık oturumları kapanır. Yaptığı tüm '
                  'kayıtlar ve hareketler olduğu gibi kalır.'
              : 'Yeniden giriş yapabilir.',
          k.aktif ? 'Pasif yap' : 'Aktif yap',
        );
        if (!ok) return;
        await _bekleyerek(() => HesapServisi.durum(k.id, aktif: !k.aktif));
        _tazele();
        _mesaj(k.aktif ? '${k.ad} pasif yapıldı' : '${k.ad} aktif yapıldı');
      }
    } on HesapHatasi catch (e) {
      _mesaj(e.mesaj, hata: true);
    }
  }

  Future<bool> _onayla(String baslik, String metin, String dugme) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(baslik),
        content: Text(metin),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(dugme)),
        ],
      ),
    );
    return r == true;
  }

  void _ac(Widget ekran) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ekran));

  @override
  Widget build(BuildContext context) {
    final yetki = ref.watch(yetkilerimProvider);
    final yonetici = yetki.yonetici && !yetki.eskiDuzen;
    final benimId = SupabaseService.kullanici?.id;
    final liste = ref.watch(kullanicilarProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kullanıcılar'),
        actions: [
          if (yonetici)
            PopupMenuButton<String>(
              onSelected: (s) {
                if (s == 'roller') {
                  _ac(const RollerScreen());
                } else {
                  _ac(HesapIslemleriScreen(yalnizTalepler: s == 'talepler'));
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'roller', child: Text('Roller ve yetkiler')),
                PopupMenuItem(value: 'talepler', child: Text('Şifre talepleri')),
                PopupMenuItem(value: 'islemler', child: Text('Hesap işlemleri kaydı')),
              ],
            ),
        ],
      ),
      floatingActionButton: yonetici
          ? FloatingActionButton.extended(
              onPressed: _ekle,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Kullanıcı ekle'),
            )
          : null,
      body: liste.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (l) {
          final aktifler = [for (final k in l) if (k.aktif) k];
          final pasifler = [for (final k in l) if (!k.aktif) k];
          return RefreshIndicator(
            onRefresh: _yenile,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    yonetici
                        ? '${aktifler.length} aktif kullanıcı. Kişiye dokunarak '
                            'düzenleyin, şifresini sıfırlayın ya da pasif yapın.'
                        : yetki.eskiDuzen
                            ? '${l.length} kullanıcı · en az bir kez giriş yapmış '
                                'olanlar. Ada dokunarak görünen adı düzeltebilirsiniz.'
                            : '${aktifler.length} aktif kullanıcı. Kendi adınıza '
                                'dokunarak görünen adınızı düzeltebilirsiniz.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (_girisHatasi != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: Text(_girisHatasi!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                for (final k in aktifler)
                  _satir(context, k, benim: k.id == benimId, yonetici: yonetici,
                      eskiDuzen: yetki.eskiDuzen),
                if (pasifler.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                    child: Text('PASİF (${pasifler.length})',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, letterSpacing: 0.4)),
                  ),
                  for (final k in pasifler)
                    _satir(context, k, benim: k.id == benimId, yonetici: yonetici,
                        eskiDuzen: yetki.eskiDuzen),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _satir(BuildContext context, Kullanici k,
      {required bool benim, required bool yonetici, required bool eskiDuzen}) {
    final g = _sonGirisler?[k.id] ?? _sonGirisler?[k.email.toLowerCase()];
    final sonGiris = _sonGirisler == null
        ? (_girisHatasi == null ? 'Son giriş yükleniyor…' : null)
        : g == null
            ? 'Giriş kaydı yok'
            : 'Son giriş: ${_tarih.format(g.$1)} · ${g.$2} · ${g.$3}';
    final tema = Theme.of(context);
    final rolSatiri = eskiDuzen
        ? null
        : [k.rol.etiket, if (k.unvan != null && k.unvan!.isNotEmpty) k.unvan!]
            .join(' · ');
    final bekliyor = k.sifreDegistirmeli;
    return Opacity(
      opacity: k.aktif ? 1 : 0.55,
      child: ListTile(
        leading: CircleAvatar(
          child: Text(k.ad.isEmpty ? '?' : k.ad.characters.first.toUpperCase()),
        ),
        title: Row(
          children: [
            Flexible(child: Text(benim ? '${k.ad} (siz)' : k.ad)),
            if (!k.aktif) _Rozet('Pasif', tema.colorScheme.error),
            if (k.aktif && bekliyor) _Rozet('Şifre bekliyor', Colors.orange.shade800),
          ],
        ),
        subtitle: Text([
          k.email,
          if (rolSatiri != null) rolSatiri,
          if (sonGiris != null) sonGiris,
        ].join('\n')),
        isThreeLine: true,
        trailing: yonetici
            ? const Icon(Icons.more_vert)
            : (benim || eskiDuzen)
                ? const Icon(Icons.edit_outlined, size: 20)
                : null,
        onTap: yonetici
            ? () => _yonet(k, benim: benim)
            : (benim || eskiDuzen)
                ? () => _adDegistir(k)
                : null,
      ),
    );
  }
}

class _Rozet extends StatelessWidget {
  const _Rozet(this.metin, this.renk);
  final String metin;
  final Color renk;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: renk),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(metin, style: TextStyle(fontSize: 11, color: renk)),
      );
}

class _KullaniciFormu {
  const _KullaniciFormu(this.email, this.ad, this.unvan, this.rol);
  final String email;
  final String ad;
  final String unvan;
  final KullaniciRol rol;
}

/// Kullanıcı ekleme / düzenleme formu.
class _KullaniciDialog extends StatefulWidget {
  const _KullaniciDialog({this.mevcut, this.benim = false});
  final Kullanici? mevcut;
  final bool benim;

  @override
  State<_KullaniciDialog> createState() => _KullaniciDialogState();
}

class _KullaniciDialogState extends State<_KullaniciDialog> {
  late final _email = TextEditingController(text: widget.mevcut?.email ?? '');
  late final _ad = TextEditingController(text: widget.mevcut?.ad ?? '');
  late final _unvan = TextEditingController(text: widget.mevcut?.unvan ?? '');
  late KullaniciRol _rol = widget.mevcut?.rol ?? KullaniciRol.sahaKullanicisi;
  String? _hata;

  @override
  void dispose() {
    _email.dispose();
    _ad.dispose();
    _unvan.dispose();
    super.dispose();
  }

  void _kaydet() {
    final email = _email.text.trim().toLowerCase();
    final ad = _ad.text.trim();
    if (widget.mevcut == null &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _hata = 'Geçerli bir e-posta yazın');
      return;
    }
    if (ad.isEmpty) {
      setState(() => _hata = 'Ad soyad yazın');
      return;
    }
    Navigator.pop(context, _KullaniciFormu(email, ad, _unvan.text.trim(), _rol));
  }

  @override
  Widget build(BuildContext context) {
    final yeni = widget.mevcut == null;
    return AlertDialog(
      title: Text(yeni ? 'Kullanıcı ekle' : 'Kullanıcıyı düzenle'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (yeni)
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'E-posta'),
              )
            else
              Text(widget.mevcut!.email,
                  style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            TextField(
              controller: _ad,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: metinBuyuk,
              decoration: const InputDecoration(labelText: 'Ad soyad'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _unvan,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: metinBuyuk,
              decoration: const InputDecoration(
                  labelText: 'Unvan (isteğe bağlı)',
                  helperText: 'Ör. TEKNİKER, ŞEF, MÜDÜR'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<KullaniciRol>(
              value: _rol,
              decoration: InputDecoration(
                labelText: 'Rol',
                helperText: widget.benim ? 'Kendi rolünüzü değiştirirken dikkat' : null,
              ),
              items: [
                for (final r in KullaniciRol.values)
                  DropdownMenuItem(value: r, child: Text(r.etiket)),
              ],
              onChanged: (r) => setState(() => _rol = r ?? _rol),
            ),
            if (yeni)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Kaydedince 15 dakika geçerli 6 haneli geçici şifre '
                  'gösterilir. Kişiye kendiniz iletin; ilk girişte kendi '
                  'şifresini belirler.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            if (_hata != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_hata!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: _kaydet, child: Text(yeni ? 'Ekle' : 'Kaydet')),
      ],
    );
  }
}

/// Geçici şifreyi büyük gösterir (bir kez; hiçbir yere kaydedilmez).
Future<void> geciciSifreGoster(
    BuildContext context, GeciciSifre g, String kim) {
  final saat = DateFormat('HH:mm').format(g.bitis);
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text('Geçici şifre · $kim'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(
            g.kod,
            style: const TextStyle(
                fontSize: 40, fontWeight: FontWeight.bold, letterSpacing: 8),
          ),
          const SizedBox(height: 8),
          Text('$saat saatine kadar (15 dakika) geçerli.',
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Bu şifreyi yalnızca kişinin kendisine, tanıdığınız birine '
              'iletin. Şifre bu ekran kapanınca bir daha gösterilmez; gerekirse '
              'yeniden sıfırlayın.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy),
          label: const Text('Kopyala'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: g.kod));
            ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Geçici şifre kopyalandı')));
          },
        ),
        FilledButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Tamam')),
      ],
    ),
  );
}
