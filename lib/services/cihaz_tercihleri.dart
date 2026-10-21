import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bu telefona özel tercihler (Ayarlar'dan değiştirilir, sunucuya gitmez).
class CihazTercihleri {
  CihazTercihleri._();

  static const _girisDeposu = 'varsayilan_giris_deposu';
  static const _yazidanOku = 'yazidan_oku';

  /// Ayarlar → "Yazıdan da oku" (Android): barkod okunmazsa çerçevedeki
  /// "S/N" satırı yazıdan okunur. Varsayılan AÇIK.
  static final yazidanOku = ValueNotifier<bool>(true);

  /// Uygulama açılırken bir kez (main.dart).
  static Future<void> yukle() async {
    try {
      final p = await SharedPreferences.getInstance();
      yazidanOku.value = p.getBool(_yazidanOku) ?? true;
    } catch (_) {}
  }

  static Future<void> yazidanOkuAyarla(bool acik) async {
    yazidanOku.value = acik;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_yazidanOku, acik);
    } catch (_) {}
  }

  /// Depoya girişte hazır seçili gelen depo.
  static Future<String?> girisDeposu() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_girisDeposu);
    } catch (_) {
      return null;
    }
  }

  static Future<void> girisDeposuAyarla(String? depoId) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (depoId == null) {
        await p.remove(_girisDeposu);
      } else {
        await p.setString(_girisDeposu, depoId);
      }
    } catch (_) {}
  }
}
