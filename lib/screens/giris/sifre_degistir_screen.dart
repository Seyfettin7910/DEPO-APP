import 'package:flutter/material.dart';

import '../../services/hesap_servisi.dart';
import '../../services/supabase_service.dart';

/// 1.36.0: Şifre değiştirme.
///
/// [zorunlu]: yöneticinin verdiği 6 haneli geçici şifreyle girildi; yeni
/// şifre belirlenmeden uygulama açılmaz (sunucu da bu kullanıcıya veri
/// vermez). Geçici şifre 15 dakika geçerlidir.
class SifreDegistirScreen extends StatefulWidget {
  const SifreDegistirScreen({
    super.key,
    this.zorunlu = false,
    this.bitis,
    this.tamam,
  });

  final bool zorunlu;
  final DateTime? bitis;

  /// Zorunlu değişiklik bitince (AuthGate yeniden denetler).
  final VoidCallback? tamam;

  @override
  State<SifreDegistirScreen> createState() => _SifreDegistirScreenState();
}

/// En az 8 karakter, harf ve rakam (sunucu da aynısını denetler).
String? sifreKuraliHatasi(String s) {
  if (s.length < 8) return 'En az 8 karakter olmalı';
  if (!RegExp(r'[0-9]').hasMatch(s)) return 'En az bir rakam olmalı';
  if (!RegExp(r'[A-Za-zÇĞİÖŞÜçğıöşü]').hasMatch(s)) {
    return 'En az bir harf olmalı';
  }
  return null;
}

class _SifreDegistirScreenState extends State<SifreDegistirScreen> {
  final _yeni = TextEditingController();
  final _tekrar = TextEditingController();
  bool _gizli = true;
  bool _calisiyor = false;
  String? _hata;
  bool _sureDoldu = false;

  @override
  void initState() {
    super.initState();
    if (widget.zorunlu) _geciciGirisiBildir();
  }

  Future<void> _geciciGirisiBildir() async {
    try {
      await HesapServisi.geciciGiris();
    } on HesapHatasi catch (e) {
      if (!mounted) return;
      setState(() {
        _sureDoldu = e.kod == 'sure_doldu';
        _hata = e.mesaj;
      });
    }
  }

  @override
  void dispose() {
    _yeni.dispose();
    _tekrar.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    final y = _yeni.text;
    final kural = sifreKuraliHatasi(y);
    if (kural != null) {
      setState(() => _hata = kural);
      return;
    }
    if (y != _tekrar.text) {
      setState(() => _hata = 'Şifreler aynı değil');
      return;
    }
    setState(() {
      _calisiyor = true;
      _hata = null;
    });
    try {
      await HesapServisi.sifreDegistir(y);
      // Oturum yenilensin (şifre değişince eski anahtar geçerli kalır ama
      // sunucu durumunu tazelemek için).
      try {
        await SupabaseService.client.auth.refreshSession();
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Şifreniz değiştirildi')));
      if (widget.zorunlu) {
        widget.tamam?.call();
      } else {
        Navigator.of(context).pop();
      }
    } on HesapHatasi catch (e) {
      if (!mounted) return;
      setState(() {
        _sureDoldu = e.kod == 'sure_doldu';
        _hata = e.mesaj;
      });
    } finally {
      if (mounted) setState(() => _calisiyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final bitis = widget.bitis;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.zorunlu ? 'Yeni şifre belirleyin' : 'Şifremi değiştir'),
        automaticallyImplyLeading: !widget.zorunlu,
        actions: [
          if (widget.zorunlu)
            TextButton(
              onPressed: () => SupabaseService.cikisYap(),
              child: const Text('Çıkış'),
            ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.zorunlu)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: tema.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Yöneticinizin verdiği geçici şifreyle girdiniz. Devam '
                      'etmek için kendi şifrenizi belirleyin.'
                      '${bitis == null ? '' : '\nGeçici şifre ${_saat(bitis)} saatine kadar geçerli.'}',
                    ),
                  ),
                if (_sureDoldu) ...[
                  Text(_hata ?? '',
                      style: TextStyle(color: tema.colorScheme.error)),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => SupabaseService.cikisYap(),
                    child: const Text('Giriş ekranına dön'),
                  ),
                ] else ...[
                  TextField(
                    controller: _yeni,
                    obscureText: _gizli,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'Yeni şifre',
                      helperText: 'En az 8 karakter, harf ve rakam',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_gizli ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _gizli = !_gizli),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tekrar,
                    obscureText: _gizli,
                    onSubmitted: (_) => _kaydet(),
                    decoration: const InputDecoration(
                      labelText: 'Yeni şifre (tekrar)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_hata != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_hata!,
                          style: TextStyle(color: tema.colorScheme.error)),
                    ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _calisiyor ? null : _kaydet,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(_calisiyor ? 'Kaydediliyor…' : 'Şifreyi kaydet'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _saat(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
