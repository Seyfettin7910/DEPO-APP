import 'package:flutter/foundation.dart' show ValueNotifier;

// Web'de bildirim çubuğu yok; bildirimler uygulama içindeki zilde görünür.
Future<void> bildirimGoster(int id, String baslik, String govde,
    {String? yuk}) async {}
Future<bool> bildirimIzniIste() async => false;
Future<void> pilAyariniAc() async {}
bool get sistemBildirimiVar => false;
final bildirimDokunusu = ValueNotifier<String?>(null);
Future<void> bildirimDokunusunuHazirla() async {}
