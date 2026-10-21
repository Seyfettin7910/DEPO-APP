# mobile_scanner 7.4.2 – Depo Otomasyon kopyası

Kaynak: https://github.com/juliansteenbakker/mobile_scanner (v7.4.2, BSD-3, LICENSE aynen).
`example/`, `test/` ve geliştirme dosyaları alınmadı.

Değişiklikler (yalnız bunlar; gerisi aslıyla aynı):

- `android/.../MobileScanner.kt`: çerçevede `metinBekleme` (2,5 sn) barkod
  görülmezse çerçeve içi (dikeyde %35 genişletilmiş) kesilip ML Kit yazı
  tanımaya verilir, en fazla `metinAralik` (0,5 sn) arayla. Satırlar
  `metinCallback` ile gider. `hizAyarla(ms)`: kamera açıkken okuma aralığı.
- `android/.../MobileScannerHandler.kt`: `metinOkuma`, `hizAyarla` metotları;
  `{"name": "metin", "data": [satırlar]}` olayı.
- `android/build.gradle.kts`: `play-services-mlkit-text-recognition`.
- `android/src/main/AndroidManifest.xml`: `com.google.mlkit.vision.DEPENDENCIES = ocr`.
- `lib/src/metin_okuma.dart` (yeni) ve `lib/mobile_scanner.dart`'ta export.

Eklentinin yeni sürümüne geçilecekse bu maddeler yeni sürüme yeniden uygulanır.
