import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/app_providers.dart';
import '../services/supabase_service.dart';
import '../services/urun_adi.dart';
import '../widgets/buyuk_harf.dart';

/// 1.30.3: Ayarlar → Kullanıcılar (yalnız görüntüleme; herkes görür).
/// Sunucuda kayıtlı, en az bir kez giriş yapmış kullanıcılar: ad, e-posta,
/// son giriş (tarih, cihaz / tarayıcı) ve uygulama sürümü. Görünen ad
/// (hareket geçmişindeki "kim yaptı") düzeltilebilir ve senkronlanır.
/// Rol, kullanıcı ekleme ve şifre sıfırlama sonraki sürümde (Final).
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

  Future<void> _adDegistir(String id, String ad, String email) async {
    final ctrl = TextEditingController(text: ad);
    final yeni = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Görünen ad'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(email, style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: metinBuyuk,
              decoration: const InputDecoration(
                  labelText: 'Ad soyad',
                  helperText: 'Hareket geçmişinde "kim yaptı" olarak görünür'),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Kaydet')),
        ],
      ),
    );
    ctrl.dispose();
    if (yeni == null || yeni.isEmpty || yeni == ad || !mounted) return;
    try {
      await ref.read(appDatabaseProvider).kullaniciAdiDegistir(id, yeni);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ad değiştirildi: $yeni')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is StateError ? e.message : '$e'),
            backgroundColor: Colors.red.shade700));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(appDatabaseProvider);
    final benimId = SupabaseService.kullanici?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Kullanıcılar')),
      body: StreamBuilder<List<(String, String, String)>>(
        stream: db.kullaniciListesiStream(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final liste = [...snap.data!]
            ..sort((a, b) => trKarsilastir(a.$2, b.$2));
          return RefreshIndicator(
            onRefresh: _girisleriYukle,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    '${liste.length} kullanıcı · en az bir kez giriş yapmış '
                    'olanlar. Ada dokunarak görünen adı düzeltebilirsiniz.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (_girisHatasi != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: Text(_girisHatasi!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                for (final (id, ad, email) in liste)
                  _satir(context, id, ad, email, benim: id == benimId),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _satir(BuildContext context, String id, String ad, String email,
      {required bool benim}) {
    final g = _sonGirisler?[id] ?? _sonGirisler?[email.toLowerCase()];
    final sonGiris = _sonGirisler == null
        ? (_girisHatasi == null ? 'Son giriş yükleniyor…' : null)
        : g == null
            ? 'Giriş kaydı yok'
            : 'Son giriş: ${_tarih.format(g.$1)}\n${g.$2} · sürüm ${g.$3}';
    return ListTile(
      leading: CircleAvatar(
        child: Text(ad.isEmpty ? '?' : ad.characters.first.toUpperCase()),
      ),
      title: Text(benim ? '$ad (siz)' : ad),
      subtitle: Text([email, if (sonGiris != null) sonGiris].join('\n')),
      isThreeLine: true,
      trailing: const Icon(Icons.edit_outlined, size: 20),
      onTap: () => _adDegistir(id, ad, email),
    );
  }
}
