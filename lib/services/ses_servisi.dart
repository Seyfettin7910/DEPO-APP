import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Barkod okuma sonuçları için ses + titreşim geri bildirimi.
/// Sesler `assets/sounds/` altındadır ve telefonun medya sesinden çalar.
class SesServisi {
  static final AudioPlayer _player = AudioPlayer();

  static Future<void> _cal(String dosya) async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/$dosya'), volume: 1.0);
    } catch (_) {
      // Ses çalınamazsa uygulama akışı bozulmasın.
    }
  }

  /// Ürün bulundu / işlem başarılı: kısa bip.
  static Future<void> basari() async {
    HapticFeedback.lightImpact();
    await _cal('basari.wav');
  }

  /// Ürün bulunamadı / hata: uyarı sesi + güçlü titreşim.
  static Future<void> hata() async {
    HapticFeedback.heavyImpact();
    await _cal('hata.wav');
  }
}
