import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/supabase_service.dart';

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
      await _emailiHatirla(email);
      // Telefona/tarayıcıya "şifreyi kaydet" teklifini göster.
      TextInput.finishAutofillContext();
      // Başarılı girişte AuthGate oturum olayını yakalayıp ana ekrana geçer.
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      setState(() => _hata = m.contains('invalid login')
          ? 'E-posta veya şifre hatalı'
          : m.contains('not confirmed')
              ? 'E-posta onaylanmamış. Yöneticiye başvurun.'
              : 'Giriş yapılamadı: ${e.message}');
    } catch (_) {
      setState(() => _hata =
          'Sunucuya ulaşılamadı. İlk giriş için internet bağlantısı gerekir.');
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
                  Icon(Icons.warehouse,
                      size: 72, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 12),
                  const Text('Depo Takip',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 32),
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
                  const Text(
                    'Hesap bilgilerini yöneticinizden alın.\n'
                    'Bir kez giriş yaptıktan sonra uygulama sizi hatırlar; '
                    'yalnızca "Çıkış yap" derseniz tekrar sorar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12),
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
