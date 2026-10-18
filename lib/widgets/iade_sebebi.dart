import 'package:flutter/material.dart';

/// Cihaz depoya geri alınırken seçilen sebepler.
const iadeSebepleri = [
  'Arıza',
  'Değişim',
  'İşi bitti / ihtiyaç kalmadı',
  'Yanlış kayıt',
  'Diğer',
];

/// Geri alma sebebi seçimi (çip listesi). "Diğer" seçilirse açıklama
/// notta yazılmalıdır; bunu çağıran pencere denetler.
class IadeSebebiSecici extends StatelessWidget {
  const IadeSebebiSecici({
    super.key,
    required this.secili,
    required this.onSecildi,
    this.zorunlu = true,
  });

  final String? secili;
  final ValueChanged<String?> onSecildi;
  final bool zorunlu;

  @override
  Widget build(BuildContext context) {
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
            for (final s in iadeSebepleri)
              ChoiceChip(
                label: Text(s),
                selected: secili == s,
                onSelected: (sec) => onSecildi(sec ? s : null),
              ),
          ],
        ),
      ],
    );
  }
}

/// Seçimi denetler; sorun varsa hata metnini döndürür.
String? iadeSebebiHatasi(String? sebep, String not_, {bool zorunlu = true}) {
  if (zorunlu && sebep == null) return 'Geri alma sebebini seçin';
  if (sebep == 'Diğer' && not_.trim().isEmpty) {
    return '"Diğer" için not alanına açıklama yazın';
  }
  return null;
}
