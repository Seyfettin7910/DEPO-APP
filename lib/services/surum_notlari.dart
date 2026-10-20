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
    surum: '1.24.3',
    tarih: '20.10.2026',
    bolumler: [
      NotBolumu('Düzeltilen', [
        NotMaddesi(
          'Veritabanı hatası',
          'Uygulamaya dönünce çıkan "database_closed" ekran hatası giderildi.',
          'Arka plandaki bildirim kontrolü veritabanını kapatıyordu; artık '
              'kapatmıyor. Bir şekilde kapanırsa uygulama kendiliğinden '
              'yeniden açar. Ekranlar bir hata olursa tamamen bozulmaz.',
        ),
      ]),
    ],
  ),
  SurumNotu(
    surum: '1.24.2',
    tarih: '20.10.2026',
    bolumler: [
      NotBolumu('Düzeltilen', [
        NotMaddesi(
          'Otomatik kurulum',
          'Kurulum onay ekranı artık Xiaomi / Redmi telefonlarda da açılıyor.',
          'Onay ekranı açılamazsa pencerede "Onay ekranını aç" düğmesi '
              'çıkar; Xiaomi\'de ayrıca "İzni aç" ile gerekli izin ekranı '
              'açılır. Kurulum sonucu (iptal, yer yok, dosya bozuk…) '
              'pencerede hemen yazılır. Normal güncellemede bu durumda da '
              '"Ertele" görünür.',
        ),
      ]),
      NotBolumu('Değişen', [
        NotMaddesi(
          'Yeni sürüm bildirimi',
          'Daha hızlı geliyor: telefonda ~15 dk, web / iPhone\'da birkaç dakika.',
          'Bildirim ayarlarında "Yeni sürüm · her zaman açık" artık web\'de '
              'de görünür.',
        ),
      ]),
    ],
  ),
  SurumNotu(
    surum: '1.24.1',
    tarih: '20.10.2026',
    bolumler: [
      NotBolumu('Yeni', [
        NotMaddesi('Kaydırarak geçiş',
            'Kamerada yana kaydırınca Barkod ⇄ Karekod değişir.'),
        NotMaddesi(
          'Yok sayılan kod ipucu',
          'Okunmayan kod çerçevenin üstünde nedeniyle kısaca görünür.',
          'Örn. "Yok sayıldı: 30-16-9D-4E-93-F2 (MAC adresi)". Yanlış '
              'barkoda doğrulttuğunuz hemen anlaşılır.',
        ),
      ]),
      NotBolumu('Düzeltilen', [
        NotMaddesi(
          'Kamera okuma',
          'Küçük ve sık çizgili barkodlar artık hızlı okunuyor.',
          'Kayıtlı kod, kurum etiketi ve koli karekodu ilk okumada; '
              'bilinmeyen kod ikinci okumada kabul edilir. Kamera saniyede '
              'daha çok dener. "S/N:" öneki ve sondaki "EU/3.0" gibi ek '
              'bilgiler atılır.',
        ),
      ]),
    ],
  ),
  SurumNotu(
    surum: '1.24.0',
    tarih: '20.10.2026',
    bolumler: [
      NotBolumu('Yeni', [
        NotMaddesi(
          'Malzemeler',
          'Kablo, adaptör gibi seri nosuz ürünler adet, metre, paket, top ya '
              'da kutu ile takip edilir.',
          'Ürünler → + → "Miktarla" seçin; birim ve fabrika barkodu '
              'girilebilir. Depo → İşlemler: Malzeme girişi, Araca Yükle, '
              'transfer, iade, Montaj / Kullanıldı. Okut ekranında fabrika '
              'barkodu okutulunca da bu işlemler açılır. Tanımsız barkod bir '
              'kez malzemeye bağlanır.',
        ),
        NotMaddesi(
          'Kullanılan malzemeler',
          'Montaj penceresinde araçtaki malzemeler hazır gelir; +/- ile girilir.',
          'İsteğe bağlıdır. Girilen miktar araç stoğundan düşer ve Kullanım '
              'Raporu\'nda görünür.',
        ),
        NotMaddesi(
          'Tutanak',
          'Montajda "Alındı / Alınacak / Kurum içi kullanım" seçilir.',
          'Sonradan cihaz kartındaki "Tutanak alındı" ile güncellenir. Ara '
              'ekranında ve Kullanım Raporu\'nda görünür. Eski montajlar '
              '"Belirtilmemiş".',
        ),
        NotMaddesi('Araçlar sekmesi',
            'Depolar ekranında depolar ve araçlar ayrı sekmede.'),
        NotMaddesi('Malzeme sayımı',
            'Sayımdaki "Malzeme" sekmesinde sayılan miktar girilir; raporda '
                'fark görünür.'),
      ]),
      NotBolumu('Değişen', [
        NotMaddesi(
          'İsimler',
          '"Kullanıma ver" → Araca Yükle, "Sahada kullanıldı" → Montaj / '
              'Kullanıldı.',
          'Cihaz durumu: "Montaj Yapıldı / Kullanıldı". Rapor: "Kullanım '
              'Raporu – Montajı Yapılanlar".',
        ),
        NotMaddesi('Kritik stok',
            'Malzemelerde minimum miktara göre uyarır.'),
        NotMaddesi(
          'Kamera okuma',
          'Çerçeve küçüldü; kod çerçevede kısa süre sabit durunca okunur.',
          'Kamera açılınca ilk anda okuma yapılmaz. Birden çok kod varsa '
              'ortadaki alınır. Web adresi, Wi-Fi, MAC adresi ve kutu '
              'üstündeki ürün barkodları yok sayılır. Çerçevenin altındaki '
              'çubuk dolunca okunur; kayıtlı kodlar hızlı, bilinmeyen kodlar '
              'biraz daha geç okunur.',
        ),
      ]),
    ],
  ),
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
