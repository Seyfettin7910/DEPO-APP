// Web'de APK kurulumu yoktur; sayfa yenilenerek güncellenir.
Future<String?> indirilmisApk(String surum) async => null;

Future<bool> indiriliyorMu(String surum) async => false;

Future<String> apkIndir(String url, String surum,
        void Function(int alinan, int? toplam) ilerleme,
        {bool sadeceWifi = false}) =>
    throw UnsupportedError('Web\'de APK indirilmez');

Future<bool> kurulumIzniVar() async => false;
Future<void> kurulumIzniIste() async {}
Future<void> apkKur(String yol) async =>
    throw UnsupportedError('Web\'de APK kurulmaz');

Future<void> duraklamisIseIptal(String surum) async {}
Future<bool> bildirimdenKurulum() async => false;

Stream<Map<String, dynamic>> get kurulumOlaylari => const Stream.empty();
Future<bool> onayEkraniniAc() async => false;
Future<bool> xiaomiMi() async => false;
Future<void> izinEkraniniAc() async {}
Future<void> apkSil(String yol) async {}
