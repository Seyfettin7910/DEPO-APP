import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// MainActivity.kt içindeki yerel kodla konuşur (Android PackageInstaller).
const _kanal = MethodChannel('depo_takip/guncelleme');

Future<File> _dosya(String surum) async {
  final klasor = await getTemporaryDirectory();
  return File('${klasor.path}/depo-takip-$surum.apk');
}

/// Bu sürümün APK'sı daha önce tam indirildiyse yolunu döndürür.
Future<String?> indirilmisApk(String surum) async {
  final f = await _dosya(surum);
  if (await f.exists() && await f.length() > 1000000) return f.path;
  return null;
}

/// APK'yı indirir; [ilerleme] (inen bayt, toplam bayt / bilinmiyorsa null).
Future<String> apkIndir(String url, String surum,
    void Function(int alinan, int? toplam) ilerleme) async {
  final hedef = await _dosya(surum);
  // Eski sürümlerin indirilmiş dosyalarını temizle
  try {
    for (final e in hedef.parent.listSync()) {
      if (e is File &&
          e.path.contains('depo-takip-') &&
          e.path != hedef.path) {
        e.deleteSync();
      }
    }
  } catch (_) {}

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

Future<bool> kurulumIzniVar() async =>
    (await _kanal.invokeMethod<bool>('kurulumIzniVarMi')) ?? false;

Future<void> kurulumIzniIste() => _kanal.invokeMethod('kurulumIzniIste');

Future<void> apkKur(String yol) => _kanal.invokeMethod('apkKur', {'yol': yol});
