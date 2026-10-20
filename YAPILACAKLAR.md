# Yapılacaklar / Notlar

Sıradaki işler ve bekleyen kararlar. Yapıldıkça README'deki sürüm notlarına taşınır.

## 1.26.0 – Okut ile arka arkaya okutma (21.10.2026 gecesi kararlaştırıldı, "yap" bekleniyor)

### 1. Okut ekranı
- [ ] **Hızlı işlemler (2×2):** Depoya giriş · Transfer · Araca Yükle · Montaj / Kullanıldı. **Sayım Okut'tan kalkar.**
- [ ] **Hiçbir işlem seçilmeden okutunca:**
  - Kayıtlı cihaz → bugünkü gibi **kartı açılır**.
  - 1. kayıtsız seri no → bugünkü gibi kırmızı uyarı + "Depoya ekle".
  - Hemen ardından **2. kayıtsız** okutulursa **arka arkaya okutma başlar** (hızlı işleme dokunmak gerekmez): ikisi de alttaki **kayıtsızlar listesine** girer, okutmaya devam edilir, bitince **"Depoya ekle (N)"** → giriş ekranı hepsiyle açılır. (Okuttukça depo ekleme ekranı açılmaz.)
  - Arka arkaya okutma başladıktan sonra kayıtlı cihaz → kart açılmaz, "Kayıtlı · atlandı" ile **atlanır**.
  - 1. kayıtsızdan sonra (henüz başlamadan) kayıtlı cihaz okutulursa **sorulur**: "Kayıtlı cihaz: … — Atla / Kartı aç". Atla → okutmaya devam.
  - Liste işlenince ya da Temizle ile boşaltılınca Okut normale döner.
- [ ] **Hızlı işleme dokununca:** arka arkaya okutulur, liste alt alta dolar; bitince işlemin düğmesi ("Transfer et (5)" gibi) ilgili ekranı listeyle **doğrudan** açar.
  - Depoya giriş: yalnız **kayıtsız** girer; kayıtlı okutulursa küçük uyarı, liste dışı.
  - Transfer / Araca Yükle / Montaj: yalnız **kayıtlı** girer; kayıtsız okutulursa küçük uyarı, liste dışı.
  - Arızalı / serviste vb. Okut'ta elenmez; işlem ekranı kaydederken bugünkü kontrolleri yapar.
- [ ] **Koli karekodu:** listeye pencere açmadan tüm seri nolar eklenir; **koliler arka arkaya** okutulabilir; aynı seri no iki kez girmez. Kısa bilgi: "Koli: 10 seri no · 8 eklendi · 2 zaten listede". (İşlem seçilmemişken koli okutulursa bugünkü koli özeti açılır.)
- [ ] **Sınır 100:** çerçevenin üstünde ortada **`100/100`** yazar; her okutmada 1, kolide eklenen kadar birden düşer (99/100, 98/100…); ✕ ile çıkarınca artar. 10 ve altı turuncu, `0/100` kırmızı ve okutma durur. Koli sığmazsa sığan kadarı eklenir, kalanı bildirilir. ("Kalan" kelimesi yazılmaz.)
- [ ] Liste uygulama kapansa da kaybolmaz (taslak).

### 2. Montaj / Kullanıldı
- [ ] Cihaz kartındaki **Montaj / Kullanıldı** → montaj ekranı açılır, bu cihaz listede hazır; **"+ Başka cihaz okut"** ile ilave okutulur. Tek cihazsa doğrudan Kaydet.
- [ ] Okut → Montaj aynı ekranı boş listeyle açar.
- [ ] Nerede kullanıldı, not, tutanak, kullanılan malzemeler **bir kez** girilir, listedeki hepsine uygulanır; hepsi **aynı koordinatla** kaydolur.
- [ ] **Konum:** ekran açılınca GPS ısınır (telefonun hazır son konumu hemen gösterilir), **Kaydet'e basıldığı andaki** konum kaydedilir; konum hazır değilse en fazla 20 sn beklenir. Gösterge: "Konum aranıyor… / Konum zayıf ±35 m / Konum hazır ±6 m". Arka plan konum izni **yok**.
- [ ] Kaydettikten sonra **"Sonraki nokta"**: liste boşalır, yer ve tutanak kalır, konum yeniden alınır.

### 3. Transfer (araçtan depoya)
- [ ] Araçtan depoya transfer **transfer** sayılır.
- [ ] **Arıza iadesi** ancak **Arızalı işaretli + sebep yazılmış + karar (Tamir / Değişim) seçilmiş** ise. Arızalı işaretli ama sebep ya da karar eksikse **kaydetmez**, uyarır.

### 4. Malzemeler (kablo, patch kablo…)
- [ ] Ürün barkodu (EAN-13) okutulunca malzeme tanınır. Birim adet ise ±1; metre ise **kutu / top içeriği** kadar (örn. 1 kutu = 305 m). Montajda metre olanlar için "Kaç metre?" sorulur. Aynı barkod iki kez okutulursa 2 kutu sayılır.
- [ ] Ürün tanımına **kutu / top içeriği** alanı (→ yerel v13 + Supabase'de 1 satır SQL).
- [ ] Okut işlem listelerinde **"+ Malzeme ekle"** (barkodsuz malzeme listeden seçilir) ve **"+ Yeni malzeme tanımla"** (Okut'tan çıkmadan).

### 5. Depoya giriş
- [ ] Ayarlar → **Varsayılan giriş deposu** (telefon başına); giriş ekranında seçili gelir.
- [ ] Depo seçenekleri açıkta, alt alta; **yalnız depolar** (araçlar görünmez).
- [ ] Karışık modellerde her seri noya ayrı model seçilebilir.

### 6. Depo ve araç ekranları
- [ ] Sağ altta yan yana **Sayım** (o depo / araç seçili açılır) ve **İşlemler**.
- [ ] İşlemler'den Okut'ta olan cihaz işlemleri çıkar (yeni giriş, buraya transfer, araca yükle, toplu iade); **malzeme işlemleri** kalır.

### 7. Tarayıcılar
- [ ] Hedef: iPhone → **Safari**; Windows → **Edge, Chrome, Firefox**; Android → uygulama.
- [ ] iPhone'da Safari dışı tarayıcıda uyarı şeridi ("Bildirimler ve Ana Ekrana Ekle için Safari'de açın").
- [ ] Giriş kayıtlarına **cihaz / tarayıcı** ("iPhone / Safari", "Windows / Edge").
- [ ] **Safari:** Ana Ekrana Ekle rehberi (ilk açılışta), dokununca otomatik büyütme kapalı, seri no alanlarında otomatik düzeltme kapalı / büyük harf, çentik ve alt çubuk payı, ilk dokunuşta ses hazırlığı, titreşim yerine görsel onay (çerçeve yeşil / kırmızı yanar), kalıcı saklama izni.

### Sonraya (bu pakette değil)
- iPhone denemesine göre: kamera çözünürlüğü, yakınlaştırma / netleme (destekleniyorsa), dönüşte kameranın yeniden açılması, raporu Paylaş ile gönderme.
- Android'de **yazıdan okuma** (S/N satırı, barkoddan sonra yedek; Ayarlar'dan açık / kapalı).
- Montajda "Nerede kullanıldı?"nın konumdan otomatik doldurulması: **şimdilik yok** (şehir / ilçe merkezindeki tesislerde sorun çıkarır). Google Geocoding: ön ödeme (1.500 TL) yüzünden vazgeçildi.

### Notlar
- **test** ve **Mustafa** kullanıcılarının eklediği ürün / cihaz / seri nolar deneme verisidir; iPhone denemesindekiler de öyle.

## Excel dökümü gelince (ayrı paket)
- [ ] **Excel'den aktarım** (Kamera biriminin demirbaş dökümü): döküm gelince sütun eşleştirmesi, seri nosu boş satırlar, konum (depo / montajlı), demirbaş sicil no kurum kodu olsun mu kararları.
  - **Not:** Miktarlı ürünlerin (kablo, adaptör…) **ilk stoğu** elle mi girilecek, Excel'den mi gelecek? Döküm gelince karar verilecek.
- [ ] **Test verisi temizliği + telefonların otomatik sıfırlanması**: sunucuda "veri sürümü" işareti; değişince cihaz göndermeden kendi kopyasını silip temiz veriyi çeker. Temizlik yalnızca SQL ile (uygulamada silme düğmesi yok). Neyin kalacağı tablosu netleşecek.
- [ ] **Kilit / parmak izi**: oturum açık kalır (Çıkış yapılmadıkça açılınca doğrudan Okut). Açık sorular: otomatik kilit seçilebilir mi olsun (Kapalı / 5 / 30 dk), hassas işlemlerde (silme, hurda, ayarlar) parmak izi olsun mu.

## Yenilikler yazım kuralı
- Her madde tek satır ve kısa: önce ekrandaki ad (kalın), sonra ne değişti. Ayrıntı "Nasıl kullanılır?" olarak maddeye dokununca açılır.
- Başlıklar: Yeni · Değişen · Düzeltilen (boş başlık yazılmaz). Teknik kelime yok; düğme adları ekrandaki gibi.

## Sırada
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
