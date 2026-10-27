import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MainActivity.kt içindeki yerel kodla konuşur (Android DownloadManager ve
/// PackageInstaller).
///
/// İndirme Android'in kendi indirme yöneticisine verilir: uygulama arka plana
/// düşse ya da kapatılsa da indirme sürer, bildirim çubuğunda ilerleme
/// görünür. Uygulama yeniden açıldığında yarım kalan indirme kaldığı yerden
/// izlenir (indirme no'su telefonda saklanır).
const _kanal = MethodChannel('depo_takip/guncelleme');

const _anahtarId = 'guncelleme_indirme_id';
const _anahtarSurum = 'guncelleme_indirme_surum';

String _ad(String surum) => 'Depo-Yonetim-Sistemi-$surum.apk';

Future<SharedPreferences?> _prefs() async {
  try {
    return await SharedPreferences.getInstance();
  } catch (_) {
    return null;
  }
}

Future<Directory> _klasor() async {
  try {
    final y = await _kanal.invokeMethod<String>('indirmeKlasoru');
    if (y != null) return Directory(y);
  } catch (_) {}
  return getTemporaryDirectory();
}

Future<File> _dosya(String surum) async =>
    File('${(await _klasor()).path}/${_ad(surum)}');

/// İndirme yöneticisindeki kaydın durumu; yoksa null.
/// durum: bekliyor | calisiyor | duraklatildi | bitti | hata | yok
Future<Map<String, dynamic>?> _durum(int id) async {
  try {
    final d = await _kanal
        .invokeMapMethod<String, dynamic>('indirmeDurumu', {'id': id});
    if (d == null) return null;
    // Tamamlandı görünüyor ama dosya silinmişse yok say
    if (d['durum'] == 'bitti') {
      final yol = d['yol'] as String?;
      if (yol == null || !await File(yol).exists()) return {'durum': 'yok'};
    }
    return d;
  } catch (_) {
    return null;
  }
}

/// Bu sürüm için kayıtlı indirme (id, durum); başka sürümse null.
Future<(int, Map<String, dynamic>?)?> _kayitliIndirme(String surum) async {
  final p = await _prefs();
  final id = p?.getInt(_anahtarId);
  if (id == null || p?.getString(_anahtarSurum) != surum) return null;
  return (id, await _durum(id));
}

bool _suruyor(Object? durum) =>
    durum == 'bekliyor' || durum == 'calisiyor' || durum == 'duraklatildi';

Future<void> _kaydiSil() async {
  final p = await _prefs();
  await p?.remove(_anahtarId);
  await p?.remove(_anahtarSurum);
}

/// Bu sürümün APK'sı tam indirildiyse yolunu döndürür.
Future<String?> indirilmisApk(String surum) async {
  final k = await _kayitliIndirme(surum);
  if (k != null) {
    final d = k.$2;
    if (d?['durum'] == 'bitti') return d!['yol'] as String;
    if (_suruyor(d?['durum'])) return null; // hâlâ iniyor
  }
  // Eski yöntemle (uygulama içinden) indirilmiş dosya
  final f = await _dosya(surum);
  if (await f.exists() && await f.length() > 1000000) return f.path;
  return null;
}

/// Bu sürüm için arka planda süren bir indirme var mı?
Future<bool> indiriliyorMu(String surum) async {
  final k = await _kayitliIndirme(surum);
  return k != null && _suruyor(k.$2?['durum']);
}

Future<void> _eskileriTemizle(String surum) async {
  final ad = _ad(surum);
  for (final klasor in {await _klasor(), await getTemporaryDirectory()}) {
    try {
      for (final e in klasor.listSync()) {
        final dosyaAdi = e.uri.pathSegments.last;
        if (e is File &&
            (dosyaAdi.startsWith('depo-takip-') ||
                dosyaAdi.startsWith('Depo-Otomasyon-Sistemi-') ||
                dosyaAdi.startsWith('Depo-Yonetim-Sistemi-')) &&
            dosyaAdi != ad) {
          e.deleteSync();
        }
      }
    } catch (_) {}
  }
}

/// APK'yı indirir; [ilerleme] (inen bayt, toplam bayt / bilinmiyorsa null).
/// [sadeceWifi]: mobil veriye geçilirse indirme duraklar, Wi-Fi gelince sürer.
Future<String> apkIndir(
    String url, String surum, void Function(int alinan, int? toplam) ilerleme,
    {bool sadeceWifi = false}) async {
  final p = await _prefs();
  int? id;

  // Bu sürüm için süren / bitmiş indirme varsa onu kullan
  final k = await _kayitliIndirme(surum);
  if (k != null) {
    if (k.$2?['durum'] == 'bitti') return k.$2!['yol'] as String;
    if (_suruyor(k.$2?['durum'])) id = k.$1;
  }

  if (id == null) {
    // Başka sürümün yarım indirmesi varsa iptal et
    final eski = p?.getInt(_anahtarId);
    if (eski != null) {
      try {
        await _kanal.invokeMethod('indirmeIptal', {'id': eski});
      } catch (_) {}
      await _kaydiSil();
    }
    await _eskileriTemizle(surum);
    try {
      id = await _kanal.invokeMethod<int>('indirmeBaslat', {
        'url': url,
        'ad': _ad(surum),
        'baslik': 'DEPO YÖNETİM SİSTEMİ $surum',
        'sadeceWifi': sadeceWifi,
      });
    } catch (_) {
      id = null;
    }
    // İndirme yöneticisi kapalıysa (bazı telefonlarda devre dışı
    // bırakılabiliyor) uygulama içinden indir.
    if (id == null) return _dogrudanIndir(url, surum, ilerleme);
    await p?.setInt(_anahtarId, id);
    await p?.setString(_anahtarSurum, surum);
  }

  while (true) {
    final d = await _durum(id);
    final durum = d?['durum'];
    if (durum == 'bitti') return d!['yol'] as String;
    if (durum == 'hata') {
      await _kaydiSil();
      throw HttpException('İndirme hatası (${d?['sebep']})');
    }
    if (d == null || durum == 'yok') {
      await _kaydiSil();
      throw const HttpException('İndirme iptal edildi');
    }
    final alinan = (d['alinan'] as num?)?.toInt() ?? 0;
    final toplam = (d['toplam'] as num?)?.toInt() ?? -1;
    ilerleme(alinan < 0 ? 0 : alinan, toplam > 0 ? toplam : null);
    await Future.delayed(const Duration(milliseconds: 700));
  }
}

/// Yedek yol: indirme yöneticisi kullanılamazsa uygulama içinden indirir
/// (bu yöntemde uygulama kapatılırsa indirme durur).
Future<String> _dogrudanIndir(String url, String surum,
    void Function(int alinan, int? toplam) ilerleme) async {
  final hedef = await _dosya(surum);
  final gecici = File('${hedef.path}.part');
  final istemci = http.Client();
  try {
    final yanit = await istemci.send(http.Request('GET', Uri.parse(url)));
    if (yanit.statusCode != 200) {
      throw HttpException('İndirme hatası (${yanit.statusCode})');
    }
    final toplam = yanit.contentLength;
    var alinan = 0;
    final yazici = gecici.openWrite();
    await for (final parca in yanit.stream) {
      yazici.add(parca);
      alinan += parca.length;
      ilerleme(alinan, toplam == null || toplam == 0 ? null : toplam);
    }
    await yazici.close();
    if (await hedef.exists()) await hedef.delete();
    await gecici.rename(hedef.path);
    return hedef.path;
  } finally {
    istemci.close();
  }
}

/// Bu sürümün indirmesi Wi-Fi beklerken duraklamışsa iptal eder; kullanıcı
/// şimdi (mobil veriyle) indirmek istediğinde yeniden başlatılır.
Future<void> duraklamisIseIptal(String surum) async {
  final k = await _kayitliIndirme(surum);
  if (k == null || k.$2?['durum'] != 'duraklatildi') return;
  try {
    await _kanal.invokeMethod('indirmeIptal', {'id': k.$1});
  } catch (_) {}
  await _kaydiSil();
}

/// Uygulama "Güncelleme indi · kurmak için dokun" bildirimiyle mi açıldı?
/// (Bir kez true döner.)
Future<bool> bildirimdenKurulum() async {
  try {
    return await _kanal.invokeMethod<bool>('bildirimdenKurulum') ?? false;
  } catch (_) {
    return false;
  }
}

Future<bool> kurulumIzniVar() async =>
    (await _kanal.invokeMethod<bool>('kurulumIzniVarMi')) ?? false;

Future<void> kurulumIzniIste() => _kanal.invokeMethod('kurulumIzniIste');

Future<void> apkKur(String yol) => _kanal.invokeMethod('apkKur', {'yol': yol});

// ---------------------------------------------------------------------
// Kurulum sonucu ve onay ekranı
// ---------------------------------------------------------------------

final _olaylar = StreamController<Map<String, dynamic>>.broadcast();
bool _dinleniyor = false;

/// Kurulumun sonucu: {durum: onay_bekleniyor | basarili | iptal | yer_yok |
/// bozuk | uyumsuz | cakisma | engellendi | hata, mesaj}.
Stream<Map<String, dynamic>> get kurulumOlaylari {
  if (!_dinleniyor) {
    _dinleniyor = true;
    _kanal.setMethodCallHandler((call) async {
      if (call.method == 'kurulumDurumu' && call.arguments is Map) {
        _olaylar.add(Map<String, dynamic>.from(call.arguments as Map));
      }
      return null;
    });
  }
  return _olaylar.stream;
}

/// Bekleyen sistem onay ekranını uygulamanın ekranından yeniden açar.
Future<bool> onayEkraniniAc() async {
  try {
    return await _kanal.invokeMethod<bool>('onayEkraniniAc') ?? false;
  } catch (_) {
    return false;
  }
}

Future<bool> xiaomiMi() async {
  try {
    return await _kanal.invokeMethod<bool>('xiaomiMi') ?? false;
  } catch (_) {
    return false;
  }
}

/// Xiaomi'de "Diğer izinler" ekranı (arka planda açılır pencere izni).
Future<void> izinEkraniniAc() async {
  try {
    await _kanal.invokeMethod('izinEkraniniAc');
  } catch (_) {}
}

/// Bozuk çıkan indirmeyi siler (yeniden indirilsin).
Future<void> apkSil(String yol) async {
  try {
    await File(yol).delete();
  } catch (_) {}
  await _kaydiSil();
}
