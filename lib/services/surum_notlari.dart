/// Uygulama içi "Yenilikler" ekranının notları. Her yeni sürümde listenin
/// BAŞINA o sürümün notu eklenir (yalnızca o sürümdeki yenilikler).
///
/// Yazım kuralı: her madde tek satır ve kısa; önce ekrandaki ad (kalın),
/// sonra ne değişti. Ayrıntı gerekiyorsa [NotMaddesi.detay]'a yazılır;
/// maddeye dokununca açılır. Başlıklar: Yeni · Değişen · Düzeltilen
/// (boş başlık yazılmaz). Teknik kelime (senkron, sunucu…) kullanılmaz.
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
  final List<NotMaddesi> maddeler;
}

class NotMaddesi {
  const NotMaddesi(this.ad, this.metin, [this.detay]);

  /// Ekranda görülen ad (kalın yazılır).
  final String ad;
  final String metin;

  /// "Nasıl kullanılır?": maddeye dokununca açılır.
  final String? detay;
}

const surumNotlari = <SurumNotu>[
  SurumNotu(
    surum: '1.23.0',
    tarih: '20.10.2026',
    bolumler: [
      NotBolumu('Yeni', [
        NotMaddesi(
          'Güncelleme penceresi',
          'Yeni sürüm çıkınca "Şimdi güncelle" veya "Ertele" sorulur.',
          'Ertele: ilk seferde 10 dakika, sonra 30 dakikada bir tekrar '
              'sorar. Bir işin ortasındaysanız pencere o iş bitince gelir. '
              'Zorunlu güncellemede pencere kapanmaz.',
        ),
        NotMaddesi(
          'Otomatik kurulum',
          '"Şimdi güncelle" deyince indirilir ve kendiliğinden kurulur.',
          'Wi-Fi\'de yeni sürüm önceden arka planda iner. Android 12 ve '
              'üstünde çoğu telefonda onay sorulmaz (ilk seferde bir kez '
              'sorulabilir). Uygulama kapalıyken indirme biterse "Güncelleme '
              'indi" bildirimi gelir; dokununca kurulur.',
        ),
        NotMaddesi(
          'Yeni sürüm bildirimi',
          'Uygulama kapalıyken de yeni sürüm bildirimi gelir.',
          'Kapatılamaz; Bildirim ayarlarında "Her zaman açık" görünür. '
              'Kurulumdan sonra "Uygulama güncellendi" bildirimi gelir.',
        ),
        NotMaddesi(
          'Yarım kalan iş korunur',
          'Sayım, toplu transfer, depoya giriş, sahada kullanım ve arıza '
              'işlemleri kaybolmaz.',
          'Uygulama kapanır, çöker ya da güncellenirse açılışta "Devam et / '
              'Sil" sorulur. Geri tuşunda "Taslak olarak sakla" seçilebilir. '
              'Taslaklar 7 gün saklanır; bulut simgesinin menüsünde '
              '"Yarım kalan işler".',
        ),
      ]),
      NotBolumu('Değişen', [
        NotMaddesi(
          'Yenilikler',
          'Notlar kısaldı; maddeye dokununca açıklaması açılır.',
        ),
        NotMaddesi(
          'Bulut menüsü',
          '"Güncellemeleri denetle" ve "Yarım kalan işler" eklendi.',
        ),
      ]),
    ],
  ),
  SurumNotu(
    surum: '1.22.1',
    tarih: '20.10.2026',
    bolumler: [
      NotBolumu('Bugüne kadar gelenler (özet)', [
        NotMaddesi('Seri no ile takip',
            'Her cihaz seri numarasıyla depoda, araçta ve sahada izlenir.'),
        NotMaddesi('Okut',
            'Barkod / karekod okutunca cihaz kartı açılır; koli karekodu tek '
                'seferde işlenir.'),
        NotMaddesi('Hareketler',
            'Giriş, transfer, kullanıma verme, sahada kullanım (konumlu), '
                'iade ve sayım.'),
        NotMaddesi('Arıza ve servis',
            'Arıza kaydı, servise gönderim, onarım süresi, değişim ve hurda.'),
        NotMaddesi('Raporlar',
            'Stok, kritik stok, bölge, garanti, servis, hurda ve daha '
                'fazlası; PDF ve Excel.'),
        NotMaddesi('Bildirimler',
            'Uygulama kapalıyken de gelir (Android ve web).'),
        NotMaddesi('Kurum etiketi',
            'Kurum kodu üretilir, bilgisayardan basılır, telefonla '
                'doğrulanır.'),
        NotMaddesi('Her yerde',
            'Android, iPhone (web) ve bilgisayar; internetsiz de çalışır.'),
      ]),
      NotBolumu('Yeni', [
        NotMaddesi('Seri no kopyalama',
            'Depo hareket geçmişinde kopyala simgesi ya da satıra uzun basma.'),
        NotMaddesi(
          'Yenilikler ekranı',
          'Güncellemeden sonra neler değiştiğini gösterir.',
          'Sonradan bulut simgesinin menüsünden açılabilir.',
        ),
      ]),
    ],
  ),
];
