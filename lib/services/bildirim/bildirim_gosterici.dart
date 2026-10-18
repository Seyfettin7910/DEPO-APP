// Telefonun bildirim çubuğuna bildirim gönderme. Yalnızca Android'de
// çalışır; web derlemesine yerel kod karışmasın diye ayrı dosyadan seçilir.
export 'bildirim_gosterici_io.dart'
    if (dart.library.js_interop) 'bildirim_gosterici_web.dart';
