import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase bağlantı bilgileri. Buradaki "publishable (anon)" anahtar
/// uygulamaya gömülmek için tasarlanmış herkese açık anahtardır; veriyi
/// koruyan şey giriş zorunluluğu ve tablolardaki güvenlik kurallarıdır
/// (supabase_kurulum.sql). service_role / secret anahtarı ASLA buraya konmaz.
class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://xxnzfqtwtfzltjkjteco.supabase.co',
  );
  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_MVHdRixdEAENv4IpIpk27A_Pqkium2x',
  );
}

class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;

  static bool _hazir = false;

  static Future<void> init() async {
    if (_hazir) return;
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
      // Giriş yalnızca e-posta + şifre ile; e-posta linkiyle dönüş
      // (deep link) kullanılmıyor. Kapatmak açılışı hızlandırır ve bazı
      // Android sürümlerinde açılışta takılmayı önler.
      authOptions: FlutterAuthClientOptions(
        detectSessionInUri: false,
        // Oturum bilinen bir anahtarla saklanır; arka plan görevi oturumu
        // yenilerse uygulama açılınca buradan okunur.
        localStorage: SharedPreferencesLocalStorage(persistSessionKey: _oturumAnahtari),
      ),
    );
    _hazir = true;
  }

  static final _oturumAnahtari =
      'sb-${Uri.parse(SupabaseConfig.url).host.split('.').first}-auth-token';

  /// Arka plan görevi (uygulama kapalıyken) oturum anahtarını yenilemiş
  /// olabilir; uygulama öne gelince diskteki güncel oturuma geçilir. Böylece
  /// eski anahtarla yenileme yapılıp oturum düşmez.
  static Future<void> oturumuDisktenYenile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final kayitli = prefs.getString(_oturumAnahtari);
      final mevcut = client.auth.currentSession;
      if (kayitli == null || mevcut == null) return;
      final yenileme = (jsonDecode(kayitli) as Map)['refresh_token'];
      if (yenileme == null || yenileme == mevcut.refreshToken) return;
      await client.auth.recoverSession(kayitli);
    } catch (e) {
      debugPrint('Oturum diskten yenilenemedi: $e');
    }
  }

  static User? get kullanici => client.auth.currentUser;
  static bool get girisYapildi => client.auth.currentSession != null;

  static Future<void> girisYap(String email, String sifre) async {
    await client.auth.signInWithPassword(email: email, password: sifre);
  }

  static Future<void> cikisYap() => client.auth.signOut();

  /// Satırları toplu olarak (id'ye göre) ekler/günceller.
  static Future<void> upsertMany(
      String tablo, List<Map<String, Object?>> satirlar) async {
    await client.from(tablo).upsert(satirlar);
  }

  /// [since] (sunucu zamanı, ms) ve sonrasında değişen satırlardan bir sayfa.
  static Future<List<Map<String, dynamic>>> cek(
    String tablo,
    int since,
    int offset,
    int limit,
  ) async {
    final sonuc = await client
        .from(tablo)
        .select()
        .gte('synced_at', since)
        .order('synced_at')
        .order('id')
        .range(offset, offset + limit - 1);
    return List<Map<String, dynamic>>.from(sonuc);
  }
}
