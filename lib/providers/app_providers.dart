import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/models.dart';
import '../services/sync_service.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Arayüzde gösterilen senkron durumu (bekleyen kayıt, son başarı, hata).
final syncDurumProvider = StateProvider<SyncDurum>((ref) => const SyncDurum());

final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService(
    ref.watch(appDatabaseProvider),
    onDurum: (d) => ref.read(syncDurumProvider.notifier).state = d,
  );
  service.start();
  ref.onDispose(service.dispose);
  return service;
});

/// Seçili depo (kullanıcı birden fazla depoya yetkiliyse üstten seçer).
final seciliDepoIdProvider = StateProvider<String?>((ref) => null);

final depolarStreamProvider = StreamProvider<List<Depo>>((ref) {
  return ref.watch(appDatabaseProvider).depolarStream();
});

final urunlerStreamProvider = StreamProvider<List<Urun>>((ref) {
  return ref.watch(appDatabaseProvider).urunlerStream();
});

/// Depo listesinde gösterilen özet (kaç çeşit ürün, toplam miktar).
final depoOzetleriProvider = StreamProvider<Map<String, DepoOzet>>((ref) {
  return ref.watch(appDatabaseProvider).depoOzetleriStream();
});

/// Minimum adedin altına inmiş ürünler (sabit depolardaki toplama göre).
final kritikStoklarProvider = StreamProvider<List<KritikStok>>((ref) {
  return ref.watch(appDatabaseProvider).kritikStoklarStream();
});

/// Ürün listesinde gösterilen, tüm depolardaki toplam stok.
final urunToplamStoklariProvider = StreamProvider<Map<String, int>>((ref) {
  return ref.watch(appDatabaseProvider).urunToplamStoklariStream();
});

/// Bir depoya giren/çıkan ürünlerin geçmişi.
final depoHareketleriProvider =
    StreamProvider.family<List<HareketSatiri>, String>((ref, depoId) {
  return ref.watch(appDatabaseProvider).depoHareketleriStream(depoId);
});

/// Bir depoda şu an bulunan seri numaralı cihazlar.
final depoCihazlariProvider =
    StreamProvider.family<List<CihazBilgi>, String>((ref, depoId) {
  return ref.watch(appDatabaseProvider).depoCihazlariStream(depoId);
});

/// Bir depodaki model bazlı adetler (urunId -> adet).
final depoUrunSayilariProvider =
    StreamProvider.family<Map<String, int>, String>((ref, depoId) {
  return ref.watch(appDatabaseProvider).depoUrunSayilariStream(depoId);
});

/// Seri no / model / depo / araç-yer araması.
final cihazAraProvider =
    StreamProvider.autoDispose.family<List<CihazBilgi>, String>((ref, sorgu) {
  return ref.watch(appDatabaseProvider).cihazAraStream(sorgu);
});

final cihazBilgiProvider =
    StreamProvider.family<CihazBilgi?, String>((ref, cihazId) {
  return ref.watch(appDatabaseProvider).cihazBilgiStream(cihazId);
});

final cihazGecmisiProvider =
    StreamProvider.family<List<CihazHareketSatiri>, String>((ref, cihazId) {
  return ref.watch(appDatabaseProvider).cihazGecmisiStream(cihazId);
});

/// Girişte Supabase auth'tan gelen kullanıcının yerel kullanicilar
/// tablosundaki karşılığı. Basitlik için burada elle set edilecek
/// şekilde bırakıldı; gerçek projede auth state listener ile doldurulur.
final aktifKullaniciIdProvider = StateProvider<String?>((ref) => null);

/// Bir cihazın arıza / servis dosyaları (en yeni üstte).
final cihazServisKayitlariProvider =
    StreamProvider.family<List<ServisKaydi>, String>((ref, cihazId) {
  return ref.watch(appDatabaseProvider).cihazServisKayitlariStream(cihazId);
});

/// Uygulama içi bildirimler (zil simgesi ve liste).
final okunmamisBildirimProvider = StreamProvider<int>((ref) {
  return ref.watch(appDatabaseProvider).okunmamisBildirimSayisiStream();
});

final bildirimListesiProvider =
    StreamProvider<List<Map<String, Object?>>>((ref) {
  return ref.watch(appDatabaseProvider).bildirimListesiStream();
});
