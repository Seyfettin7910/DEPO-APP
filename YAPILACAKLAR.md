# Yapılacaklar / Notlar

Sıradaki işler ve bekleyen kararlar. Yapıldıkça README'deki sürüm notlarına taşınır.

## Yayınlananların telefonda denenmesi (21.10.2026 sabahı)
- [ ] **Supabase SQL:** `supabase_guncelleme_1_27_0.sql` (malzemede kutu içeriği) — kutu içeriği tanımlamadan ÖNCE çalıştırılmalı.
- [ ] 1.26.0: Okut arka arkaya okutma (2 kayıtsız), hızlı işlemler, koli, 100/100, toplu montaj + Kaydet anındaki konum, Sonraki nokta, transfer "Arızalı", varsayılan giriş deposu, karışık model, depo ekranında Sayım.
- [ ] 1.26.1: iPhone Safari (Ana Ekrana Ekle rehberi, Safari dışı uyarı, ses, görsel onay), giriş kayıtlarında tarayıcı.
- [ ] 1.27.0: malzeme barkodu (kutu içeriği), 🔗+ malzeme ekle / yeni tanımla, giriş / transfer / montajda birlikte kayıt.

## Sonraya
- [ ] iPhone denemesine göre: kamera çözünürlüğü, yakınlaştırma / netleme (destekleniyorsa), dönüşte kameranın yeniden açılması, raporu Paylaş ile gönderme.
- [ ] Android'de **yazıdan okuma** (S/N satırı; barkoddan sonra yedek; Ayarlar'dan açık / kapalı).
- [ ] Montajda "Nerede kullanıldı?"nın konumdan otomatik doldurulması: şimdilik yok (şehir / ilçe merkezindeki tesislerde sorun çıkarır). Google Geocoding ön ödeme (1.500 TL) yüzünden bırakıldı.
- Not: **test** ve **Mustafa** kullanıcılarının eklediği her şey deneme verisidir (iPhone denemesi dahil).

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
