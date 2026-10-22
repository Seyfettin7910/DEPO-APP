# Yapılacaklar / Notlar

Sıradaki işler ve bekleyen kararlar. Yapıldıkça README'deki sürüm notlarına taşınır.

**Kapsam:** Uygulamanın amacı **depo yönetimi**. Taşınır / taşınmaz / zimmet kayıtları belediyenin **Flexity** yazılımında tutulur, bu uygulamanın kapsamında değil; uygulama raporlarıyla onu **destekler** (ör. Flexity'ye girilecek bilgileri hazır veren dökümler).

## Yayınlananların telefonda denenmesi
- [x] **Supabase SQL:** `supabase_guncelleme_1_27_0.sql` çalıştırıldı.
- [x] **Supabase SQL:** `supabase_guncelleme_1_29_0.sql` (anlık senkron) çalıştırıldı (12 tablo).
- [x] **Supabase SQL:** `supabase_guncelleme_1_29_1.sql` (eski yazılar büyük harf) 21.10.2026'da, telefonlar 1.29.1'e geçmeden çalıştırıldı.
- [ ] Aynı SQL **bir kez daha**: Seyfettin'in ve kardeşinin telefonu 1.29.1'e geçip ikisinde de "bekleyen yok" görününce (eski sürümle küçük harf yazılanlar için). Arkadaşlar ara ara deneme yapıyor (giriş kayıtlarında görünür); eski sürümle küçük harf yazarlarsa SQL tekrar çalıştırılır, zararsız.
- [ ] 1.26.0: Okut arka arkaya okutma (2 kayıtsız), hızlı işlemler, koli, 100/100, toplu montaj + Kaydet anındaki konum, Sonraki nokta, transfer "Arızalı", varsayılan giriş deposu, karışık model, depo ekranında Sayım.
- [ ] 1.26.1: iPhone Safari (Ana Ekrana Ekle rehberi, Safari dışı uyarı, ses, görsel onay), giriş kayıtlarında tarayıcı.
- [ ] 1.27.0: malzeme barkodu (kutu içeriği), 🔗+ malzeme ekle / yeni tanımla, giriş / transfer / montajda birlikte kayıt.
- [ ] 1.27.1: güncelleme telefonun kendi yükleyicisiyle (Güncelle'ye bir dokunuş).
- [ ] 1.27.2: kamera 2x sabit, altta 1x · 2x · 3x seçici (otomatik yakınlaştırma kapalı).
- [ ] 1.27.3: raporlarda PDF / Excel düğmeleri, bölge raporu adları.
- [ ] 1.28.0: "Nerede kullanıldı?" konumdan (15 m içindeki eski ad, yoksa İLÇE MAHALLE), internetsiz montajda sonradan dolma.
- [ ] 1.29.0: kamera 15 sn'de yavaşlama / 30 sn'de durma + dokununca açılma, fener sönmesi; iki telefonla (biri uçak modunda) senkron denemesi; Android'de S/N yazıdan okuma (gerçek etiketlerle); iPhone'da kamera durup açılınca izin tekrar soruluyor mu.
- [ ] 1.29.1: bütün alanlar büyük harf (Türkçe İ / I; seri no, barkod, plaka Latin), klavye büyük harfle açılıyor mu, SQL sonrası eski kayıtlar çevrildi mi.
- [ ] 1.29.2: kamera ekranı (düğme yok, üstte "… için yana kaydırın", sol üstte sayaç 100/kalan, pembe şerit çerçevenin hemen üstünde, karekod çerçevesi aynı boyutta, altta "15-25 cm uzakta tutun", küçük 1x · 2x · 3x); yazıdan okuma 3 sn + barkod önceliği (Mercusys etiketiyle); alttaki düğmeler tuşların üstünde mi (etiket kağıdı, rapor önizleme); etiket kağıdı ekranı tek Kaydet + tam genişlik; yazdırma önizlemesi (büyütme, çift dokunuş, Yazdır / PDF paylaş).
- [ ] 1.29.3: karekod modunda "15-25 cm uzakta tutun" görünüyor mu, ince 1x · 2x · 3x; ürün adı Latin büyük harf (hikvision → HIKVISION); benzer ürün ekranı (yeni üründe seçim, ad düzeltmede uyarı). Eski "HİKVİSİON" adlarını elle düzelt.
- [x] **Supabase SQL:** `supabase_guncelleme_1_30_0.sql` (urunler.birlesti_id) 22.10.2026'da çalıştırıldı.
- [ ] 1.30.0: ürün birleştirme (Ürünler → basılı tut → "Başka ürünle birleştir"; ad düzeltmede "Birleştir"); özet sayıları doğru mu, cihazlar / hareketler / malzeme stoğu kalan üründe mi; internetsiz telefonda eski ürünle kayıt → internet gelince kalan ürüne geçiyor mu. Roller gelince yalnız yönetici.
- [ ] 1.30.1: Okut'ta kayıtsız seri → "Depoya ekle" → "+ Yeni" ile model tanımla, seçili geliyor mu, seriler duruyor mu.

## Final paketi (toplanıyor; tek güncellemede yapılacak, "yap" bekliyor)
İhtiyaçlar ekran ekran toplanıyor: Okut · Depolar · Ürünler · Ara ve cihaz kartı · Raporlar · Ayarlar ve bildirimler · Bilgisayar (web) ve iPhone · Sistem.

### Okut
- [ ] **Okuma kaynağı göstergesi:** okuma kabul edilince çerçevenin hemen üstünde 1,5 sn küçük etiket: "✓ Barkod" (çizgi barkod), "✓ Karekod" (koli dahil), "✓ Yazı (S/N)" (pembe). Kayıtlara / senkrona / rapora GEÇMEZ, yalnız ekranda. Bütün kamera ekranlarında. (Amaç: hangi etiketlerin barkoddan okunamadığını sahada görmek.)
- [ ] **Okuma sayıları ("kapının ölçüsü"), göstergeyle aynı pakette, SENKRONLU** (amaç: hangi telefon modelinde okuma zayıf, cihaza özel iyileştirme):
  - Sayılanlar: kabul edilen okumalar kaynağa göre (barkod / karekod / yazı); yok sayılan kodlar sebebe göre (ürün barkodu, MAC, web adresi, sipariş / kutu kodu, kayıtlı değil…); "Doğru mu?" Evet / Hayır; kameranın 30 sn'de durması; ortalama okuma süresi (kamera açılışı / son okumadan kabul edilen okumaya).
  - Telefon bilgisi: model (ör. Xiaomi 2201117TG), Android / iOS sürümü, uygulama sürümü, tarayıcı (web), kamera yakınlığı (1x / 2x / 3x). Telefon başına sabit bir kurulum kimliği.
  - Kayıt biçimi: telefon başına günde bir satır, sunucuda yeni tablo `okuma_istatistikleri` (Supabase SQL gerekir). Kişisel veri yok; telefon bazında (kullanıcıya bağlanmaz, aksi istenmedikçe).
  - **Anlık senkrona GİRMEZ (Seyfettin'in kararı):** sayılar gün boyu telefonda birikir, **günde bir kez akşam ~17:00-18:00** sunucuya gönderilir (arka plan görevi; o saatte gönderilemezse uygulama sonraki açıldığında önceki günler gönderilir). Yalnız gönderilir, telefonlara geri çekilmez; Realtime yayınına eklenmez → pil, internet ve senkron yükü yok.
  - Görünüm: Raporlar → "Okuma istatistikleri" (internet gerekir, sunucudan anlık okunur, giriş kayıtları gibi): telefon modeline göre tablo (okuma sayısı, yazıdan %, yok sayılan %, "Hayır" %, ortalama süre), tarih aralığı; PDF / Excel. Telefonda Ayarlar'da yalnız henüz gönderilmemiş (bugünkü) sayılar; geçmiş günler Raporlar'da.
  - **Gönderilen günler telefondan silinir** (sunucu "aldım" deyince; gönderilemeyen gün silinmez, sonra tekrar denenir). Telefonda ekstra veri birikmez.
  - Gerekli: telefon modeli için `device_info_plus` paketi.

### Depolar
- [ ] **Araçlar sekmesinde uzun basınca hızlı bakış:** listeden çıkmadan alttan açılan pencerede araçtakilerin özeti (ör. "HIKVISION 7104 NVR × 2 · IP KAMERA × 6 · CAT6 KABLO 305 m"), altında "Ayrıntılar" (stok ekranını açar). Dokununca bugünkü gibi stok ekranı açılır. (Depolar sekmesinde de aynı olabilir.)

## Sonraya
- [ ] **"Nerede kullanıldı?"nın konumdan otomatik dolması – Google'dan çekme ERTELENDİ** (Google hesabı 1.500 TL ön ödeme istiyor; Geocoding anahtarı / günlük kota 250 hazır bekliyor). Kararlar:
  - Önce eski montajlardan öğrenme: yeni konumun **en fazla 15 m** yakınında daha önce yazılmış ad varsa o gelir; konum hassasiyeti **±15 m'den kötüyse** eski ad önerilmez.
  - Yakında eski ad yoksa adres servisinden (OpenStreetMap / ileride Google) ilçe + mahalle.
  - İnternet yokken satır boş bırakılabilir, bağlantı gelince otomatik dolar (konum da yoksa elle yazmak zorunlu).
  - Şehir / ilçe merkezindeki belediye tesislerinde sorun çıkarmaması için ayrıca düşünülecek.
- [ ] **iPhone optimizasyonu (bekleyebilir):** iPhone şu an web sürümünü (Safari) kullanıyor, iOS uygulaması henüz derlenmedi. 30 sn sonra kamera durup açılırken Safari izin tekrar sorarsa iPhone'da durdurma yerine yalnız yavaşlatma.
- [ ] **iPhone (Safari) kamerası (bekleyebilir):** netleme ve çözünürlük Safari'nin elinde (dokununca netleme orada çalışmaz); iPhone denemesinde okuma yavaş / zor olursa ya da dönüşte kamera açılmazsa bakılacak. Android'de hepsi yapıldı: yüksek çözünürlük, dokununca + 4 sn'de bir netleme, dönüşte yeniden açılma (1.21.0), hızlı okuma 120 ms + okuma sayısıyla onay (1.24.1), 2x sabit (1.27.2).
- Not: **test** ve **Mustafa** kullanıcılarının eklediği her şey deneme verisidir (iPhone denemesi dahil).
- Not: Şu an kullanan telefonlar: Seyfettin'in ve kardeşinin telefonu; başka kullanıcı yok. Arkadaşlar ara ara deneme yapıyor.

## Excel dökümü gelince (ayrı paket)
- [ ] **Excel'den aktarım** (Kamera biriminin demirbaş dökümü): döküm gelince sütun eşleştirmesi, seri nosu boş satırlar, konum (depo / montajlı), demirbaş sicil no kurum kodu olsun mu kararları.
  - **Not:** Miktarlı ürünlerin (kablo, adaptör…) **ilk stoğu** elle mi girilecek, Excel'den mi gelecek? Döküm gelince karar verilecek.
- [ ] **Test verisi temizliği + telefonların otomatik sıfırlanması**: sunucuda "veri sürümü" işareti; değişince cihaz göndermeden kendi kopyasını silip temiz veriyi çeker. Temizlik yalnızca SQL ile (uygulamada silme düğmesi yok). Neyin kalacağı tablosu netleşecek.
- [ ] **Kilit / parmak izi**: oturum açık kalır (Çıkış yapılmadıkça açılınca doğrudan Okut). Açık sorular: otomatik kilit seçilebilir mi olsun (Kapalı / 5 / 30 dk), hassas işlemlerde (silme, hurda, ayarlar) parmak izi olsun mu.

## Yenilikler yazım kuralı
- Her madde tek satır ve kısa: önce ekrandaki ad (kalın), sonra ne değişti. Ayrıntı "Nasıl kullanılır?" olarak maddeye dokununca açılır.
- Başlıklar: Yeni · Değişen · Düzeltilen (boş başlık yazılmaz). Teknik kelime yok; düğme adları ekrandaki gibi.

## Sırada
- [ ] **Flexity'ye aktarım raporu:** idari işlerin Flexity'ye girdiği bilgiler (yeni alınan cihazlar, kurulum yeri, hurda…) doğrudan Flexity'nin beklediği sütunlarla Excel olarak. Gerekli: Flexity'nin toplu aktarım şablonu / örnek dosyası (idari işlerden alınacak).
- [ ] **Kullanıcı rolleri ve yetkiler** (Yönetici / Depocu / Saha); silme yalnızca yöneticide, hareket kayıtları kimse tarafından silinemez.
- [ ] **Veritabanı yedeği** (gece şifreli otomatik yedek + uygulamadan Excel dışa aktarım).
- [ ] **Belediye sunucusuna geçiş** (alan adı → web + APK → veritabanı). Gerekli bilgi: sunucu Windows mu Linux mu, internete çıkışı ve dışarıdan erişimi var mı.

## Bekleyenler
- [ ] **Etiket engelini zorunlu yapmak** (1.22.0'da isteğe bağlı): uyum sorunu çıkmazsa ayar kaldırılıp kural zorunlu hale getirilir.
- [ ] **Etiket yazıcısı hazır şablonu**: yazıcının marka / modeli öğrenilince rulo ölçüsü hazır şablon olarak eklenir.
- [ ] **APK boyutunu küçültme** (cihaz türüne göre ayrı APK, ~90 MB → ~30-35 MB). Tablet / el terminali kararı netleşince.
- [ ] **El terminali desteği** (Zebra, Honeywell vb.): "barkod okuyucu modu" veya Zebra DataWedge. Cihaz markası/modeli belli olunca.
- [ ] **Tablet düzeni** (geniş ekranda iki sütun) gerekirse.
- [ ] **Kısa uygulama adı** ana ekranda ("Depo Otomasyon"), istenirse.
- [ ] **Giriş kayıtlarının saklama süresi** (KVKK) belediye politikasına göre.
- [ ] Eski `depo-takip.apk` adını kaldırma (herkes 1.16.4+ olunca).
