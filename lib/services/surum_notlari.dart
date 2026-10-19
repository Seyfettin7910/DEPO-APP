/// Uygulama içi "Yenilikler" ekranının notları. Her yeni sürümde listenin
/// BAŞINA o sürümün notu eklenir (yalnızca o sürümdeki yenilikler).
class SurumNotu {
  const SurumNotu({
    required this.surum,
    required this.tarih,
    required this.bolumler,
  });

  final String surum;
  final String tarih;
  final List<NotBolumu> bolumler;
}

class NotBolumu {
  const NotBolumu(this.baslik, this.maddeler);
  final String baslik;
  final List<String> maddeler;
}

const surumNotlari = <SurumNotu>[
  SurumNotu(
    surum: '1.22.1',
    tarih: '20.10.2026',
    bolumler: [
      NotBolumu('Bugüne kadar gelenler (kısa özet)', [
        'Seri no ile takip: her cihaz seri numarasıyla izlenir; depo, araç '
            '(seyyar depo) ve saha takibi yapılır.',
        'Okut: barkod / karekod okutulunca cihaz kartı açılır. Koli karekodu '
            'okutulunca içindeki tüm seri numaraları tek seferde işlenir.',
        'Hareketler: depoya giriş, transfer, kullanıma verme, sahada kullanım '
            '(konum ve mahalle kaydıyla), iade ve sayım.',
        'Arıza ve servis: arıza kaydı, servise gönderim, onarım süresi, '
            'değişim ve hurda takibi.',
        'Raporlar: stok, kritik stok, bölge, garanti, alımlar, arıza / servis, '
            'hurda, hareket geçmişi, giriş kayıtları ve etiket durumu; PDF ve '
            'Excel olarak.',
        'Bildirimler: uygulama kapalıyken de gelir (Android ve iPhone / web). '
            'Kritik stok, arıza, servis gecikmesi, cihaz geldi, günlük özet ve '
            'daha fazlası.',
        'Kurum etiketi: cihazlara kurum kodu üretilir, etiketler bilgisayardan '
            'basılır, yapıştırma telefonla doğrulanır.',
        'Kamera: dokununca netleme, yakınlaştırma ve uzaktan okuma.',
        'Her yerde: Android uygulaması, iPhone\'da ana ekrandan web sürümü ve '
            'bilgisayar. İnternetsizken de çalışır, bağlantı gelince eşitlenir.',
      ]),
      NotBolumu('Bu sürümde', [
        'Depo hareket geçmişinde seri numarası kopyalama: satırdaki kopyala '
            'simgesine dokunun veya satıra uzun basın.',
        '"Yenilikler" ekranı: güncellemeden sonra ilk açılışta neler '
            'değiştiğini gösterir. Sonradan bulut (senkron) simgesinin '
            'menüsünden açılabilir.',
      ]),
    ],
  ),
];
