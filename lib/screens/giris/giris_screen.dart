import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/guncelleme_servisi.dart';
import '../../services/oturum_kilidi.dart';
import '../../services/supabase_service.dart';
import '../../services/tarayici.dart';
import '../../services/giris_kaydi_servisi.dart';

/// E-posta + şifre ile giriş. Kullanıcılar Supabase panelinden
/// (Authentication > Users) eklenir; uygulamadan kayıt olunamaz.
class GirisScreen extends StatefulWidget {
  const GirisScreen({super.key});

  @override
  State<GirisScreen> createState() => _GirisScreenState();
}

class _GirisScreenState extends State<GirisScreen> {
  final _emailCtrl = TextEditingController();
  final _sifreCtrl = TextEditingController();
  bool _yukleniyor = false;
  bool _gizli = true;
  String? _hata;

  static const _sonEmailAnahtari = 'son_giris_email';

  @override
  void initState() {
    super.initState();
    _sonEmailiYukle();
  }

  /// Son başarılı girişteki e-postayı kutuya yazar; böylece yalnızca şifre
  /// girilir (şifreyi de telefonun/tarayıcının şifre kaydedicisi doldurabilir).
  Future<void> _sonEmailiYukle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(_sonEmailAnahtari);
      if (email != null && mounted && _emailCtrl.text.isEmpty) {
        setState(() => _emailCtrl.text = email);
      }
    } catch (_) {
      // Hatırlanamazsa sorun değil, kullanıcı yazar.
    }
  }

  Future<void> _emailiHatirla(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sonEmailAnahtari, email);
    } catch (_) {}
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _sifreCtrl.dispose();
    super.dispose();
  }

  Future<void> _giris() async {
    final email = _emailCtrl.text.trim();
    final sifre = _sifreCtrl.text;
    if (email.isEmpty || sifre.isEmpty) {
      setState(() => _hata = 'E-posta ve şifre girin');
      return;
    }
    setState(() {
      _yukleniyor = true;
      _hata = null;
    });
    try {
      await SupabaseService.girisYap(email, sifre);
      unawaited(GirisKaydiServisi.basarili());
      await OturumKilidi.instance.kilidiAc();
      await _emailiHatirla(email);
      // Telefona/tarayıcıya "şifreyi kaydet" teklifini göster.
      TextInput.finishAutofillContext();
      // Başarılı girişte AuthGate oturum olayını yakalayıp ana ekrana geçer.
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      if (m.contains('invalid login')) {
        unawaited(GirisKaydiServisi.hatali(email));
      }
      setState(() => _hata = m.contains('invalid login')
          ? 'E-posta veya şifre hatalı'
          : m.contains('not confirmed')
              ? 'E-posta onaylanmamış. Yöneticiye başvurun.'
              : 'Giriş yapılamadı: ${e.message}');
    } catch (_) {
      setState(() => _hata =
          'Sunucuya ulaşılamadı. Giriş için internet bağlantısı gerekir.');
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset('assets/logo.png',
                          width: 88, height: 88, filterQuality: FilterQuality.medium),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('DEPO OTOMASYON SİSTEMİ',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5)),
                  const SizedBox(height: 24),
                  if (OturumKilidi.instance.sonSebep != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_clock_outlined),
                          const SizedBox(width: 8),
                          Expanded(child: Text(OturumKilidi.instance.sonSebep!)),
                        ],
                      ),
                    ),
                  AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                              labelText: 'E-posta', border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _sifreCtrl,
                          obscureText: _gizli,
                          autofillHints: const [AutofillHints.password],
                          onSubmitted: (_) => _giris(),
                          decoration: InputDecoration(
                            labelText: 'Şifre',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                  _gizli ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => _gizli = !_gizli),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_hata != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_hata!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _yukleniyor ? null : _giris,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(_yukleniyor ? 'Giriş yapılıyor...' : 'Giriş yap'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Hesap bilgilerini yöneticinizden alın.\n'
                    'Güvenlik için 5 dakika işlem yapılmazsa oturum kapanır.'
                    '${GuncellemeServisi.mevcutSurum.isEmpty ? '' : '\nSürüm ${GuncellemeServisi.mevcutSurum}'}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                  // Web'den (iPhone hariç) Android uygulamasını indirme linki.
                  if (kIsWeb && !iosTarayici()) ...[
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton.icon(
                        icon: const Icon(Icons.android, color: Color(0xFF1E7B3A)),
                        label: const Text('Android uygulamasını indir (APK)'),
                        onPressed: () => launchUrl(
                            Uri.parse(GuncellemeServisi.apkLinki),
                            mode: LaunchMode.externalApplication),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Text(
                    'Developed by Seyfettin AYDIN',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 0.5,
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
