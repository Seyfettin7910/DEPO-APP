# Yapılacaklar / Notlar

Sıradaki işler ve bekleyen kararlar. Yapıldıkça README'deki sürüm notlarına taşınır.

## 1.24.2 – Daha hızlı "Yeni sürüm" bildirimi + kurulum onayı (konuşuldu, "yap" bekleniyor)
- [ ] **Android:** arka plan görevi her çalışmada (~15 dk, Android'in en sık aralığı) sürümü denetler; 3 saatlik sınır kalkar. Yalnızca kendi sürüm dosyamıza (version.json) bakar, GitHub API'ye sormaz (aynı internet çıkışındaki çok telefonda sorgu sınırına takılmasın). Her sürüm için bir kez.
- [ ] **Web / iPhone:** sunucudaki bildirim fonksiyonu her çalışmada sürüm dosyasına bakar; yeni sürümde web bildirimine abone herkese "Yeni sürüm var" gönderir (neredeyse yayın anında).
- [ ] **Otomatik kurulum onayı (Xiaomi / HyperOS sorunu):** 1.23.0 → 1.24.0 ilk kendi kendine güncellemede pencere "Tekrar dene"ye düştü (onay ekranı arka plandaki alıcıdan açılamadı; Xiaomi "arka planda açılır pencere" iznini kapalı tutuyor). Düzeltme: onay ekranı uygulamanın açık ekranından açılır; uygulama kapalıysa "Güncellemeyi onaylamak için dokunun" bildirimi; kurulum sonucu (onay reddedildi, yer yok, dosya bozuk…) pencerede anında gösterilir, 20 sn bekleme kalkar.
- Not: Yayın anında (anlık) Android bildirimi için Firebase gerekir; şimdilik gerek görülmedi. Değişiklik telefonlar 1.24.2'yi kurunca çalışır.

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
