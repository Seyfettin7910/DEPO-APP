import 'package:flutter/material.dart';

import '../services/konum_izleyici.dart';
import 'renkler.dart';

/// Montaj ve malzeme kullanımı ekranlarının üstündeki konum şeridi
/// (1.30.3'te Montaj ekranından ortak widget'a alındı): durum (aranıyor /
/// zayıf / hazır / yok) ve "konum kaydedilsin mi" anahtarı.
class KonumSeridi extends StatelessWidget {
  const KonumSeridi({
    super.key,
    required this.izleyici,
    required this.kaydet,
    required this.onChanged,
  });

  final KonumIzleyici izleyici;
  final bool kaydet;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = izleyici.gosterilen;
    final IconData ikon;
    final Color renk;
    final Color zemin;
    final String baslik;
    final String alt;
    if (izleyici.hata != null) {
      ikon = Icons.location_off;
      renk = Renkler.cikis;
      zemin = Renkler.cikisZemin;
      baslik = 'Konum yok';
      alt = izleyici.hata!;
    } else if (p == null) {
      ikon = Icons.location_searching;
      renk = Renkler.ayar;
      zemin = Renkler.ayarZemin;
      baslik = 'Konum aranıyor…';
      alt = 'Kaydet\'e basınca o andaki konum kaydedilir';
    } else if (!izleyici.gpsVar || p.accuracy > KonumIzleyici.iyiHassasiyet) {
      ikon = Icons.gps_not_fixed;
      renk = Renkler.urun;
      zemin = Renkler.urunZemin;
      baslik = izleyici.gpsVar
          ? 'Konum zayıf · ±${p.accuracy.round()} m'
          : 'Yaklaşık konum · ±${p.accuracy.round()} m';
      alt = izleyici.gpsVar
          ? 'Açık alanda iyileşir'
          : 'GPS ısınıyor, birkaç saniye sürer';
    } else {
      ikon = Icons.gps_fixed;
      renk = Renkler.okut;
      zemin = Renkler.okutZemin;
      baslik = 'Konum hazır · ±${p.accuracy.round()} m';
      alt = 'Kaydet\'e basınca bu andaki konum kaydedilir';
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: kaydet ? zemin : Renkler.ayarZemin,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(kaydet ? ikon : Icons.location_disabled,
              color: kaydet ? renk : Renkler.ayar),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kaydet ? baslik : 'Konum kaydedilmeyecek',
                    style: TextStyle(
                        color: kaydet ? renk : Renkler.ayar,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                if (kaydet) Text(alt, style: const TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
          Switch(value: kaydet, onChanged: onChanged),
        ],
      ),
    );
  }
}
