import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    'kurum_kodlari',
    'kurum_ayarlari',
    'cihazlar',
    'stok_hareketleri',
    'kullanim_kayitlari',
    'servis_kayitlari',
    'etiketler',
    'etiket_hareketleri',
  ];

  /// Sonradan eklenen tablolar ve onları oluşturan Supabase SQL sürümü.
  /// Sunucuda henüz yoksa diğer tabloların senkronu durmasın.
  static const _yeniTablolar = {
    'servis_kayitlari': '1.17.0',
    'kurum_kodlari': '1.22.0',
    'kurum_ayarlari': '1.22.0',
    'etiketler': '1.22.0',
    'etiket_hareketleri': '1.22.0',
  };

  /// Sonradan eklenen sütunlar ve SQL sürümü. Sunucuda henüz yoksa o sütun
  /// gönderilmez (diğer bilgiler gider), SQL çalıştırılınca kendiliğinden
  /// gönderilmeye başlar.
  static const _yeniKolonlar = {
    'urunler': {'kutu_icerigi': '1.27.0'},
  };
  static final _eksikKolonlar = <String, Set<String>>{};

  /// PostgREST "Could not find the 'x' column of 'tablo'" hatasındaki sütun.
  static String? _eksikKolon(Object e, String tablo) {
    if (e is! PostgrestException) return null;
    final m = RegExp(r"Could not find the '([^']+)' column").firstMatch(e.message);
    final k = m?.group(1);
    if (k != null && (_yeniKolonlar[tablo]?.containsKey(k) ?? false)) return k;
    return null;
  }

  static bool _tabloYok(Object e) =>
      e is PostgrestException &&
      (e.code == '42P01' ||
          e.code == 'PGRST205' ||
          e.message.contains('does not exist') ||
          e.message.contains('Could not find the table'));

  static String _sqlMesaji(String tablo) =>
      'Sunucuda "$tablo" tablosu yok: Supabase güncelleme SQL\'ini '
      '(${_yeniTablolar[tablo]}) çalıştırın';
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

  static const _sonSenkronAnahtari = 'son_senkron_ms';

  void start() {
    // Son başarılı senkron saati uygulama yeniden açılınca da görünsün.
    unawaited(SharedPreferences.getInstance().then((p) {
      final ms = p.getInt(_sonSenkronAnahtari);
      if (ms != null && _durum.sonBasari == null && !_kapandi) {
        _yayinla(_durum.kopya(
            sonBasari: DateTime.fromMillisecondsSinceEpoch(ms)));
      }
    }).catchError((_) {}));
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

      final simdi = DateTime.now();
      unawaited(SharedPreferences.getInstance()
          .then((p) => p.setInt(_sonSenkronAnahtari, simdi.millisecondsSinceEpoch))
          .catchError((_) => false));
      _yayinla(SyncDurum(
        bekleyen: await db.bekleyenSayisi(),
        sonBasari: simdi,
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
      while (true) {
        final eksik = _eksikKolonlar[tablo] ?? const <String>{};
        final kolonlar = [
          for (final k in AppDatabase.senkronKolonlari[tablo]!)
            if (!eksik.contains(k)) k
        ];
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
        } catch (e) {
          final kolon = _eksikKolon(e, tablo);
          if (kolon != null) {
            // Sütun sunucuda yok: onsuz tekrar gönder.
            (_eksikKolonlar[tablo] ??= {}).add(kolon);
            final m = 'Sunucuda "$tablo.$kolon" sütunu yok: Supabase güncelleme '
                'SQL\'ini (${_yeniKolonlar[tablo]![kolon]}) çalıştırın';
            if (!sorunlar.contains(m)) sorunlar.add(m);
            continue;
          }
          if (_yeniTablolar.containsKey(tablo) && _tabloYok(e)) {
            final m = _sqlMesaji(tablo);
            if (!sorunlar.contains(m)) sorunlar.add(m);
            break; // kayıtlar yerelde bekler; SQL çalıştırılınca gönderilir
          }
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
      } on PostgrestException catch (e) {
        // Sunucuda henüz oluşturulmamış yeni tablo diğer tabloların
        // senkronunu durdurmasın.
        if (!_yeniTablolar.containsKey(tablo)) rethrow;
        final m = _tabloYok(e) ? _sqlMesaji(tablo) : _hataMetni(e);
        if (!sorunlar.contains(m)) sorunlar.add(m);
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
