// Web bildirimi (iPhone ana ekran uygulaması / bilgisayar tarayıcısı).
// Android uygulamasında kullanılmaz (orada telefon kendisi bildirir).
export 'web_push_io.dart' if (dart.library.js_interop) 'web_push_web.dart';
