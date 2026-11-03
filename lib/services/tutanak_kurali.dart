/// 1.35.1: "Kurum içi kullanım (tutanak yok)" seçilen montajda cihazın
/// kullanıldığı birim / yer Not alanına yazılmak zorunda (tutanak yerine
/// bu kayıt tutulur). Montaj ekranı, cihaz kartındaki "Değiştir" ve
/// veritabanı aynı kuralı kullanır. Testleri: test/tutanak_kurali_test.dart.
library;

const kurumIciNotHatasi =
    'Kurum içi kullanımda, kullanıldığı birimi / yeri Not alanına yazın';

String? tutanakNotHatasi(String? tutanak, String? not) =>
    tutanak == 'kurum_ici' && (not ?? '').trim().isEmpty
        ? kurumIciNotHatasi
        : null;
