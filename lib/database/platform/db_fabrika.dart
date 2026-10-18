// Yerel veritabanının platforma göre ayarlanması.
// Web'de sqflite doğrudan çalışmaz; tarayıcıda sqlite (wasm) + IndexedDB
// kullanılır. Masaüstünde (Windows/Linux) FFI arka ucu gerekir.
// Doğru dosya derleme anında seçilir, böylece web derlemesine dart:ffi,
// mobil derlemeye de web paketleri karışmaz.
export 'db_fabrika_io.dart'
    if (dart.library.js_interop) 'db_fabrika_web.dart';
