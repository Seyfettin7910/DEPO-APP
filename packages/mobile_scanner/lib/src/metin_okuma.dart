// Depo Otomasyon eklemesi (eklentinin aslında yok).
//
// Android'de, çerçevede bir süre barkod görülmezse çerçevenin içi yazıdan
// okunur; okunan satırlar [MetinOkuma.satirlar] akışından gelir. Kamera
// açıkken okuma aralığı [MetinOkuma.hizAyarla] ile değiştirilir (pil
// tasarrufu). Web'de / iOS'ta hiçbir şey yapmaz.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/src/method_channel/mobile_scanner_method_channel.dart';
import 'package:mobile_scanner/src/mobile_scanner_platform_interface.dart';

/// Barkod yokken çerçeve içini yazıdan okuma (yalnız Android).
abstract final class MetinOkuma {
  static const _kanal = MethodChannel(
    'dev.steenbakker.mobile_scanner/scanner/method',
  );

  static bool get destekleniyor =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Okunan satırlar (her yazı tanıma turunda bir liste).
  static Stream<List<String>> get satirlar {
    final p = MobileScannerPlatform.instance;
    if (!destekleniyor || p is! MethodChannelMobileScanner) {
      return const Stream.empty();
    }
    return p.eventsStream.where((e) => e['name'] == 'metin').map(
          (e) => [
            for (final s in (e['data'] as List<Object?>? ?? const []))
              if (s is String) s,
          ],
        );
  }

  /// Yazıdan okumayı açar / kapatır. [bekleme]: barkodsuz geçmesi gereken
  /// süre; [aralik]: iki okuma arası en kısa süre.
  static Future<void> ayarla({
    required bool acik,
    Duration bekleme = const Duration(milliseconds: 2500),
    Duration aralik = const Duration(milliseconds: 500),
  }) async {
    if (!destekleniyor) return;
    try {
      await _kanal.invokeMethod<void>('metinOkuma', {
        'acik': acik,
        'bekleme': bekleme.inMilliseconds,
        'aralik': aralik.inMilliseconds,
      });
    } on Object catch (_) {}
  }

  /// Barkod okuma aralığı (ms): küçük = sık okuma, büyük = az pil.
  static Future<void> hizAyarla(int ms) async {
    if (!destekleniyor) return;
    try {
      await _kanal.invokeMethod<void>('hizAyarla', {'ms': ms});
    } on Object catch (_) {}
  }
}
