import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../database/app_database.dart';
import '../../database/platform/db_fabrika.dart';
import '../supabase_service.dart';
import '../sync_service.dart';
import 'bildirim_motoru.dart';

const _gorev = 'depo_bildirim_kontrol';
const _onPlanAnahtari = 'on_plan_ms';

/// Uygulama ön plandayken arka plan görevi çalışmaz (çift senkron ve
/// oturum anahtarı çakışması olmasın). Ön plan bunu düzenli işaretler.
Future<void> onPlandaIsaretle(bool aktif) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        _onPlanAnahtari, aktif ? DateTime.now().millisecondsSinceEpoch : 0);
  } catch (_) {}
}

@pragma('vm:entry-point')
void arkaPlanGirisi() {
  Workmanager().executeTask((gorev, veri) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();

      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final onPlan = prefs.getInt(_onPlanAnahtari) ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - onPlan < 90 * 1000) {
        return true; // uygulama açık; kontrolü o yapıyor
      }

      veritabaniFabrikasiniAyarla();
      await SupabaseService.init().timeout(const Duration(seconds: 20));
      if (!SupabaseService.girisYapildi) return true; // çıkış yapılmış

      final db = AppDatabase();
      try {
        await SyncService(db, onDurum: (_) {}, bildirimCalistir: false)
            .syncNow()
            .timeout(const Duration(minutes: 3));
      } catch (e) {
        debugPrint('Arka plan senkronu: $e');
      }
      await BildirimMotoru.calistir(db, benimId: SupabaseService.kullanici?.id);
      await db.close();
    } catch (e) {
      debugPrint('Arka plan görevi hatası: $e');
    }
    return true;
  });
}

/// Girişten sonra bir kez çağrılır; görev zaten kayıtlıysa korunur.
Future<void> arkaPlanBaslat() async {
  if (!Platform.isAndroid) return;
  try {
    await Workmanager().initialize(arkaPlanGirisi);
    await Workmanager().registerPeriodicTask(
      _gorev,
      _gorev,
      frequency: const Duration(minutes: 15),
    );
  } catch (e) {
    debugPrint('Arka plan görevi kaydedilemedi: $e');
  }
}
