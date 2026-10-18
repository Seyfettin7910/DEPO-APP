// Web'de APK kurulumu yoktur; sayfa yenilenerek güncellenir.
Future<String?> indirilmisApk(String surum) async => null;

Future<String> apkIndir(String url, String surum,
        void Function(int alinan, int? toplam) ilerleme) =>
    throw UnsupportedError('Web\'de APK indirilmez');

Future<bool> kurulumIzniVar() async => false;
Future<void> kurulumIzniIste() async {}
Future<void> apkKur(String yol) async =>
    throw UnsupportedError('Web\'de APK kurulmaz');
