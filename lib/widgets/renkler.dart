import 'package:flutter/material.dart';

/// Bölüm renkleri: her bölümün simgesi kendi renginde görünür, böylece
/// simgeler hem daha okunur hem de bir bakışta ayırt edilir.
class Renkler {
  Renkler._();

  static const depo = Color(0xFF1E66C5);
  static const depoZemin = Color(0xFFDCE8F8);
  static const urun = Color(0xFFB35400);
  static const urunZemin = Color(0xFFFBE6D2);
  static const okut = Color(0xFF1E7B3A);
  static const okutZemin = Color(0xFFD5EEDB);
  static const ara = Color(0xFF7B3FB5);
  static const araZemin = Color(0xFFECE1F7);
  static const rapor = Color(0xFF00838F);
  static const raporZemin = Color(0xFFD2EEF0);
  static const ayar = Color(0xFF475569);
  static const ayarZemin = Color(0xFFE2E8F0);
  static const cikis = Color(0xFFC62828);
  static const cikisZemin = Color(0xFFFBDADA);
  static const montaj = Color(0xFFC2185B);
  static const montajZemin = Color(0xFFFADCE8);
  static const zil = Color(0xFFD97706);
  static const zilZemin = Color(0xFFFDECC8);
}

/// Yuvarlatılmış renkli kutu içinde simge (ayar satırları, hızlı işlemler).
class RenkliSimge extends StatelessWidget {
  const RenkliSimge(
    this.ikon, {
    super.key,
    required this.renk,
    required this.zemin,
    this.boyut = 40,
    this.dolu = false,
  });

  final IconData ikon;
  final Color renk;
  final Color zemin;
  final double boyut;

  /// true: kutu simge renginde, simge beyaz.
  final bool dolu;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: boyut,
      height: boyut,
      decoration: BoxDecoration(
        color: dolu ? renk : zemin,
        borderRadius: BorderRadius.circular(boyut * 0.3),
      ),
      child: Icon(ikon, color: dolu ? Colors.white : renk, size: boyut * 0.6),
    );
  }
}
