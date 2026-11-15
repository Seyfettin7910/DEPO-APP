import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final _eklenti = FlutterLocalNotificationsPlugin();
bool _hazir = false;

bool get sistemBildirimiVar => Platform.isAndroid;

/// 1.36.0: dokunulan bildirimin yükü (ör. "sifreTalebi"); ana ekran dinler
/// ve ilgili ekranı açar, sonra null yapar.
final bildirimDokunusu = ValueNotifier<String?>(null);

Future<bool> _hazirla() async {
  if (!Platform.isAndroid) return false;
  if (_hazir) return true;
  await _eklenti.initialize(
    const InitializationSettings(
      // res/drawable-*/ic_bildirim.png: bildirim çubuğundaki beyaz simge
      android: AndroidInitializationSettings('ic_bildirim'),
    ),
    onDidReceiveNotificationResponse: (r) {
      if (r.payload != null && r.payload!.isNotEmpty) {
        bildirimDokunusu.value = r.payload;
      }
    },
  );
  _hazir = true;
  // Uygulama bildirime dokunularak açıldıysa
  try {
    final d = await _eklenti.getNotificationAppLaunchDetails();
    final y = d?.notificationResponse?.payload;
    if ((d?.didNotificationLaunchApp ?? false) && y != null && y.isNotEmpty) {
      bildirimDokunusu.value = y;
    }
  } catch (_) {}
  return true;
}

Future<void> bildirimGoster(int id, String baslik, String govde,
    {String? yuk}) async {
  try {
    if (!await _hazirla()) return;
    await _eklenti.show(
      id,
      baslik,
      govde,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'depo_bildirim',
          'Depo bildirimleri',
          channelDescription:
              'Kritik stok, arıza, servis, transfer ve günlük özet bildirimleri',
          importance: Importance.high,
          priority: Priority.high,
          color: const Color(0xFF2E6F40),
          styleInformation: BigTextStyleInformation(govde),
        ),
      ),
      payload: yuk,
    );
  } catch (_) {}
}

/// Açılışta dokunuşu yakalamak için eklentiyi hazırlar.
Future<void> bildirimDokunusunuHazirla() async {
  try {
    await _hazirla();
  } catch (_) {}
}

/// Android 13+ bildirim izni (bir kez sorulur).
Future<bool> bildirimIzniIste() async {
  try {
    if (!await _hazirla()) return false;
    final android = _eklenti.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  } catch (_) {
    return false;
  }
}

/// Pil tasarrufu kısıtlamasını kaldırma ekranı (arka plan kontrolü
/// bazı telefonlarda bu kısıtlama yüzünden gecikebilir).
Future<void> pilAyariniAc() async {
  try {
    await const MethodChannel('depo_takip/guncelleme').invokeMethod('pilAyari');
  } catch (_) {}
}
