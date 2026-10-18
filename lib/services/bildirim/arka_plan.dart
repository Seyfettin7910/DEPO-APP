// Uygulama kapalıyken ~15 dakikada bir senkron + bildirim kontrolü
// (Android WorkManager). Web'de yoktur.
export 'arka_plan_io.dart' if (dart.library.js_interop) 'arka_plan_web.dart';
