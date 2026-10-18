import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/app_providers.dart';
import '../../services/supabase_service.dart';
import '../home_screen.dart';
import 'giris_screen.dart';

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
    }
  }

  @override
  Widget build(BuildContext context) {
    return _oturum == null ? const GirisScreen() : const HomeScreen();
  }
}
