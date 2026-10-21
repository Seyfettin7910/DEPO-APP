import 'package:flutter/services.dart';

import '../services/bolge_adi.dart' show trBuyuk;

/// 1.29.1: elle yazılan bütün metin alanları BÜYÜK HARF.
///
/// - [metinBuyuk]: ad, açıklama, not, yer… Türkçe kuralı (i → İ, ı → I).
/// - [kodBuyuk]: seri no, barkod, plaka, kurum kodu… Latin kuralı (i → I);
///   kodlarda Türkçe "İ" olmaz.
///
/// Alanlarda klavye de büyük harfle açılır
/// (`textCapitalization: TextCapitalization.characters`); bu biçimleyici
/// yapıştırılan / küçük kalan harfleri düzeltir. E-posta, şifre ve sayı
/// alanlarına uygulanmaz.
class BuyukHarfBicimi extends TextInputFormatter {
  const BuyukHarfBicimi({this.latin = false});

  final bool latin;

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue eski, TextEditingValue yeni) {
    final t = latin ? yeni.text.toUpperCase() : trBuyuk(yeni.text);
    if (t == yeni.text) return yeni;
    if (t.length == yeni.text.length) return yeni.copyWith(text: t);
    return TextEditingValue(
        text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}

const metinBuyuk = <TextInputFormatter>[BuyukHarfBicimi()];
const kodBuyuk = <TextInputFormatter>[BuyukHarfBicimi(latin: true)];
