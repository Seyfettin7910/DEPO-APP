import 'package:depo_app/services/tutanak_kurali.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Kurum içi kullanımda not zorunlu', () {
    expect(tutanakNotHatasi('kurum_ici', null), kurumIciNotHatasi);
    expect(tutanakNotHatasi('kurum_ici', ''), kurumIciNotHatasi);
    expect(tutanakNotHatasi('kurum_ici', '   '), kurumIciNotHatasi);
    expect(tutanakNotHatasi('kurum_ici', 'FEN İŞLERİ 2. KAT'), isNull);
  });

  test('Diğer tutanak durumlarında not isteğe bağlı', () {
    for (final t in ['alindi', 'alinacak', null]) {
      expect(tutanakNotHatasi(t, null), isNull);
      expect(tutanakNotHatasi(t, ''), isNull);
    }
  });
}
