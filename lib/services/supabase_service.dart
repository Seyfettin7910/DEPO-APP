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
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    );
    _hazir = true;
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
