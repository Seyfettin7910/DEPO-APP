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
    surum: '1.30.0',
    tarih: '22.10.2026',
    bolumler: [
      NotBolumu('Yeni', [
        NotMaddesi(
          'Ürün birleştirme',
          'Aynı ürün iki kez açıldıysa biri diğerine katılır.',
          'Ürünler\'de ürüne basılı tutun → "Başka ürünle birleştir" → kalacak '
              'ürünü seçin (benzer adlar en üstte). Cihazlar, hareketler ve '
              'servis kayıtları kalan ürüne taşınır, hiçbir hareket silinmez. '
              'Ad düzeltirken aynı adda ürün çıkarsa "Birleştir" de seçilebilir. '
              'Geri alınamaz.',
        ),
      ]),
    ],
  ),
  SurumNotu(
    surum: '1.29.3',
    tarih: '22.10.2026',
    bolumler: [
      NotBolumu('Yeni', [
        NotMaddesi(
          'Benzer ürün',
          'Yeni ürünün adı var olan bir ürüne benziyorsa seçim ekranı çıkar.',
          '"Hikvision 7104…" yazınca "HİKVİSİON 7104…" bulunur: aynı ürünse '
              'listeden seçin, cihazlar tek ürün altında toplanır. Değilse '
              '"Hiçbiri değil, yeni ürün oluştur". Ad düzeltirken aynı adda '
              'başka ürün varsa uyarır.',
        ),
      ]),
      NotBolumu('Değişen', [
        NotMaddesi(
          'Ürün / model adı',
          'Yabancı harflerle büyük harf: hikvision → HIKVISION.',
          'Türkçe İ gereken yerde klavyeden İ yazın (ELEKTRİK). Eski '
              '"HİKVİSİON" gibi adlar ürünü açıp düzeltilebilir.',
        ),
        NotMaddesi(
          'Kamera',
          'Karekod modunda da "15-25 cm uzakta tutun" görünür; 1x · 2x · 3x inceldi.',
        ),
      ]),
    ],
  ),
  SurumNotu(
    surum: '1.29.2',
    tarih: '22.10.2026',
    bolumler: [
      NotBolumu('Yeni', [
        NotMaddesi(
          'Yazdırma önizlemesi',
          'Etiketler yazdırılmadan önce büyütülerek kontrol edilir.',
          'İki parmakla 5 kata kadar büyütün, çift dokunuşla büyütüp geri '
              'alın. Altta "Yazdır" ve "PDF paylaş". Etiket basımı, hizalama '
              'test sayfası ve örnek etiketlerde.',
        ),
      ]),
      NotBolumu('Değişen', [
        NotMaddesi(
          'Kamera ekranı',
          'Barkod / Karekod düğmesi kalktı; geçiş yana kaydırarak.',
          'Üstte hangi yöne geçileceği yazar ("Karekod için yana '
              'kaydırın"). Sayaç sol üstte: 100/100, 100/99… Altta yalnız '
              '"15-25 cm uzakta tutun"; 1x · 2x · 3x küçüldü.',
        ),
        NotMaddesi(
          'Yazıdan da oku',
          '3 sn barkod okunmazsa başlar; barkod okunursa her zaman barkod geçer.',
        ),
      ]),
      NotBolumu('Düzeltilen', [
        NotMaddesi(
          'Alttaki düğmeler',
          'Telefonun geri / ana ekran tuşlarının arkasında kalmıyor.',
        ),
        NotMaddesi(
          'Etiket kağıdı ve hizalama',
          'Tek "Kaydet" düğmesi; ölçü kutuları tam genişlik.',
        ),
      ]),
    ],
  ),
  SurumNotu(
    surum: '1.29.1',
    tarih: '21.10.2026',
    bolumler: [
      NotBolumu('Değişen', [
        NotMaddesi(
          'Büyük harf',
          'Yazılan ve kendiliğinden dolan bütün yazılar BÜYÜK HARF.',
          'Ad, açıklama, not, "Nerede kullanıldı?", il / ilçe / mahalle, '
              'firma, plaka, seri no… Klavye büyük harfle açılır. Eski '
              'kayıtlar da büyük harfe çevrildi. E-posta ve şifre değişmez.',
        ),
      ]),
    ],
  ),
  SurumNotu(
    surum: '1.29.0',
    tarih: '21.10.2026',
    bolumler: [
      NotBolumu('Yeni', [
        NotMaddesi(
          'Yazıdan da oku',
          'Barkod okunmazsa etiketteki S/N satırı yazıdan okunur (Android).',
          'Barkod 2,5 saniye okunmazsa çerçevenin üstünde "Yazı da '
              'okunuyor" yazar; S/N satırını çerçeveye alın. Kayıtlı cihazsa '
              'doğrudan açılır, değilse "Doğru mu?" diye sorulur. Ayarlar → '
              '"Yazıdan da oku" ile kapatılabilir.',
        ),
      ]),
      NotBolumu('Değişen', [
        NotMaddesi(
          'Kamera pil tasarrufu',
          '15 sn kod görmezse yavaşlar, 30 sn sonra durur; dokununca açılır.',
          'Kamera durunca fener de söner. Kod görünce ya da ekrana dokununca '
              'kaldığı yerden normal hızda devam eder.',
        ),
        NotMaddesi(
          'Telefonlar arası kayıtlar',
          'Başka telefonda yapılan kayıt birkaç saniyede gelir, daha az pil.',
          'Uygulama açılınca ve internet gelince ayrıca tam kontrol yapılır.',
        ),
      ]),
    ],
  ),
  SurumNotu(
    surum: '1.28.0',
    tarih: '21.10.2026',
    bolumler: [
      NotBolumu('Yeni', [
        NotMaddesi(
          'Nerede kullanıldı?',
          'Montajda konumdan kendiliğinden dolar; elle yazılan değişmez.',
          'Önce 15 m içinde daha önce yazılmış yer adı gelir (konum en fazla '
              '±15 m iken); yoksa "SUSURLUK KULAT" gibi ilçe + mahalle. '
              'Yakında birden çok eski ad varsa altında seçilebilir.',
        ),
        NotMaddesi(
          'İnternetsiz montaj',
          'Konum alındıysa "Nerede kullanıldı?" boş bırakılabilir.',
          'İnternet gelince bölge ve yer adı kendiliğinden doldurulur '
              '(cihaz kartında da). Konum yoksa yine elle yazılmalı.',
        ),
      ]),
    ],
  ),
  SurumNotu(
    surum: '1.27.3',
    tarih: '21.10.2026',
    bolumler: [
      NotBolumu('Değişen', [
        NotMaddesi(
          'PDF / Excel',
          'Raporun altında yazılı iki büyük düğme: kırmızı PDF, yeşil Excel.',
          'Rapor adı üstte tam görünür. iPhone\'da dosya inmez, Paylaş '
              'menüsü açılır (WhatsApp, e-posta, Dosyalar\'a kaydet).',
        ),
        NotMaddesi(
          'Bölge raporu',
          'Aynı yerin farklı yazılışları tek satırda ("KULAT" = "Kulat").',
          '"Mahallesi / Mah. / Köyü" ekleri atılır. "Montajlı cihaz" ile '
              '"Kurulum noktası" (farklı konum; aynı yere toplu takılanlar tek '
              'nokta) ayrı yazılır; "Belirsiz" mahalle sayılmaz.',
        ),
        NotMaddesi(
          'Kullanım raporu',
          '"Tutanak belirtilmemiş" kutusu eklendi (eski montajlar).',
          'Alt başlıkta yazar: kullanım raporu yapılmış tüm montajları, bölge '
              'raporu şu an takılı cihazları gösterir.',
        ),
      ]),
    ],
  ),
  SurumNotu(
    surum: '1.27.2',
    tarih: '21.10.2026',
    bolumler: [
      NotBolumu('Değişen', [
        NotMaddesi(
          'Kamera yakınlığı',
          'Kamera 2x açılır; görüntünün altındaki 1x · 2x · 3x ile değişir.',
          'Otomatik yakınlaştırma kapatıldı: aniden yaklaşıp uzaklaşması '
              'okumayı bozuyordu. İki parmakla büyütme de çalışır. iPhone\'da '
              'seçici, tarayıcı destekliyorsa görünür.',
        ),
      ]),
    ],
  ),
  SurumNotu(
    surum: '1.27.1',
    tarih: '21.10.2026',
    bolumler: [
      NotBolumu('Düzeltilen', [
        NotMaddesi(
          'Güncelleme kurulumu',
          'Artık telefonun kendi yükleme ekranı açılır; "Güncelle"ye bir kez '
              'dokunmanız yeterli.',
          'Sessiz kurulum Xiaomi / Redmi telefonlarda izinlere takıldığı '
              'için kaldırıldı. İlk seferde telefon "bu kaynaktan izin ver" '
              'diye sorabilir.',
        ),
      ]),
    ],
  ),
  SurumNotu(
    surum: '1.27.0',
    tarih: '21.10.2026',
    bolumler: [
      NotBolumu('Yeni', [
        NotMaddesi(
          'Malzeme barkodu',
          'Okut\'ta hızlı işlem seçiliyken kablo / adaptör barkodu okutunca '
              'listeye eklenir.',
          'Her okutma bir kutu / top sayılır (ör. 305 m); aynı barkod iki kez '
              '= 2 kutu. Montajda "Kaç metre?" sorulur. Miktara dokunarak '
              'değiştirilebilir.',
        ),
        NotMaddesi(
          'Kutu / top içeriği',
          'Ürün tanımında "Bir kutu / top içeriği" (ör. 305 metre).',
          'Ürünler → malzemeye dokunun → kutu içeriğini yazın. Boşsa her '
              'okutma 1 sayılır (patch kablo gibi).',
        ),
        NotMaddesi(
          'Malzeme ekle',
          'Okut listesinde 🔗+ ile barkodsuz malzeme listeden seçilir.',
          'Listede yoksa "+ Yeni malzeme tanımla" ile Okut\'tan çıkmadan '
              'tanımlanır (ad, birim, kutu içeriği, barkod).',
        ),
        NotMaddesi(
          'Birlikte kayıt',
          'Depoya giriş, transfer, Araca Yükle ve montajda cihazlar ve '
              'malzemeler tek seferde kaydedilir.',
          'Transferde malzemelerin nereden alınacağı seçilir. Montajda '
              'yalnız malzeme de kaydedilebilir (cihazsız kullanım).',
        ),
      ]),
    ],
  ),
  SurumNotu(
    surum: '1.26.1',
    tarih: '21.10.2026',
    bolumler: [
      NotBolumu('Yeni', [
        NotMaddesi(
          'iPhone: Ana Ekrana Ekle',
          'Safari\'de ilk açılışta adım adım rehber; Ayarlar\'dan da açılır.',
          'Ana ekrana eklenince bildirimler gelir, telefondaki veriler '
              'silinmez, kamera / konum izni hatırlanır.',
        ),
        NotMaddesi('Görsel onay',
            'Okutunca kamera çerçevesi yeşil (tamam) ya da kırmızı (hata) yanar.'),
        NotMaddesi('Giriş kayıtları',
            'Hangi cihaz ve tarayıcıdan girildiği yazılır (ör. iPhone · Safari).'),
      ]),
      NotBolumu('Değişen', [
        NotMaddesi('iPhone',
            'Safari dışı tarayıcıda "Safari\'de açın" uyarısı; seri no '
                'alanlarında otomatik düzeltme kapalı; ilk okutmada da ses.'),
      ]),
    ],
  ),
  SurumNotu(
    surum: '1.26.0',
    tarih: '21.10.2026',
    bolumler: [
      NotBolumu('Yeni', [
        NotMaddesi(
          'Arka arkaya okutma',
          'Okut\'ta 2 kayıtsız seri no arka arkaya okutulunca liste başlar; '
              'bitince "Depoya ekle (N)".',
          'Liste başladıktan sonra kayıtlı cihaz okutulursa atlanır. İlk '
              'kayıtsızdan sonra kayıtlı cihaz okutulursa "Atla / Kartı aç" '
              'diye sorulur. Liste uygulama kapansa da kaybolmaz.',
        ),
        NotMaddesi(
          'Hızlı işlemler',
          'Depoya giriş · Transfer · Araca Yükle · Montaj: dokunun, arka '
              'arkaya okutun, düğmeyle ilgili ekran listeyle açılır.',
          'Depoya girişe yalnız kayıtsız, diğerlerine yalnız kayıtlı cihaz '
              'girer; uymayan "liste dışı" diye atlanır. Koli karekodları da '
              'arka arkaya okutulabilir. En fazla 100: kameranın üstünde '
              '"98/100" gibi görünür.',
        ),
        NotMaddesi(
          'Toplu montaj',
          'Bir noktaya takılan cihazların hepsi tek seferde, aynı konumla '
              'kaydedilir.',
          'Cihaz kartındaki "Montaj / Kullanıldı" o cihazla açılır, "+ Başka '
              'cihaz okut" ile diğerleri eklenir. Yer, not, tutanak ve '
              'malzemeler bir kez girilir. Kaydettikten sonra "Sonraki nokta".',
        ),
        NotMaddesi(
          'Konum',
          'Montajda Kaydet\'e basıldığı andaki konum kaydedilir.',
          'Ekran açılınca GPS ısınır; üstteki şerit konumun durumunu gösterir '
              '(aranıyor / zayıf / hazır). Konum hazır değilse en fazla 20 sn '
              'beklenir.',
        ),
        NotMaddesi('Varsayılan giriş deposu',
            'Ayarlar\'dan seçilir; depoya girişte hazır seçili gelir.'),
        NotMaddesi('Karışık koli',
            'Depoya girişte bir seri noya dokunup ona ayrı model seçilebilir.'),
      ]),
      NotBolumu('Değişen', [
        NotMaddesi(
          'Araçtan depoya transfer',
          'Normal transfer olarak kaydedilir; "Arızalı" işaretlenirse arıza '
              'iadesi olur.',
          'Arıza iadesi için sebep yazılmalı ve karar (tamir / değişim) '
              'seçilmeli; biri eksikse kaydetmez.',
        ),
        NotMaddesi(
          'Depo ve araç ekranları',
          'Sağ altta "Sayım" ve "İşlemler" (malzeme işlemleri).',
          'Cihaz girişi, transfer ve araca yükleme Okut\'tan yapılır. Sayım '
              'Okut\'tan kalktı; depo / araç ekranında o yer seçili açılır.',
        ),
        NotMaddesi('Depoya giriş',
            'Depolar alt alta görünür; araçlar listelenmez.'),
      ]),
    ],
  ),
  SurumNotu(
    surum: '1.25.1',
    tarih: '20.10.2026',
    bolumler: [
      NotBolumu('Değişen', [
        NotMaddesi(
          'Sayım',
          'Sağ üstte yazılı "Bitir" düğmesi: sayımı bitirip raporu '
              '(PDF / Excel) alır.',
          'Sekmeler (Eksik, Bulunan, Fazla, Malzeme) artık ekrana sığıyor '
              've her biri kendi renginde; sayaçlarla aynı renkler.',
        ),
        NotMaddesi(
          'Kamera düğmesi',
          'Sayım, transfer ve depoya girişte okutma simgesiyle görünür.',
          'Yeşil: kamerayla okut. Kırmızı: kamerayı kapat. (Eskiden video '
              'kamerası simgesiydi, video çekecek sanılıyordu.)',
        ),
      ]),
    ],
  ),
  SurumNotu(
    surum: '1.25.0',
    tarih: '20.10.2026',
    bolumler: [
      NotBolumu('Yeni', [
        NotMaddesi(
          'Ayarlar sekmesi',
          'Alt menüde; yarım kalan işler, bildirim ve etiket ayarları, '
              'güncelleme, yenilikler burada.',
          'Çıkış da artık Ayarlar\'ın en altındaki "Çıkış yap" düğmesinde.',
        ),
        NotMaddesi(
          'Hızlı işlemler',
          'Okut ekranında: Depoya giriş, Transfer, Araca Yükle, Sayım.',
          'Kameranın altındaki "Elle yaz" seri no ile arar, "Fener" ışığı '
              'açar.',
        ),
        NotMaddesi(
          'Son senkron saati',
          'Üst çubukta bulut simgesinin yanında görünür.',
          'Yeşil saat: güncel. Turuncu "3 bekliyor": gönderilmemiş kayıt '
              'var. Kırmızı "Çevrimdışı": internet yok, kayıtlar telefonda '
              'bekler. Dokununca hemen senkronize eder.',
        ),
        NotMaddesi('Büyük yazı',
            'Ayarlar → Büyük yazı ile yazılar ve simgeler büyür.'),
        NotMaddesi('Android indirme linki',
            'Web giriş ekranında "Android uygulamasını indir (APK)".'),
      ]),
      NotBolumu('Değişen', [
        NotMaddesi('Renkli simgeler',
            'Her bölüm kendi renginde; simgeler daha büyük ve okunur.'),
        NotMaddesi(
          'Raporlar',
          'Tarih ve Yenile yazılı düğme; altta büyük "Rapor oluştur".',
          'Sayım, Okut ekranındaki hızlı işlemlere ve depo → İşlemler '
              'menüsüne taşındı.',
        ),
      ]),
    ],
  ),
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
