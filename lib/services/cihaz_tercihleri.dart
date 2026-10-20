import 'package:shared_preferences/shared_preferences.dart';

/// Bu telefona özel tercihler (Ayarlar'dan değiştirilir, sunucuya gitmez).
class CihazTercihleri {
  CihazTercihleri._();

  static const _girisDeposu = 'varsayilan_giris_deposu';

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
