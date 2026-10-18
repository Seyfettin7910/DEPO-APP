import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final _eklenti = FlutterLocalNotificationsPlugin();
bool _hazir = false;

bool get sistemBildirimiVar => Platform.isAndroid;

Future<bool> _hazirla() async {
  if (!Platform.isAndroid) return false;
  if (_hazir) return true;
  await _eklenti.initialize(
    const InitializationSettings(
      // res/drawable-*/ic_bildirim.png: bildirim çubuğundaki beyaz simge
      android: AndroidInitializationSettings('ic_bildirim'),
    ),
  );
  _hazir = true;
  return true;
}

Future<void> bildirimGoster(int id, String baslik, String govde) async {
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
    );
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
