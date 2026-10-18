// APK indirme ve kurma. Yalnızca Android'de çalışır; web derlemesine
// dart:io ve yerel kanal kodu karışmasın diye ayrı dosyalardan seçilir.
export 'apk_kurucu_io.dart' if (dart.library.js_interop) 'apk_kurucu_web.dart';
