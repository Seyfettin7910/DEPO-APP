import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../supabase_service.dart';
import 'bildirim_ayarlari.dart';
import 'web_push.dart';

/// iPhone / bilgisayar tarayıcısında sunucudan gelen bildirimler.
/// Abonelik ve bildirim ayarları sunucuya (push_abonelikleri) yazılır;
/// sunucudaki zamanlanmış görev olayları hesaplayıp bildirimi gönderir.
class WebBildirim {
  static String? _genelAnahtar;

  static bool get destekleniyor => kIsWeb && webPushDestek();
  static bool get iphone => kIsWeb && webPushIos();

  /// iPhone'da bildirim yalnızca ana ekrana eklenmiş uygulamada çalışır.
  static bool get anaEkranGerekli => iphone && !webPushAnaEkran();
  static String get izin => webPushIzin();

  /// Ayarlar ekranı açılınca önceden çağrılır (abone olurken bekleme olmasın).
  static Future<void> hazirla() async {
    if (!kIsWeb || _genelAnahtar != null) return;
    try {
      final k = await SupabaseService.client.rpc('push_genel_anahtar');
      if (k is String && k.isNotEmpty) _genelAnahtar = k;
    } catch (e) {
      debugPrint('Bildirim anahtarı alınamadı: $e');
    }
  }

  static Future<bool> aboneMi() async => (await webPushMevcut()).isNotEmpty;

  static String get _platform =>
      iphone ? 'iPhone / iPad (web)' : 'Web tarayıcısı';

  static Future<void> _kaydet(String json, BildirimAyarlari a) async {
    final m = jsonDecode(json) as Map<String, dynamic>;
    final anahtarlar = (m['keys'] as Map?) ?? const {};
    await SupabaseService.client.rpc('push_abone_ol', params: {
      'p_endpoint': m['endpoint'],
      'p_p256dh': anahtarlar['p256dh'],
      'p_auth': anahtarlar['auth'],
      'p_ayarlar': a.toJson(),
      'p_platform': _platform,
    });
  }

  /// Bildirimi açar. Hata varsa açıklamasını, başarılıysa null döndürür.
  /// Düğmenin onPressed'inde ilk iş olarak (await'ten önce) çağrılmalı.
  static Future<String?> ac(BildirimAyarlari a) async {
    final anahtar = _genelAnahtar;
    if (anahtar == null) {
      // Anahtar henüz yoksa sunucu ilk kez hazırlanıyordur.
      await hazirla();
      return 'Sunucu hazırlanıyor. Birkaç dakika sonra tekrar deneyin.';
    }
    try {
      final json = await webPushAbone(anahtar);
      if (json.isEmpty) {
        return 'Bildirim izni verilmedi.';
      }
      await _kaydet(json, a);
      return null;
    } catch (e) {
      return 'Bildirim açılamadı: $e';
    }
  }

  /// Ayarlar değişince veya uygulama açılınca abonelik bilgisini tazeler.
  static Future<void> guncelle(BildirimAyarlari a) async {
    if (!kIsWeb) return;
    try {
      final json = await webPushMevcut();
      if (json.isNotEmpty) await _kaydet(json, a);
    } catch (e) {
      debugPrint('Bildirim aboneliği güncellenemedi: $e');
    }
  }

  static Future<void> kapat() async {
    if (!kIsWeb) return;
    try {
      final uc = await webPushIptal();
      if (uc.isNotEmpty) {
        await SupabaseService.client
            .rpc('push_abonelik_sil', params: {'p_endpoint': uc});
      }
    } catch (e) {
      debugPrint('Bildirim aboneliği kapatılamadı: $e');
    }
  }

  static Future<bool> test(String baslik, String govde) =>
      webPushTest(baslik, govde);
}
