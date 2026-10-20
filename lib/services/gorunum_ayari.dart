import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ayarlar → "Büyük yazı": uygulamadaki yazıları ve simgeleri büyütür
/// (telefonun kendi yazı boyutunun üstüne). Bu cihazda saklanır.
class GorunumAyari {
  GorunumAyari._();

  static const _anahtar = 'buyuk_yazi';
  static const carpan = 1.2;
  static final buyukYazi = ValueNotifier<bool>(false);

  static Future<void> yukle() async {
    try {
      final p = await SharedPreferences.getInstance();
      buyukYazi.value = p.getBool(_anahtar) ?? false;
    } catch (_) {}
  }

  static Future<void> ayarla(bool acik) async {
    buyukYazi.value = acik;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_anahtar, acik);
    } catch (_) {}
  }

  /// MaterialApp.builder içinde: büyük yazı açıksa yazı ölçeği ve simge
  /// boyutu büyür.
  static Widget uygula(BuildContext context, Widget child) {
    return ValueListenableBuilder<bool>(
      valueListenable: buyukYazi,
      child: child,
      builder: (context, acik, child) {
        if (!acik) return child!;
        final mq = MediaQuery.of(context);
        final sistem = mq.textScaler.scale(100) / 100;
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(sistem * carpan)),
          child: IconTheme.merge(
            data: const IconThemeData(size: 24 * carpan),
            child: child!,
          ),
        );
      },
    );
  }
}
