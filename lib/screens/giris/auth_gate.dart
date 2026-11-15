import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/app_providers.dart';
import '../../services/hesap_servisi.dart';
import '../../services/oturum_kilidi.dart';
import '../../services/supabase_service.dart';
import '../home_screen.dart';
import 'giris_screen.dart';
import 'sifre_degistir_screen.dart';

/// Oturum varsa ana ekranı, yoksa giriş ekranını gösterir. Oturum telefonda
/// saklanır; çevrimdışı açılışta da giriş istenmez.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  Session? _oturum;
  StreamSubscription<AuthState>? _sub;

  /// 1.36.0: sunucudaki hesap durumu (pasif mi, şifre değişmeli mi).
  /// İnternet yoksa ya da sunucu eskiyse null: uygulama açılır.
  HesapDurumu? _durum;
  String? _denetlenen;

  @override
  void initState() {
    super.initState();
    _oturum = SupabaseService.client.auth.currentSession;
    Future.microtask(() => _kullaniciyiAyarla(_oturum?.user));
    _sub = SupabaseService.client.auth.onAuthStateChange.listen((e) {
      if (!mounted) return;
      // Yalnızca açık çıkışta giriş ekranına dön; geçici yenileme
      // hataları kullanıcıyı dışarı atmasın.
      if (e.event == AuthChangeEvent.signedOut) {
        setState(() => _oturum = null);
        _kullaniciyiAyarla(null);
      } else if (e.session != null) {
        setState(() => _oturum = e.session);
        _kullaniciyiAyarla(e.session!.user);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _kullaniciyiAyarla(User? user) {
    if (!mounted) return;
    ref.read(aktifKullaniciIdProvider.notifier).state = user?.id;
    if (user != null) {
      ref
          .read(appDatabaseProvider)
          .kullaniciGarantiEt(user.id, user.email ?? user.id);
      if (_denetlenen != user.id) {
        _denetlenen = user.id;
        unawaited(_durumuDenetle(user.id));
      }
    } else {
      _denetlenen = null;
      _durum = null;
    }
  }

  Future<void> _durumuDenetle(String id) async {
    final d = await HesapServisi.benimDurumum();
    if (!mounted || d == null || _oturum?.user.id != id) return;
    if (d.var_) {
      await ref.read(appDatabaseProvider).kullaniciDurumuYaz(id, d.ham);
    }
    if (d.var_ && !d.aktif) {
      GirisScreen.bilgi = 'Hesabınız pasif. Yöneticinize başvurun.';
      await SupabaseService.cikisYap();
      return;
    }
    if (mounted) setState(() => _durum = d);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OturumKilidi.instance,
      builder: (context, _) {
        if (_oturum == null || OturumKilidi.instance.kilitli) {
          return const GirisScreen();
        }
        final d = _durum;
        if (d != null && d.sifreDegistirmeli) {
          return SifreDegistirScreen(
            zorunlu: true,
            bitis: d.geciciBitis,
            tamam: () {
              final id = _oturum?.user.id;
              setState(() => _durum = null);
              if (id != null) unawaited(_durumuDenetle(id));
            },
          );
        }
        return const HomeScreen();
      },
    );
  }
}
