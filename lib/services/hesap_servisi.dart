import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// 1.36.0: hesap işlemleri (sunucudaki "hesap" fonksiyonu).
///
/// Şifre ya da geçici kod hiçbir yere yazılmaz; geçici kod yalnızca
/// yöneticinin ekranında bir kez gösterilir. Tüm işlemler sunucuda
/// hesap_islemleri tablosuna kaydedilir.
class HesapHatasi implements Exception {
  const HesapHatasi(this.kod, this.mesaj);
  final String kod;
  final String mesaj;
  @override
  String toString() => mesaj;
}

/// Kullanıcı ekleme / şifre sıfırlama sonucu: 6 haneli geçici şifre.
class GeciciSifre {
  const GeciciSifre(this.kod, this.bitis, {this.id});
  final String kod;
  final DateTime bitis;
  final String? id;
}

/// Giriş yapan kişinin sunucudaki durumu (benim_durumum).
class HesapDurumu {
  const HesapDurumu({
    required this.var_,
    this.rol,
    this.aktif = true,
    this.sifreDegistirmeli = false,
    this.geciciBitis,
    this.ham = const {},
  });
  final bool var_;
  final String? rol;
  final bool aktif;
  final bool sifreDegistirmeli;
  final DateTime? geciciBitis;
  final Map<String, dynamic> ham;

  bool get sureDoldu =>
      sifreDegistirmeli &&
      geciciBitis != null &&
      geciciBitis!.isBefore(DateTime.now());
}

class HesapServisi {
  static Future<Map<String, dynamic>> _cagir(Map<String, Object?> govde) async {
    try {
      final r = await SupabaseService.client.functions
          .invoke('hesap', body: govde);
      final d = r.data;
      if (d is Map && d['ok'] == true) return Map<String, dynamic>.from(d);
      if (d is Map) {
        throw HesapHatasi('${d['kod'] ?? 'hata'}', '${d['mesaj'] ?? 'İşlem yapılamadı'}');
      }
      throw const HesapHatasi('hata', 'İşlem yapılamadı');
    } on FunctionException catch (e) {
      final d = e.details;
      if (d is Map && d['mesaj'] != null) {
        throw HesapHatasi('${d['kod'] ?? 'hata'}', '${d['mesaj']}');
      }
      if (e.status == 404) {
        throw const HesapHatasi('fonksiyon_yok',
            'Sunucuda hesap fonksiyonu yok (1.36.0 güncellemesi yüklenmemiş)');
      }
      throw HesapHatasi('hata', 'İşlem yapılamadı (${e.status})');
    } on HesapHatasi {
      rethrow;
    } catch (_) {
      throw const HesapHatasi(
          'baglanti', 'Sunucuya ulaşılamadı. Bu işlem için internet gerekir.');
    }
  }

  static DateTime _tarih(Object? ms) =>
      DateTime.fromMillisecondsSinceEpoch((ms as num?)?.toInt() ?? 0);

  /// Giriş yapmadan "Şifremi unuttum": yöneticilere bildirim gider.
  /// E-posta kayıtlı olsun olmasın aynı yanıt döner.
  static Future<void> sifreTalebi(String email) =>
      _cagir({'islem': 'sifre_talebi', 'email': email.trim()});

  /// Geçici şifreyle girildiğini sunucuya bildirir (süre doldu mu bakılır).
  static Future<void> geciciGiris() => _cagir({'islem': 'gecici_giris'});

  /// Kendi şifresini değiştirir (en az 8 karakter, harf ve rakam).
  static Future<void> sifreDegistir(String yeni) =>
      _cagir({'islem': 'sifre_degistir', 'yeni': yeni});

  static Future<GeciciSifre> ekle({
    required String email,
    required String ad,
    required String rol,
    String? unvan,
  }) async {
    final d = await _cagir({
      'islem': 'ekle',
      'email': email.trim(),
      'ad': ad.trim(),
      'rol': rol,
      'unvan': unvan?.trim() ?? '',
    });
    return GeciciSifre('${d['kod']}', _tarih(d['bitis']), id: d['id'] as String?);
  }

  static Future<GeciciSifre> sifirla(String id) async {
    final d = await _cagir({'islem': 'sifirla', 'id': id});
    return GeciciSifre('${d['kod']}', _tarih(d['bitis']), id: id);
  }

  static Future<void> durum(String id, {required bool aktif}) =>
      _cagir({'islem': 'durum', 'id': id, 'aktif': aktif});

  static Future<void> guncelle(String id,
          {String? rol, String? unvan, String? ad}) =>
      _cagir({
        'islem': 'guncelle',
        'id': id,
        if (rol != null) 'rol': rol,
        if (unvan != null) 'unvan': unvan,
        if (ad != null) 'ad': ad,
      });

  /// Sunucudaki kendi durumum. Sunucu eski sürümse (fonksiyon yoksa) ya da
  /// internet yoksa null: giriş engellenmez.
  static Future<HesapDurumu?> benimDurumum() async {
    try {
      final r = await SupabaseService.client.rpc('benim_durumum');
      if (r is! Map) return null;
      final m = Map<String, dynamic>.from(r);
      return HesapDurumu(
        var_: m['var'] == true,
        rol: m['rol'] as String?,
        aktif: ((m['aktif'] as num?)?.toInt() ?? 1) == 1,
        sifreDegistirmeli: ((m['sifre_degistirmeli'] as num?)?.toInt() ?? 0) == 1,
        geciciBitis: m['gecici_bitis'] == null ? null : _tarih(m['gecici_bitis']),
        ham: m,
      );
    } catch (_) {
      return null;
    }
  }

  /// Şifre talepleri ve hesap işlemleri (yalnız kullanıcı yönetimi yetkisi).
  static Future<List<Map<String, dynamic>>> islemler({
    String? tur,
    DateTime? baslangic,
    int limit = 500,
  }) async {
    var q = SupabaseService.client.from('hesap_islemleri').select();
    if (tur != null) q = q.eq('tur', tur);
    if (baslangic != null) {
      q = q.gte('tarih', baslangic.toUtc().toIso8601String());
    }
    final r = await q.order('tarih', ascending: false).limit(limit);
    return List<Map<String, dynamic>>.from(r);
  }

  /// Yetki ihlalleri (sunucu "kayıt" kipindeyken yazılanlar).
  static Future<List<Map<String, dynamic>>> ihlaller({int limit = 300}) async {
    final r = await SupabaseService.client
        .from('yetki_ihlalleri')
        .select()
        .order('tarih', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(r);
  }
}

/// hesap_islemleri.tur → okunur ad.
String hesapIslemAdi(Object? tur) => switch ('$tur') {
      'sifre_talebi' => 'Şifre talebi',
      'sifre_sifirlama' => 'Şifre sıfırlandı',
      'gecici_giris' => 'Geçici şifreyle giriş',
      'sifre_degisti' => 'Şifre değiştirildi',
      'gecici_suresi_doldu' => 'Geçici şifre süresi doldu',
      'kullanici_ekleme' => 'Kullanıcı eklendi',
      'rol_degisti' => 'Rol / unvan değişti',
      'pasif' => 'Pasif yapıldı',
      'aktif' => 'Aktif yapıldı',
      'ad_degisti' => 'Ad değişti',
      final t => t,
    };
