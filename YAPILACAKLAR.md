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
- [ ] 1.30.2: barkodsuz malzemeye kurum kodu (tek tek / hepsine), barkod etiketi basma + önizleme, Okut'ta etiketi okutunca kutu içeriği ekleniyor mu, tanımsız 266'lı kodda uyarı.

## Sıradaki ara sürüm (1.30.3; Final paketinden ÖNCE, Seyfettin'in kararı; birkaç konu daha eklenecek)
#### Malzeme stok kodu (266'lı EAN-13; 1.30.2'de geldi)
- [ ] **Adı "Stok Kodu"** (Seyfettin'in kararı): 266'lı kodun her yerdeki adı "kurum kodu" yerine **Stok Kodu** (ürün formu, menüler, Okut uyarısı, etiket, yenilikler). "Kurum kodu / kurum etiketi" yalnız cihazlardaki BLD-BIM-… karekodu için kalır. ("Seri no" denmedi: seri no tek cihaza özel, stok kodu malzemenin türüne.)
- **Kural (Seyfettin'in kararı):** her malzemenin tek kimliği stok kodu; hangi firmadan / hangi barkodla gelirse gelsin depoya girerken kutuya bizim etiketimiz yapıştırılır, fabrika barkodu kullanılmaz → birden çok barkod alanı gerekmez.
- [ ] Toplu: "Bütün malzemelere stok kodu ver (fabrika barkodlarının yerine)"; yeni malzemede barkod boşsa kaydederken stok kodu kendiliğinden; Okut'ta malzemenin fabrika barkodu okutulursa "Fabrika barkodu okunmaz, kutudaki stok kodu etiketini okutun"; malzeme girişi kaydedilince "Kaç kutu geldi? Etiket basılsın mı?".

#### Bilgisayar (web)
- [ ] **Sağ tık menüsü + satırlarda görünür ⋮** yalnız bilgisayar tarayıcısında (Edge / Chrome / Firefox); telefon uygulaması ve iPhone Safari'de bugünkü gibi uzun basma (⋮ gizli). Uzun basmayla menü açılan bütün listelerde (ürünler, depolar, cihazlar…).

#### Bildirimler
- [ ] **Zil yalnız bildirimleri göstersin:** bildirim listesindeki dişli (sağ üst) ve liste boşken çıkan "ayarlar" düğmesi kalkar; bildirim ayarları yalnız Ayarlar → Bildirim ayarları'nda.

#### Senkron gereksiz tetikleniyor (incelendi)
Bulunan sebepler: uygulamaya her dönüşte 3 tam senkron (öne gelme + oturum yenileme olayı + anlık bağlantının yeniden kurulması; yazdırma / paylaşma / izin pencereleri de "dönüş" sayılıyor); saatlik oturum yenilemesinde tam senkron; Wi-Fi ⇄ mobil veri geçişinde tam senkron; kendi gönderdiğimiz kaydın sunucudan "yankısı"; yalnız kontrol ederken bile "Gönderiliyor…" yazması.
- [ ] **Birleştirme:** tam senkron bitince 30 sn içinde gelen yeni tam senkron istekleri atlanır (gönderilmemiş kayıt varsa ve "Şimdi senkronize et"e elle basılırsa atlanmaz).
- [ ] **Oturum olayı:** yalnız gerçek girişte senkron; saatlik yenilemede değil.
- [ ] **İnternet:** yalnız "yoktu → geldi" geçişinde tam senkron; Wi-Fi ⇄ mobil geçişinde değil.
- [ ] **Yankı:** sunucudan gelen değişiklik bilgisi telefondaki kayıtla aynıysa (kendi gönderdiğimiz) yok sayılır.
- [ ] **Görünüm:** "Gönderiliyor…" yalnız gönderilecek kayıt varken; yalnız kontrolde düğmede küçük dönen simge.
- Kayıt kaçmasına karşı korumalar (5 dk yedek kontrol, damga yöntemi, 1 dk pay) aynen kalır.

#### Ürün formu: kategori açılır liste
- [ ] **Kategori açılır liste** (ürünlerde kullanılan kategoriler, alfabetik; en üstte "Kategorisiz") + yanında **"+ Yeni"** (depoya girişteki "Ürün / model" satırı gibi): küçük pencerede yeni ad (büyük harf), kaydedince seçili gelir. Yeni ad var olana benziyorsa uyarı ("KAYIT CİHAZLARI zaten var…", benzer ürün kontrolü gibi). Yeni tablo yok, kategoriler ürünlerden. (Sonraya not: kategori yeniden adlandırma / birleştirme.)

#### Ayarlar → Kullanıcılar (yalnız görüntüleme; roller DEVREYE GİRMEZ)
- [ ] Liste: ad, e-posta, son giriş (tarih-saat, Android / iPhone / web), **uygulama sürümü** (büyük harf SQL'inin ikinci çalıştırması için "herkes 1.29.1'de mi" buradan). **Görünen ad düzenlenebilir** (e-postanın @ öncesi yerine "SEYFETTİN AYDIN"). Ekleme / şifre sıfırlama / pasif yapma / roller YOK (Final paketinde, sunucu fonksiyonu gerekir). Sınır: yalnız en az bir kez giriş yapmış kullanıcılar görünür. Herkes görür (deneme döneminde e-postalar uydurma, Seyfettin'in notu).

#### Malzeme Montaj / Kullanıldı ekranı
- [ ] Alttaki açıklama: "fabrika barkodunu okutun" yerine "stok kodu etiketini okutun ya da 'Malzeme seç' ile listeden seçin".
- [ ] **Konum:** cihaz montajındaki gibi Kaydet anında konum alınır (konum şeridi), "Nerede kullanıldı?" 15 m içindeki eski addan ya da "İLÇE MAHALLE" olarak kendiliğinden dolar; internetsizde boş bırakılabilir, sonra dolar.
- [ ] **"Kaydet (0 kalem)"** kalem yokken pasif.
- [ ] Yer örneği büyük harf: "ÖRN: ZABITA MÜDÜRLÜĞÜ, PARK CAD. 12"; "Not (isteğe bağlı)" (aşağıdaki yazım birliğiyle).

#### Yazım birliği
- [ ] **"opsiyonel" → "isteğe bağlı"** bütün ekranlarda (ör. Malzeme Montaj / Kullanıldı → "Not (isteğe bağlı)"); Yenilikler yazım kuralındaki gibi tek dil.

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
- (Araçta hızlı bakış: vazgeçildi; dokununca stok ekranı zaten açılıyor.)

### Flexity uyumu (dökümdeki biçime göre; döküm ÖRNEK, yapı buna göre düzenlenecek)
- [ ] **Ürün:** MARKA ve MODEL ayrı alanlar (bugün yalnız "ad"); ad bunlardan + kısa açıklamadan oluşur. Ürüne Flexity **taşınır kodu ve adı** (ör. 253.01.03 · GÖRÜNTÜLEME, BİLGİ TOPLAMA VE TAKİP SİSTEMLERİ).
- [ ] **Cihaz kartı:** **Flexity sicil no** (253.01.03.2025.N), **değer**, (eşleştirme için) Flexity ID. Seri no = Flexity "ETİKET NO". İlk giriş tarihi = alım tarihi. ZİMMETLİ / KULLANAN / DOSYA NO tutulmaz (Flexity'nin işi, KVKK).
- [ ] **Sicil no gizli alan:** Android / iPhone / web ekranlarında HİÇ görünmez, yalnız raporlarda (Seyfettin'in kararı). Biçim: taşınır kodu . yıl . sıra (253.01.03.2027.1); sıra yıla özel. **Uygulama numara ÜRETMEZ:** örnek dökümde 2025 sıraları kesintili (5–809 aralığında 106 numara başka kayıtlarda; Mayıs partisi Ocak'ın arasına düşmüş) → numaralar belediye genelinde aynı taşınır kodunu paylaşan kayıtlarla ortak. **Akış (ör. Ocak 2027 ihalesi):** 1) depoya giriş (seri nolar) → 2) "Flexity'ye girilecekler" raporu (seri no ETİKET NO'ya) → 3) idari işler Flexity'ye girer, Flexity sicil verir → 4) Flexity dökümü uygulamaya yüklenir, **seri no ile eşleştirilip** sicil yazılır; eşleşmeyenler listelenir. Yükleme yetkisi: Yönetici + Depo sorumlusu (yetki tablosuna yeni madde).
- [ ] **Depo / araç:** Flexity'deki **yer adı** karşılığı (ör. "Haberleşme Şube Müdürlüğü Kamera Montaj Ekibi Deposu"); montajlıda yer = kullanım yeri.
- [ ] **Excel'den aktarım:** bu sütun düzenini başlık adlarından tanır; yazım farkları düzeltilir (HIKVISON, 16 KANL, O / 0, I / 1), benzer ürün kontrolüyle model eşlenir; seri nosuz satırlar sicil no ile "seri no bekleniyor".
- [ ] **Flexity raporu:** aynı sütun düzeniyle Excel: SİCİL NO · ADI · SERVİS · MARKA · MODEL · İLK GİRİŞ TARİHİ · DEĞERİ · BULUNDUĞU YER · DEMİRBAŞ AÇIKLAMASI (kendiliğinden: model açıklaması + "sn: …" + yer, bugün elle yazılan biçim) · ETİKET NO (seri no). Flexity'de tutulan sütunlar (ZİMMETLİ, DOSYA NO, KULLANAN) boş. Süzgeç: değişenler (tarih aralığı) / hepsi.

### Sistem: kullanıcı kaydı ve roller (kararlar tamam)
- **Bugün:** kullanıcılar Supabase panelinden açılıyor; uygulama herkesi "saha" kaydediyor ama rolün etkisi yok; sunucuda giriş yapan herkes her şeyi yapabiliyor.
- **Kullanıcı işleri tamamen uygulamadan** (Seyfettin'in kararı): Supabase paneline girmeden, yönetici ekranından kullanıcı ekleme, rol, pasif yapma, şifre sıfırlama. Sıfırlamada geçici şifre + ilk girişte değiştirme zorunlu (ilk kayıttaki gibi). **Geçici şifre: her seferinde rastgele 6 haneli** (ör. "482915"; yöneticiye büyük gösterilir + "Kopyala"; sabit "123456" güvenlik açığı olduğu için seçilmedi), **15 dakika geçerli** (Seyfettin'in kararı; yeni kullanıcıda da aynı). Süre dolarsa yönetici yeniden "Şifre sıfırla". Kullanıcı geçici şifreyle girince "Yeni şifrenizi belirleyin" ekranı; değiştirmeden hiçbir işlem yapamaz (sunucuda da). Listede durum: aktif / pasif / "şifre değiştirmesi bekleniyor". **Kod iletme kuralı** (Seyfettin'in kararı): kod yalnız **kim olduğunu bildiğin kişiye** yüz yüze, belediyenin mesajlaşma grubundan ya da tanıdık numaraya mesajla iletilir; telefonla gelen talebe ses tanınmadan kod verilmez. Sıfırlama penceresinde bu bir satırla hatırlatılır; kullanım kılavuzuna da yazılır. **"Şifremi unuttum" düğmesi (sade, Seyfettin'in kararı):** giriş ekranında; e-posta yazılır → **yalnız yönetici hesaplarına bildirim** gider ("Ahmet Y. şifre sıfırlama istedi") ve kullanıcıya **uyarı ekranı** açılır ("Talebiniz yöneticiye iletildi; yeni geçici şifreniz size yönetici tarafından iletilecek"). **Yöneticide:** bildirime dokununca doğrudan **uyarı ekranı** açılır: "Ahmet Y. (e-posta) şifre sıfırlama istedi · 13:40" + **"Şifre sıfırla"** düğmesi (6 haneli kod, 15 dk, "yalnız tanıdığın kişiye ilet" hatırlatması) + "Kapat". Kullanıcılar listesinde aramaya gerek kalmaz. Talep listesi / reddet / takip YOK. Küçük korumalar: mesaj e-posta kayıtlı olsun olmasın aynı (hesap yoklanamaz); aynı e-postadan 15 dk'da bir bildirim. Giriş yapılmamışken gönderildiği için Supabase sunucu fonksiyonu üzerinden. Android'de uygulama kapalıysa bildirim en geç ~15 dk'da düşer.
- **Hesap işlemleri kaydı** (Seyfettin'in kararı, yapılacak): şifre talebi (e-posta, zaman, IP); şifre sıfırlama (hangi yönetici, kimin, ne zaman); geçici şifreyle giriş ve şifre değiştirme; süresi dolan geçici şifre; kullanıcı ekleme, rol değiştirme, pasif / aktif yapma. **Şifre ya da kodun kendisi asla yazılmaz.** Görünüm: Raporlar → Giriş kayıtları → "Hesap işlemleri" sekmesi (yalnız yönetici), tarih / kullanıcı süzgeci, PDF / Excel. Uygulamadan değiştirilemez / silinemez; saklama süresi KVKK maddesiyle birlikte.
- **Kayıt:** dışarıdan kayıt kapalı; Ayarlar → Kullanıcılar (yalnız yönetici): ekle / düzenle / pasif yap (silme yok, geçmiş korunur; pasif kullanıcının oturumu kapanır); şifre sıfırlama. Gizli anahtar telefona gelmez, Supabase sunucu fonksiyonu çağıranın yönetici olduğunu denetler. **Kullanıcı açma: geçici şifre + ilk girişte değiştirme zorunlu** (Seyfettin'in kararı; e-posta altyapısı gerekmez). **Şifre unutulursa:** yönetici Ayarlar → Kullanıcılar → "Şifre sıfırla" ile yeni geçici şifre verir, ilk girişte yine değiştirme zorunlu. **Yönetici unutursa:** başka bir yönetici sıfırlar → en az 2 yönetici olması önerilir; hiç yönetici kalmazsa Supabase panelinden.
- **Roller:** Yönetici (Y) · Depo sorumlusu (D) · Saha (S) · **Gözlemci** (R): yalnız görür + rapor alır (idari işler, amirler, sayım komisyonu).
- **Yetki tablosu yöneticinin düzenleyebildiği tablo** (Seyfettin'in kararı; sabit olsaydı her değişiklik kod demekti): Ayarlar → Roller ve yetkiler; **aşağıdaki varsayılanlarla başlar**, "Varsayılana dön" düğmesi. Kilitlenmeye karşı: Yönetici rolünden kullanıcı yönetimi (30) kaldırılamaz; 33 (hareket silme) kimseye açılamaz. Yetkiler sunucuda da (RLS) aynı tablodan okunur.
- **Yetki tablosu (madde madde, varsayılanlar):**

| # | Yetki (varsayılan) | Y | D | S | Gözlemci |
|---|---|---|---|---|---|
| 1 | Okutma, cihaz kartını görme | ✅ | ✅ | ✅ | ✅ |
| 2 | Cihaz arama | ✅ | ✅ | ✅ | ✅ |
| 3 | Depoya giriş (yeni cihaz) | ✅ | ✅ | ❌ | ❌ |
| 4 | Depolar arası transfer | ✅ | ✅ | ❌ | ❌ |
| 5 | Araca yükleme | ✅ | ✅ | ✅ | ❌ |
| 6 | Araçtan depoya iade | ✅ | ✅ | ✅ | ❌ |
| 7 | Montaj / kullanıldı | ✅ | ✅ | ✅ | ❌ |
| 8 | Sahadan geri alma | ✅ | ✅ | ✅ | ❌ |
| 9 | Arıza bildirme (arızalı işaretleme) | ✅ | ✅ | ✅ | ❌ |
| 10 | Servis süreci (gönderme, dönüş, değişim) | ✅ | ✅ | ❌ | ❌ |
| 11 | Cihaz kartı bilgisini düzenleme (alım, garanti, yer) | ✅ | ✅ | ❌ | ❌ |
| 12 | Hurdaya ayırma | ✅ | ❌ | ❌ | ❌ |
| 13 | Cihaz silme | ✅ | ❌ | ❌ | ❌ |
| 14 | Malzeme girişi | ✅ | ✅ | ❌ | ❌ |
| 15a | Malzemeyi araca yükleme | ✅ | ✅ | ✅ | ❌ |
| 15b | Araçtan depoya malzeme iadesi | ✅ | ✅ | ✅ | ❌ |
| 15c | Depolar arası malzeme transferi | ✅ | ✅ | ❌ | ❌ |
| 16 | Montajda malzeme kullanımı | ✅ | ✅ | ✅ | ❌ |
| 17 | Ürün / model tanımlama, düzenleme | ✅ | ✅ | ❌ | ❌ |
| 18 | Ürün birleştirme | ✅ | ✅ | ❌ | ❌ |
| 19 | Ürün silme | ✅ | ❌ | ❌ | ❌ |
| 20 | Depo / araç tanımlama, düzenleme | ✅ | ✅ | ❌ | ❌ |
| 21 | Depo / araç silme | ✅ | ❌ | ❌ | ❌ |
| 22 | Sayım | ✅ | ✅ | ❌ | ❌ |
| 23 | Kurum kodu üretme, basım kuyruğu | ✅ | ✅ | ❌ | ❌ |
| 24 | Etiket basma (bilgisayardan) | ✅ | ✅ | ❌ | ❌ |
| 25 | Etiket yapıştırma doğrulaması | ✅ | ✅ | ✅ | ❌ |
| 26 | Kurum etiketi ayarları (kodlar, engel) | ✅ | ❌ | ❌ | ❌ |
| 27 | Raporlar, PDF / Excel (Flexity dahil) | ✅ | ✅ | ❌ | ✅ |
| 28 | Giriş kayıtları | ✅ | ❌ | ❌ | ❌ |
| 29 | Okuma istatistikleri raporu | ✅ | ✅ | ❌ | ❌ |
| 30 | Kullanıcı yönetimi | ✅ | ❌ | ❌ | ❌ |
| 31 | Kendi bildirim ayarları | ✅ | ✅ | ✅ | ✅ |
| 32a | Bütün kullanıcıların güvenlik bildirimleri (hatalı şifre, yeni IP) | ✅ | ❌ | ❌ | ❌ |
| 32b | Kendi hesabının güvenlik bildirimleri ("hesabına yeni bir yerden giriş yapıldı") | ✅ | ✅ | ✅ | ✅ |
| 33 | **Hareket kaydı silme** | ❌ | ❌ | ❌ | ❌ |

- **Uygulama:** yetkisi olmayan düğmeyi görmez; **sunucuda da veritabanı kurallarıyla** (RLS) kesinleşir; internetsizken yapılmış yetkisiz işlem sunucuca reddedilir, telefonda "yetkiniz yok".
- **Geçiş:** ilk yönetici Seyfettin (tek SQL); mevcut kullanıcıların rolleri Seyfettin'den.
- (Saha kullanıcısına araç bağlama: vazgeçildi.)

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
- **Döküm geldi (22.10.2026):** Flexity'den "Görüntüleme, Bilgi Toplama ve Takip Sistemleri" (taşınır kodu 253.01.03), 699 satır, hepsi HIKVISION, 13 model. Sütunlar: ID · SİCİL NO (253.01.03.2025.N) · ADI · SERVİS · MARKA · MODEL · PLAKA (boş) · İLK GİRİŞ TARİHİ · DEĞERİ · ZİMMETLİ · DOSYA NO · KULLANAN (boş) · BULUNDUĞU YER · GİRİŞ / DEMİRBAŞ AÇIKLAMASI · ORTAK KULLANIM · ETİKET NO.
  - **ETİKET NO aslında seri no:** 285 satırda dolu (22.08.2025 Netkur alımı; GA8346… / 11 haneli), 414 satırda boş (24.01.2025 ve 02.05.2025 alımları).
  - Yer: 414 "Sanal Oda (Taşınır Yer Tanımı Öncesi)", 281 "Kamera Montaj Ekibi Deposu", 3 montajlı (Şehitlik ×2, Atatürk Parkı), 1 boş (açıklamada "Fen İşleri"). Montajlılarda seri ve yer elle DEMİRBAŞ AÇIKLAMASI'na yazılmış.
  - Yazım farkları: "HIKVISON", "16 KANL", "DS-2CD 1340GOILF" (boşluk, O / 0), "DS-2CD2121G0-1" (I / 1).
  - Analiz sohbette; kararlar bekleniyor (seri nosuz 414 cihaz, Sanal Oda'dakilerin gerçek yeri, sicil no ve değer alanları).
- [ ] **Excel'den aktarım** (Kamera biriminin demirbaş dökümü): döküm gelince sütun eşleştirmesi, seri nosu boş satırlar, konum (depo / montajlı), demirbaş sicil no kurum kodu olsun mu kararları.
  - **Not:** Miktarlı ürünlerin (kablo, adaptör…) **ilk stoğu** elle mi girilecek, Excel'den mi gelecek? Döküm gelince karar verilecek.
- [ ] **Test verisi temizliği + telefonların otomatik sıfırlanması**: sunucuda "veri sürümü" işareti; değişince cihaz göndermeden kendi kopyasını silip temiz veriyi çeker. Temizlik yalnızca SQL ile (uygulamada silme düğmesi yok). Neyin kalacağı tablosu netleşecek.
- [ ] **Kilit / parmak izi**: oturum açık kalır (Çıkış yapılmadıkça açılınca doğrudan Okut). Açık sorular: otomatik kilit seçilebilir mi olsun (Kapalı / 5 / 30 dk), hassas işlemlerde (silme, hurda, ayarlar) parmak izi olsun mu.

## Yenilikler yazım kuralı
- Her madde tek satır ve kısa: önce ekrandaki ad (kalın), sonra ne değişti. Ayrıntı "Nasıl kullanılır?" olarak maddeye dokununca açılır.
- Başlıklar: Yeni · Değişen · Düzeltilen (boş başlık yazılmaz). Teknik kelime yok; düğme adları ekrandaki gibi.

## Sırada
- [ ] **Flexity'ye aktarım raporu:** idari işlerin Flexity'ye girdiği bilgiler (yeni alınan cihazlar, kurulum yeri, hurda…) doğrudan Flexity'nin beklediği sütunlarla Excel olarak. Gerekli: Flexity'nin toplu aktarım şablonu / örnek dosyası (idari işlerden alınacak).
- [ ] **Veritabanı yedeği** (gece şifreli otomatik yedek + uygulamadan Excel dışa aktarım).
- [ ] **Belediye sunucusuna geçiş** (alan adı → web + APK → veritabanı). Gerekli bilgi: sunucu Windows mu Linux mu, internete çıkışı ve dışarıdan erişimi var mı.

## Bekleyenler
- [ ] **Etiket engelini zorunlu yapmak** (1.22.0'da isteğe bağlı): uyum sorunu çıkmazsa ayar kaldırılıp kural zorunlu hale getirilir.
- [ ] **Etiket yazıcısı hazır şablonu**: yazıcının marka / modeli öğrenilince rulo ölçüsü hazır şablon olarak eklenir.
- [ ] **APK boyutunu küçültme** (cihaz türüne göre ayrı APK, ~90 MB → ~30-35 MB). Tablet / el terminali kararı netleşince.
- [ ] **El terminali desteği** (Zebra, Honeywell vb.): "barkod okuyucu modu" veya Zebra DataWedge. Cihaz markası/modeli belli olunca.
- [ ] **Tablet düzeni** (geniş ekranda iki sütun) gerekirse.
- [ ] **Kısa uygulama adı** ana ekranda ("Depo Otomasyon"), istenirse.
- [ ] **KVKK (BEKLEMEDE — program kabul edilip gerçek kullanıma geçilince; deneme sürecinde değil, Seyfettin'in kararı):**
  - Giriş ekranında (Android, iPhone, web) kısa satır: "Sistemin sağlıklı yürütülebilmesi için kullanıcı, giriş ve işlem konumu bilgileriniz kaydedilmektedir. Aydınlatma Metni" → tam metin sayfası (veri sorumlusu: Belediye; veriler ve amaçlar; aktarım: sunucu hizmeti; hukuki sebep; kullanıcı hakları ve başvuru). "Kabul ediyorum" kutusu YOK (aydınlatma ≠ rıza). Taslak hazırlanır, belediyenin KVKK sorumlusu onaylar.
  - Giriş kayıtları / hesap işlemleri için saklama süresi (belediyenin saklama-imha politikasına göre), süresi dolanlar kendiliğinden silinir.
  - Sunucunun yeri (yurt dışı aktarım) → Türkiye / belediye sunucusu kararıyla birlikte.
  - Belediyenin KVKK sorumlusuna bilgi (VERBİS envanteri onların işi). Not alanlarına vatandaş adı / telefonu yazılmaması kullanım kuralı.
- [ ] Eski `depo-takip.apk` adını kaldırma (herkes 1.16.4+ olunca).
