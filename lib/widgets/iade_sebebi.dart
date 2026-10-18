import 'package:flutter/material.dart';

/// Cihaz depoya geri alınırken seçilen sebepler.
const iadeSebepleri = [
  'Arıza',
  'Değişim',
  'İşi bitti / ihtiyaç kalmadı',
  'Yanlış kayıt',
  'Diğer',
];

/// Sahadan geri almada ek seçenek: cihaz alınır ve doğrudan hurdaya ayrılır.
const omruDolduSebebi = 'Ömrünü doldurdu (hurda)';

/// Geri alma sebebi seçimi (çip listesi). "Diğer" seçilirse açıklama
/// notta yazılmalıdır; bunu çağıran pencere denetler.
/// "Arıza" seçilince altında arızanın türü (tamir / değişim) sorulur.
class IadeSebebiSecici extends StatelessWidget {
  const IadeSebebiSecici({
    super.key,
    required this.secili,
    required this.onSecildi,
    this.zorunlu = true,
    this.hurdaSecenegi = false,
    this.arizaKarari,
    this.onArizaKarari,
  });

  final String? secili;
  final ValueChanged<String?> onSecildi;
  final bool zorunlu;

  /// "Ömrünü doldurdu (hurda)" seçeneği gösterilsin mi (sahadan geri alma).
  final bool hurdaSecenegi;

  /// Arıza türü: tamir | degisim. [onArizaKarari] verilmezse sorulmaz.
  final String? arizaKarari;
  final ValueChanged<String?>? onArizaKarari;

  @override
  Widget build(BuildContext context) {
    final sebepler = [...iadeSebepleri, if (hurdaSecenegi) omruDolduSebebi];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(zorunlu ? 'Geri alma sebebi' : 'Sebep (opsiyonel)',
              style: Theme.of(context).textTheme.labelLarge),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final s in sebepler)
              ChoiceChip(
                label: Text(s),
                selected: secili == s,
                onSelected: (sec) => onSecildi(sec ? s : null),
              ),
          ],
        ),
        if (secili == 'Arıza' && onArizaKarari != null)
          ArizaKarariSecici(secili: arizaKarari, onSecildi: onArizaKarari!),
        if (secili == omruDolduSebebi)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Cihaz seçilen depoya alınır ve hemen hurdaya ayrılır; '
              'stokta görünmez.',
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

/// Arızanın türü: tamir edilebilir mi, değişim mi gerekiyor?
class ArizaKarariSecici extends StatelessWidget {
  const ArizaKarariSecici({
    super.key,
    required this.secili,
    required this.onSecildi,
  });

  final String? secili; // tamir | degisim
  final ValueChanged<String?> onSecildi;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text('Arıza durumu',
              style: Theme.of(context).textTheme.labelLarge),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            ChoiceChip(
              avatar: const Icon(Icons.build_outlined, size: 18),
              label: const Text('Tamir gerekli'),
              selected: secili == 'tamir',
              onSelected: (s) => onSecildi(s ? 'tamir' : null),
            ),
            ChoiceChip(
              avatar: const Icon(Icons.sync_problem, size: 18),
              label: const Text('Tamiri mümkün değil, değişim gerekli'),
              selected: secili == 'degisim',
              onSelected: (s) => onSecildi(s ? 'degisim' : null),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Arızalı cihaz depoda bekler; onarılana kadar transfer edilemez, '
            'kullanıma verilemez ve sahada kullanılamaz.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// Seçimi denetler; sorun varsa hata metnini döndürür.
String? iadeSebebiHatasi(String? sebep, String not_,
    {bool zorunlu = true, String? arizaKarari, bool arizaSor = false}) {
  if (zorunlu && sebep == null) return 'Geri alma sebebini seçin';
  if (sebep == 'Diğer' && not_.trim().isEmpty) {
    return '"Diğer" için not alanına açıklama yazın';
  }
  if (arizaSor && sebep == 'Arıza' && arizaKarari == null) {
    return 'Arıza durumunu seçin (tamir / değişim)';
  }
  return null;
}
