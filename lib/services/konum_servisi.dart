import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

/// Tek seferlik konum okuması sonucu.
class KonumSonucu {
  const KonumSonucu.basarili(this.enlem, this.boylam, this.hassasiyet)
      : hata = null;
  const KonumSonucu.hatali(this.hata)
      : enlem = null,
        boylam = null,
        hassasiyet = null;

  final double? enlem;
  final double? boylam;

  /// Metre cinsinden tahmini hata payı.
  final double? hassasiyet;
  final String? hata;

  bool get basarili => enlem != null && boylam != null;
}

/// Cihazın kullanıldığı / monte edildiği yerin konumunu alır. Yalnızca
/// "Sahada kullanıldı" anında, bir kez okunur; kişi takibi yapılmaz.
class KonumServisi {
  static Future<KonumSonucu> konumAl() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const KonumSonucu.hatali('Telefonun konum (GPS) özelliği kapalı');
      }
      var izin = await Geolocator.checkPermission();
      if (izin == LocationPermission.denied) {
        izin = await Geolocator.requestPermission();
      }
      if (izin == LocationPermission.denied) {
        return const KonumSonucu.hatali('Konum izni verilmedi');
      }
      if (izin == LocationPermission.deniedForever) {
        return const KonumSonucu.hatali(
            'Konum izni kapalı (telefon ayarlarından açılabilir)');
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return KonumSonucu.basarili(p.latitude, p.longitude, p.accuracy);
    } catch (e) {
      return KonumSonucu.hatali('Konum alınamadı');
    }
  }

  static String koordinat(double enlem, double boylam) =>
      '${enlem.toStringAsFixed(6)}, ${boylam.toStringAsFixed(6)}';

  static String haritaLinki(double enlem, double boylam) =>
      'https://www.google.com/maps/search/?api=1&query='
      '${enlem.toStringAsFixed(6)},${boylam.toStringAsFixed(6)}';

  static Future<void> haritadaAc(double enlem, double boylam) => launchUrl(
        Uri.parse(haritaLinki(enlem, boylam)),
        mode: LaunchMode.externalApplication,
      );
}
