import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'adres_servisi.dart';
import 'bildirim/bildirim_motoru.dart';
import 'supabase_service.dart';

/// Arayüze gösterilen senkron durumu.
class SyncDurum {
  final bool calisiyor;
  final int bekleyen; // sunucuya henüz gönderilmemiş kayıt sayısı
  final DateTime? sonBasari;
  final String? hata;

  const SyncDurum({
    this.calisiyor = false,
    this.bekleyen = 0,
    this.sonBasari,
    this.hata,
  });

  SyncDurum kopya({
    bool? calisiyor,
    int? bekleyen,
    DateTime? sonBasari,
    String? hata,
    bool hataTemizle = false,
  }) =>
      SyncDurum(
        calisiyor: calisiyor ?? this.calisiyor,
        bekleyen: bekleyen ?? this.bekleyen,
        sonBasari: sonBasari ?? this.sonBasari,
        hata: hataTemizle ? null : (hata ?? this.hata),
      );
}

/// Offline-first senkronizasyon: yerel değişiklikler (dirty=1) sunucuya
/// gönderilir, sunucudaki değişiklikler çekilip yerele uygulanır.
/// Çakışmada updated_at'i daha yeni olan kazanır. Sunucu tarafında
/// değişiklikler kendi saatiyle (synced_at) damgalanır, bu yüzden telefon
/// saati yanlış olsa da hiçbir değişiklik kaçmaz.
class SyncService {
  static const _tablolar = [
    'depolar',
    'urunler',
    'araclar',
    'kullanicilar',
    'cihazlar',
    'stok_hareketleri',
    'kullanim_kayitlari',
    'servis_kayitlari',
  ];
  static const _sayfa = 500;
  // Commit sırası yüzünden kaçabilecek satırlar için geriye doğru pay (ms).
  static const _binisme = 5000;

  final AppDatabase db;
  final void Function(SyncDurum) onDurum;

  SyncDurum _durum = const SyncDurum();
  StreamSubscription? _baglantiSub;
  StreamSubscription? _authSub;
  StreamSubscription? _degisiklikSub;
  Timer? _periyodik;
  Timer? _gecikme;
  bool _calisiyor = false;
  bool _kapandi = false;

  /// false: bildirim kontrolünü çağıran kendisi yapar (arka plan görevi).
  final bool bildirimCalistir;

  SyncService(this.db, {required this.onDurum, this.bildirimCalistir = true});

  SyncDurum get durum => _durum;

  void start() {
    _baglantiSub = Connectivity().onConnectivityChanged.listen((sonuclar) {
      if (sonuclar.any((r) => r != ConnectivityResult.none)) syncNow();
    });
    _authSub = SupabaseService.client.auth.onAuthStateChange.listen((e) {
      if (e.session != null) syncNow();
    });
    // Yerel değişiklik olunca kısa bir gecikmeyle gönder.
    _degisiklikSub = db.degisiklikler.listen((_) {
      _gecikme?.cancel();
      _gecikme = Timer(const Duration(seconds: 2), _degisiklikSonrasi);
    });
    _periyodik = Timer.periodic(const Duration(seconds: 30), (_) => syncNow());
    syncNow();
  }

  void dispose() {
    _kapandi = true;
    _baglantiSub?.cancel();
    _authSub?.cancel();
    _degisiklikSub?.cancel();
    _periyodik?.cancel();
    _gecikme?.cancel();
  }

  void _yayinla(SyncDurum d) {
    _durum = d;
    if (!_kapandi) onDurum(d);
  }

  Future<void> _degisiklikSonrasi() async {
    final bekleyen = await db.bekleyenSayisi();
    if (_kapandi) return;
    _yayinla(_durum.kopya(bekleyen: bekleyen));
    if (bekleyen > 0) syncNow();
  }

  /// Hemen senkronize eder (zaten çalışıyorsa yeni bir tur başlatmaz).
  Future<void> syncNow() async {
    if (_calisiyor || _kapandi) return;
    _calisiyor = true;
    // İlk durum bildirimi sağlayıcı oluşturulurken olmasın.
    await Future<void>.delayed(Duration.zero);
    try {
      if (!SupabaseService.girisYapildi) return;

      final baglanti = await Connectivity().checkConnectivity();
      if (baglanti.every((r) => r == ConnectivityResult.none)) {
        _yayinla(_durum.kopya(
          bekleyen: await db.bekleyenSayisi(),
          hata: 'Çevrimdışı: değişiklikler bağlantı gelince gönderilecek',
        ));
        return;
      }

      _yayinla(_durum.kopya(calisiyor: true, hataTemizle: true));
      final sorunlar = <String>[];
      await _gonder(sorunlar);
      await _cek(sorunlar);
      // İnternetsiz kaydedilmiş kurulum noktalarının il/ilçe/mahallesini bul.
      unawaited(AdresTamamlayici.calistir(db));

      _yayinla(SyncDurum(
        bekleyen: await db.bekleyenSayisi(),
        sonBasari: DateTime.now(),
        hata: sorunlar.isEmpty ? null : sorunlar.take(3).join('\n'),
      ));
    } catch (e) {
      _yayinla(SyncDurum(
        bekleyen: await db.bekleyenSayisi(),
        sonBasari: _durum.sonBasari,
        hata: _hataMetni(e),
      ));
    } finally {
      _calisiyor = false;
      // Senkrondan sonra yeni olaylar için bildirim kontrolü (çevrimdışı da
      // çalışır: gönderilmemiş kayıt hatırlatması vb.)
      if (bildirimCalistir && !_kapandi && SupabaseService.girisYapildi) {
        unawaited(BildirimMotoru.calistir(db,
            benimId: SupabaseService.kullanici?.id));
      }
    }
  }

  String _hataMetni(Object e) {
    if (e is PostgrestException) {
      if (e.code == '23505') return 'Seri no çakışması: ${e.message}';
      return 'Sunucu hatası: ${e.message}';
    }
    if (e is AuthException) return 'Oturum hatası: ${e.message}';
    return 'Sunucuya ulaşılamadı';
  }

  // -------------------------------------------------------------------
  // Yerel -> sunucu
  // -------------------------------------------------------------------
  Future<void> _gonder(List<String> sorunlar) async {
    for (final tablo in _tablolar) {
      final kolonlar = AppDatabase.senkronKolonlari[tablo]!;
      while (true) {
        final satirlar = await db.kirliSatirlar(tablo, limit: 200);
        if (satirlar.isEmpty) break;

        final yuk = [
          for (final r in satirlar) {for (final k in kolonlar) k: r[k]},
        ];

        try {
          await SupabaseService.upsertMany(tablo, yuk);
          for (final r in satirlar) {
            await db.senkronEdildi(
                tablo, r['id'] as String, (r['updated_at'] as num).toInt());
          }
        } catch (_) {
          // Toplu gönderim başarısız: tek tek dene ki tek bir hatalı kayıt
          // diğerlerini engellemesin.
          for (var i = 0; i < satirlar.length; i++) {
            try {
              await SupabaseService.upsertMany(tablo, [yuk[i]]);
              await db.senkronEdildi(tablo, satirlar[i]['id'] as String,
                  (satirlar[i]['updated_at'] as num).toInt());
            } catch (e) {
              sorunlar.add(_hataMetni(e));
            }
          }
          break; // hatalı satırlar dirty kalır; sonraki turda tekrar denenir
        }
      }
    }
  }

  // -------------------------------------------------------------------
  // Sunucu -> yerel
  // -------------------------------------------------------------------
  Future<void> _cek(List<String> sorunlar) async {
    for (final tablo in _tablolar) {
      try {
        await _tabloCek(tablo, sorunlar);
      } on PostgrestException catch (_) {
        // Sunucuda henüz oluşturulmamış yeni tablo diğer tabloların
        // senkronunu durdurmasın.
        if (tablo != 'servis_kayitlari') rethrow;
        sorunlar.add('Servis kayıtları sunucuda yok: Supabase güncelleme '
            'SQL\'ini (1.17.0) çalıştırın');
      }
    }
  }

  Future<void> _tabloCek(String tablo, List<String> sorunlar) async {
    {
      final imlec = await db.sonCekim(tablo);
      final baslangic = imlec > _binisme ? imlec - _binisme : 0;
      var enBuyuk = imlec;
      var offset = 0;
      final cakismalar = <String>[];

      while (true) {
        final sayfa = await SupabaseService.cek(tablo, baslangic, offset, _sayfa);
        if (sayfa.isEmpty) break;
        await db.uzaktanUygula(tablo, sayfa, cakismalar);
        for (final r in sayfa) {
          final t = (r['synced_at'] as num?)?.toInt() ?? 0;
          if (t > enBuyuk) enBuyuk = t;
        }
        if (sayfa.length < _sayfa) break;
        offset += _sayfa;
      }

      await db.sonCekimYaz(tablo, enBuyuk);
      if (cakismalar.isNotEmpty) {
        sorunlar.add('Seri no çakışması: ${cakismalar.take(3).join(', ')}');
      }
    }
  }
}
