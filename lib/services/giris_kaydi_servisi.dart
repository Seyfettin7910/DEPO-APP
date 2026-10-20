import 'package:flutter/foundation.dart';

import 'guncelleme_servisi.dart';
import 'tarayici.dart';
import 'supabase_service.dart';

/// Giriş kayıtları (kim, ne zaman, hangi IP'den, hangi cihaz / sürümle).
/// IP adresi sunucu tarafında, bağlantının kendisinden alınır.
/// Kayıt başarısız olursa (internet yok, SQL henüz çalıştırılmamış) giriş
/// engellenmez; sessizce geçilir.
class GirisKaydiServisi {
  static String get platform {
    final p = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android',
      TargetPlatform.iOS => 'iPhone / iPad',
      TargetPlatform.windows => 'Windows',
      TargetPlatform.macOS => 'Mac',
      TargetPlatform.linux => 'Linux',
      TargetPlatform.fuchsia => 'Fuchsia',
    };
    if (!kIsWeb) return 'Uygulama · $p';
    final t = tarayiciAdi(); // "iPhone / iPad · Safari", "Windows · Edge"…
    return t.isEmpty ? 'Web · $p' : 'Web · $p · $t';
  }

  static String get _surum => GuncellemeServisi.mevcutSurum.isEmpty
      ? '-'
      : GuncellemeServisi.mevcutSurum;

  static Future<void> basarili() async {
    try {
      await SupabaseService.client.rpc('giris_kaydet',
          params: {'p_platform': platform, 'p_surum': _surum});
    } catch (e) {
      debugPrint('Giriş kaydı yazılamadı: $e');
    }
  }

  static Future<void> hatali(String email) async {
    try {
      await SupabaseService.client.rpc('hatali_giris_kaydet', params: {
        'p_email': email,
        'p_platform': platform,
        'p_surum': _surum,
      });
    } catch (e) {
      debugPrint('Hatalı giriş kaydı yazılamadı: $e');
    }
  }

  /// Rapor için kayıtlar (yeniden eskiye). İnternet gerekir.
  static Future<List<Map<String, dynamic>>> kayitlar({
    DateTime? baslangic,
    DateTime? bitis,
    int limit = 5000,
  }) async {
    var sorgu = SupabaseService.client.from('giris_kayitlari').select();
    if (baslangic != null) {
      sorgu = sorgu.gte('tarih', baslangic.toUtc().toIso8601String());
    }
    if (bitis != null) {
      sorgu = sorgu.lte('tarih', bitis.toUtc().toIso8601String());
    }
    final sonuc =
        await sorgu.order('tarih', ascending: false).limit(limit);
    return List<Map<String, dynamic>>.from(sonuc);
  }

  /// Bu kullanıcı bu IP'den [once] tarihinden önce başarıyla girmiş mi?
  static Future<bool> oncedenVarMi(String email, String ip, DateTime once) async {
    final r = await SupabaseService.client
        .from('giris_kayitlari')
        .select('id')
        .eq('email', email)
        .eq('ip', ip)
        .eq('basarili', true)
        .lt('tarih', once.toUtc().toIso8601String())
        .limit(1);
    return (r as List).isNotEmpty;
  }
}
