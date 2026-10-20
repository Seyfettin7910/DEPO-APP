import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Barkod okuma sonuçları için ses + titreşim + görsel onay.
/// Sesler `assets/sounds/` altındadır ve telefonun medya sesinden çalar.
/// iPhone'da (web) titreşim olmadığından kamera çerçevesi yeşil / kırmızı
/// yanar ([onay]); ses de ilk dokunuşta hazırlanır ([ilkDokunus]).
class SesServisi {
  static final AudioPlayer _player = AudioPlayer();

  /// Son okuma sonucu: true = başarılı (yeşil), false = hata (kırmızı).
  /// Kamera ekranları dinler ve çerçeveyi kısa süre o renkte yakar.
  static final onay = ValueNotifier<(bool, int)?>(null);
  static int _sayac = 0;

  static Future<void> _cal(String dosya) async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/$dosya'), volume: 1.0);
    } catch (_) {
      // Ses çalınamazsa uygulama akışı bozulmasın.
    }
  }

  static bool _hazir = false;

  /// iPhone (Safari) ilk dokunuştan önce ses çaldırmaz: ilk dokunuşta sesi
  /// sessizce bir kez çalıp hazırlarız, böylece ilk okutmada da ses çıkar.
  static void ilkDokunus() {
    if (!kIsWeb || _hazir) return;
    _hazir = true;
    () async {
      try {
        await _player.play(AssetSource('sounds/basari.wav'), volume: 0);
        await _player.stop();
      } catch (_) {}
    }();
  }

  /// Ürün bulundu / işlem başarılı: kısa bip.
  static Future<void> basari() async {
    HapticFeedback.lightImpact();
    onay.value = (true, ++_sayac);
    await _cal('basari.wav');
  }

  /// Ürün bulunamadı / hata: uyarı sesi + güçlü titreşim.
  static Future<void> hata() async {
    HapticFeedback.heavyImpact();
    onay.value = (false, ++_sayac);
    await _cal('hata.wav');
  }
}
