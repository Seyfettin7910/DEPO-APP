# Depo Takip Uygulaması

Çok kullanıcılı, çoklu depo, offline-senkronizasyonlu stok ve kullanım takip
uygulaması. iOS, Android ve Windows'ta tek kod tabanından çalışır.



## 1.26.1 – iPhone (Safari) ve tarayıcılar
- Hedef tarayıcılar: iPhone → Safari; Windows → Edge / Chrome / Firefox; Android → uygulama.
- `web/tarayici.js` + `lib/services/tarayici*.dart`: tarayıcı adı, iOS, ana ekranda mı, `navigator.storage.persist()` (açılışta).
- iPhone Safari'de ana ekrana eklenmemişse bir kez "Ana Ekrana Ekle" rehberi (Ayarlar'dan da). iPhone'da Safari dışı tarayıcıda alt menünün üstünde uyarı şeridi.
- Giriş kayıtlarında platform: "Web · iPhone / iPad · Safari" gibi (SQL gerekmez).
- `SesServisi.onay`: okutma sonucu kamera çerçevesi yeşil / kırmızı yanar (iPhone'da titreşim yok); ilk dokunuşta ses hazırlanır (iOS ses kilidi). Seri no alanlarında otomatik düzeltme / öneri kapalı. viewport `maximum-scale=1.0`.

## 1.26.0 – Okut ile arka arkaya okutma, toplu montaj
- Okut: `OkutListesi` (lib/services/okut_listesi.dart, testleri test/okut_listesi_test.dart): işlem yokken kayıtlı → kart; 1. kayıtsız → uyarı; 2. kayıtsız → arka arkaya okutma (Depoya giriş listesi); başladıktan sonra kayıtlı atlanır; 1. kayıtsızdan sonra kayıtlı → "Atla / Kartı aç". Hızlı işlemler (Depoya giriş · Transfer · Araca Yükle · Montaj) aynı listeyle; giriş yalnız kayıtsız, diğerleri yalnız kayıtlı alır. Koli karekodu listeye pencere açmadan eklenir. Sınır 100, kamerada "kalan/100". Liste SharedPreferences'ta (`okut_listesi`). Bilgisayarda USB okuyucu için yazma alanı. Sayım Okut'tan kalktı.
- Montaj ekranı (`MontajScreen`): birden çok cihaz aynı kullanım yeri / tutanak / malzeme / koordinatla; cihaz kartından o cihazla açılır; "Sonraki nokta". Konum `KonumIzleyici` ile ekran açıkken akıştan izlenir, Kaydet anındaki (≤5 sn taze, ≤20 m) konum alınır; yoksa en fazla 20 sn beklenir. Taslak türü `montaj`.
- Transfer: hedef depo + araçtan gelen cihaz varsa "Arızalı" seçeneği; işaretliyse sebep + karar zorunlu, kayıt `iade` / `Arıza`.
- Depoya giriş: Ayarlar → Varsayılan giriş deposu (cihaza özel), depolar alt alta (araçlar yok), seri noya özel model (karışık koli; kayıt model gruplarıyla).
- Depo / araç ekranı: "Sayım" + "İşlemler" (yalnız malzeme). İşlem ekranları kaydedince `true` döner (Okut listesi boşalır).
- CI: kontrol dalında `flutter test test/okut_listesi_test.dart`.

## 1.25.1 – Sayım ekranı düzenlemesi
- Sayım: rapor düğmesi soluk simge yerine yazılı "Bitir" (sayımı bitir, PDF / Excel rapor). Dört sekme (Eksik / Bulunan / Fazla / Malzeme) kaydırmasız ekrana sığar (FittedBox), her sekme ve sayaç kendi renginde; depo seçiminde, ekle düğmesinde ve ilerleme çubuğunda renkli simgeler.
- Sayım, toplu transfer ve depoya giriş: kamera düğmesi `videocam` yerine `qr_code_scanner` (yeşil), açıkken `no_photography_outlined` (kırmızı).

## 1.25.0 – Ayarlar sekmesi ve yeni görünüm
- Alt menüde "Çıkış" yerine "Ayarlar" sekmesi (hesap, yarım kalan işler, senkron, bildirim / etiket ayarları, büyük yazı, güncelleme, yenilikler, çıkış).
- Üst çubukta senkron göstergesi: son senkron saati / "N bekliyor" / "Gönderiliyor…" / "Çevrimdışı"; dokununca senkronize eder. Son senkron saati cihazda saklanır.
- Okut ekranında "Elle yaz", "Fener" ve hızlı işlemler (Depoya giriş, Transfer, Araca Yükle, Sayım). Raporlar'da yazılı Tarih / Yenile ve büyük "Rapor oluştur".
- Renkli bölüm simgeleri (`Renkler`), "Büyük yazı" (yazı ölçeği ×1.2), web giriş ekranında Android APK linki.

## 1.24.3 – "database_closed" düzeltmesi
- Android arka plan görevi (senkron + bildirim) iş bitince veritabanını kapatıyordu; sqflite aynı dosya için uygulamayla aynı yerel bağlantıyı paylaştığından arka planda açık duran uygulamanın bağlantısı da kapanıyor, dönünce "DatabaseException(database_closed)" ekran hatası çıkıyordu. Görev artık kapatmıyor.
- `AppDatabase` bağlantı kapanmışsa kendiliğinden yeniden açar (eşzamanlı açılışlar tek seferde) ve açık ekranları tazeler.
- Ekranlarda `AsyncValue.value` yerine `valueOrNull`: veri akışı hata verirse ekran tamamen bozulmaz.

## 1.24.2 – Otomatik kurulum onayı ve hızlı yeni sürüm bildirimi
- Kurulum onayı (Android): sistemin onay ekranı artık uygulamanın ön plandaki ekranından açılıyor (Xiaomi / HyperOS arka plandan açılan ekranı engelliyordu; 1.23.0→1.24.0 ve 1.24.0→1.24.1 geçişlerinde pencere "Tekrar dene"ye düşüyordu). Uygulama arka plandaysa "Güncellemeyi onaylayın" bildirimi. Onay ekranı 3 sn içinde öne gelmezse pencerede "Onay ekranını aç" ve Xiaomi'de "İzni aç" (Diğer izinler ekranı; dönünce kurulum kendiliğinden yeniden denenir). Kurulum sonucu (onay_bekleniyor, iptal, yer yok, bozuk, uyumsuz, çakışma, engellendi) PackageInstaller'dan anında pencereye gelir; 20 sn bekleme kalktı. Normal güncellemede takılınca "Ertele" görünür.
- Yeni sürüm bildirimi: Android arka plan görevi her çalışmada (en fazla 10 dk'da bir) yalnızca version.json'a bakar (GitHub API'ye sormaz). Sunucudaki bildirim fonksiyonu (2 dk'da bir) version.json değişince web / iPhone abonelerine "Yeni sürüm var" gönderir (`push_ayar.son_surum`). Bildirim ayarlarında "Yeni sürüm · her zaman açık" web'de de görünür.

## 1.24.1 – Kamera okuma düzeltmesi
- Okuma onayı süre yerine okuma sayısıyla: kurum etiketi, koli karekodu ve (Okut'ta) kayıtlı kod ilk okumada; bilinmeyen / şüpheli kod 1,5 sn içinde ikinci okumada kabul edilir. Aradaki kaçırılan kareler sayacı sıfırlamaz (küçük, sık çizgili barkodlar — ör. Mercusys S/N — 1.24.0'da okunmuyordu). Açılış beklemesi 0,5 sn; kamera saniyede daha çok kare dener (120 ms).
- Seri no ayıklama: "S/N:", "SN:" önekleri ve sondaki ek bilgi ("22440W0015776 EU/3.0" → 22440W0015776) atılır; böyle kodlar koli sanılmaz.
- Yok sayılan kod çerçevenin üstünde 2 sn gösterilir: "Yok sayıldı: … (MAC adresi / web adresi / sipariş-kutu kodu / ürün barkodu / kayıtlı değil)".
- Kamerada tek parmakla yana kaydırınca Barkod ⇄ Karekod değişir.

## 1.24.0 – Saha işleri: malzemeler, tutanak, Araçlar sekmesi, yeni isimler
- Miktarlı (seri nosuz) ürünler: ürün eklerken takip türü "Seri no ile / Miktarla"; birimler adet, metre, paket, top, kutu; isteğe bağlı fabrika barkodu. Hareketler `stok_hareketleri`'ne `cihaz_id` boş, `miktar` dolu yazılır (yeni tablo yok, silinmez); depo / araç stoğu hareketlerden hesaplanır.
- Depo → "İşlemler": Malzeme girişi, Malzeme Araca Yükle, transfer, iade (araçtan depoya), Malzeme Montaj / Kullanıldı. Malzeme listeden seçilir ya da fabrika barkodu okutulur (tanımsız barkod bir kez malzemeye bağlanır); +/- ve yazarak miktar. Kaynaktaki miktardan fazlası düşülemez. Yarım iş koruması bu ekranda da var. Okut ekranında fabrika barkodu okutulunca malzeme işlemleri açılır.
- Montaj penceresinde "Kullanılan malzemeler" (isteğe bağlı, açılır bölüm): cihazın bulunduğu aracın / deponun malzemeleri hazır gelir, +/- ile girilir; cihazla aynı işlemde stoktan düşer, Kullanım Raporu'na girer.
- Tutanak: montajda zorunlu seçim (Alındı / Alınacak / Kurum içi kullanım). Cihaz kartında tutanak kartı ("Tutanak alındı" / "Değiştir", tarih ve kişi). Ara ekranında ve Kullanım Raporu'nda "Tutanak" sütunu; eski kayıtlar "Belirtilmemiş".
- Depolar ekranı iki sekme: Depolar | Araçlar ("(SEYYAR DEPO)" kalktı); satırda cihaz ve malzeme çeşidi. Depo stokunda "Malzemeler" bölümü, hareketlerde miktar + birim.
- İsimler: "Kullanıma ver" → Araca Yükle (Toplu Araca Yükle), "Sahada kullanıldı" → Montaj / Kullanıldı, durum "Montaj Yapıldı / Kullanıldı", rapor "Kullanım Raporu – Montajı Yapılanlar".
- Raporlar: Kullanım raporunda tutanak ve malzeme satırları; Ürünler raporunda "Malzemeler" bölümü; malzemede ürün stok durumu (konumlara göre miktar, montajda kullanılan); hareket geçmişinde malzeme hareketleri; kritik stok malzemede miktara göre; sayımda "Malzeme" sekmesi (sistemde / sayılan / fark).
- Kamera okuma (tüm okutma ekranları): çerçeve küçüldü (barkod şeridi %70 genişlik, karekod %62); kamera açılınca ilk 0,8 sn okuma yok; birden çok kod varsa ortaya en yakını alınır; web adresi, Wi-Fi, kartvizit, telefon / e-posta, MAC adresi, 4 karakterden kısa kod ve kutu üstündeki ürün barkodları (EAN / UPC; malzeme barkodu okuturken ya da Okut'ta kayıtlı malzeme barkoduysa hariç) yok sayılır; kod çerçevede sabit durunca okunur (kurum etiketi, koli karekodu ve Okut'ta kayıtlı kodlar ~0,4 sn, Okut'ta bilinmeyen kod ~1 sn), çerçevenin altında dolan çubuk gösterilir.
- Bildirimler (telefon ve web): "Araca malzeme geldi", ürün özetinde miktar + birim; sunucudaki kritik stok hesabı malzemeleri de kapsar.
- Supabase: `supabase_guncelleme_1_24_0.sql` bir kez çalıştırılmalı. En düşük sürüm 1.24.0 (zorunlu güncelleme; 1.23.0'daki yarım iş koruması sayesinde iş kaybolmaz).

## 1.23.0 – Güncelleme altyapısı ve yarım iş koruması
- Güncelleme penceresi (telefon ve web): "Şimdi güncelle" / "Ertele" (ilk erteleme 10 dk, sonra 30 dk'da bir). Bir işin ortasındayken (sayım, toplu transfer, depoya giriş, sahada kullanım / arıza penceresi) normal güncelleme penceresi o iş bitince gelir. Zorunlu güncellemede pencere kapanmaz; iş önce taslağa yazılır. Uygulama açık kaldıkça 30 dakikada bir denetlenir; bulut menüsünde "Güncellemeleri denetle".
- Android otomatik kurulum: Wi-Fi'de yeni sürüm önceden arka planda iner; "Şimdi güncelle" deyince (gerekirse indirilip) kendiliğinden kurulur, ikinci bir "Şimdi kur?" sorusu yok. `UPDATE_PACKAGES_WITHOUT_USER_ACTION` izniyle Android 12+ telefonlarda çoğunlukla onay sorulmaz (ilk seferde bir kez sorulabilir; Android 11 ve altı / bazı üreticiler sormaya devam eder). Uygulama kapalıyken indirme biterse "Güncelleme indi · kurmak için dokunun" bildirimi (dokununca kurulur); kurulumdan sonra "Uygulama güncellendi" bildirimi.
- Yeni sürüm bildirimi (Android, uygulama kapalıyken; arka plan görevi en fazla 3 saatte bir sorar, her sürüm için bir kez; zorunlu güncelleme ayrı metin). Bildirim ayarlarında "Yeni sürüm · her zaman açık" (kapatılamaz).
- Yarım kalan iş koruması (taslak): sayım, toplu transfer / kullanıma verme / iade, depoya giriş ekranları ile sahada kullanım, depoya geri alma, arıza kaydı, servise gönderme, onarım sonucu ve hurda pencereleri her değişiklikte telefona yazılır. Uygulama kapanır, çöker ya da güncellenirse açılışta "Yarım kalan işler: Devam et / Sil". Ekranlarda geri tuşunda "Taslak olarak sakla / Sil ve çık / Kal". Liste geri yüklenirken yeniden denetlenir (bu arada başka yere giden cihaz atlanır). Taslaklar 7 gün saklanır; bulut menüsünde "Yarım kalan işler". Cihaz kartında yarım kalan pencere için "Devam et" kartı.
- Yenilikler yeni biçim: kısa maddeler (Yeni / Değişen / Düzeltilen), maddeye dokununca "Nasıl kullanılır?" açıklaması.
- En düşük sürüm 1.22.0 olarak kaldı (zorunlu değil): eski sürümler zorunlu pencereyle işin ortasında kesilmesin. Supabase değişikliği yok.

## 1.22.1
- Depo hareket geçmişinde seri no kopyalama: satırdaki kopyala simgesi veya satıra uzun basma.
- "Yenilikler" ekranı: güncellemeden sonraki ilk açılışta sürüm notları (bu sürümde önceki özelliklerin özeti de var); bulut simgesinin menüsünden sonradan açılabilir. Notlar: `lib/services/surum_notlari.dart` (her sürümde başa eklenir).

## 1.22.0 – Kurum etiketi (barkod / karekod)
- Ayarlardan özelleştirilebilen kurum kodları (ör. `BLD`, `BLD-BIM`). Depoya girişte seçilen kurum koduyla her cihaza benzersiz kod üretilir (`BLD-BIM-7K3Q9X2M`: 7 rastgele + 1 kontrol karakteri, karışan 0/O, 1/I harfleri yok) ve cihazın seri numarasıyla eşleştirilir.
- Etiketler isteğe bağlı olarak basım kuyruğuna alınır; "Basım bekleyen etiket" bildirimi (bildirim ayarlarından açanlara) gider. Basım yalnızca bilgisayardan (web): varsayılan A4 etiket kağıdı (hazır ölçüler veya özel ölçü), rulo etiket (etiket yazıcısı) isteğe bağlı, hizalama test sayfası ve kaydırma ayarı, başlangıç etiketi seçimi, baskı sonrası "hangileri düzgün basıldı" onayı.
- Etikette karekod (kurum kodu + sürüm + seri no) ve yer yeterliyse çizgi barkod (kurum kodu) birlikte; ürün adı, seri no ve tarih yazılı.
- Yapıştırma doğrulaması (telefon): önce etiket, sonra cihazın kendi seri no barkodu okutulur. Eşleşmezse alarm, uyuşmazlık kaydı ve bildirim.
- Engel (kurum genelinde, isteğe bağlı, varsayılan kapalı): açılırsa doğrulanmamış etiketli cihaz transfer edilemez, kullanıma verilemez, sahada kullanılamaz.
- Seri numarası olmayan ürünler için kurum kodu seri no yerine kullanılır. Mevcut stok için "Etiketsiz cihazlar → toplu kod üret". Cihaz kartında etiket durumu, yeniden basım (sürüm artar, eski etiket okutulunca uyarı) ve etiket geçmişi (silinemez).
- Okut, Ara, transfer ve sayım ekranlarında kurum etiketi de okutulabilir. Yeni rapor: Etiket durumu (PDF / Excel).
- Supabase: `supabase_guncelleme_1_22_0.sql` bir kez çalıştırılmalı. En düşük sürüm 1.22.0 (zorunlu güncelleme).

## 1.21.0 – Koli karekodu ve kamera iyileştirmeleri
- Koli karekodu (içinde kolideki bütün cihazların seri numaraları alt alta) okutulunca seri numaraları ayrı ayrı işlenir:
  - Okut ekranı: koli özeti açılır (kaç tanesi kayıtlı / kayıtsız, kayıtlılar nerede). "Depoya ekle" kayıtsızları, "Transfer" depodakileri hazır liste olarak ilgili ekrana götürür.
  - Depoya giriş, toplu transfer / kullanım / iade ve sayım: kolideki bütün seri numaraları tek okutmada listeye eklenir; zaten kayıtlı, başka modele ait vb. olanlar atlanır ve özetle bildirilir.
  - Ara ekranında da koli özeti açılır. Servis dönüşünde yeni cihaz için koli karekodu okutulursa uyarır.
- Kamera: daha yüksek çözünürlük (yoğun karekodlar uzaktan okunur), Android'de otomatik yakınlaştırma, ekrana dokununca netleme, kod okunmadıkça ara ara kendiliğinden netleme, iki parmakla veya "Yakınlaştır" düğmesiyle yakınlaştırma, daha büyük karekod çerçevesi ve depoya giriş / transfer / sayım ekranlarında daha büyük kamera alanı.
- Arka plandan dönüşte kamera, ekran öndeyse kendiliğinden yeniden açılır (tüm okutma ekranlarında).

## 1.20.0 – iPhone ve bilgisayara bildirim
- Web sürümü (iPhone'da ana ekrana eklenen uygulama, bilgisayarda Chrome / Edge) uygulama kapalıyken de bildirim alır: Bildirim ayarları → "Bildirimlere izin ver".
- Bildirimleri Supabase'deki zamanlanmış görev (2 dakikada bir) her abonenin kendi ayarlarına göre gönderir (supabase/functions/bildirim-gonder). Gizli anahtarlar sunucuda kendiliğinden üretilir.
- "Çıkış" artık tam çıkış: sunucu oturumu kapanır, arka plan kontrolü ve bu tarayıcının bildirim aboneliği durur. 5 dakikalık kilit yalnızca ekranı kilitler.
- Supabase: `supabase_guncelleme_1_20_0.sql` bir kez çalıştırılmalı; GitHub'a `SUPABASE_ACCESS_TOKEN` secret'ı eklenmeli.

## 1.19.0 – Bildirimler
- 12 bildirim türü: kritik stok / tükendi, yeni arıza, servis gecikmesi, garanti bitiyor, araca / depoya cihaz geldi, depoya giriş, hurda ve silme, servisten dönüş, hatalı şifre denemeleri, yeni IP'den giriş, gönderilmemiş kayıtlar, günlük özet.
- Android: uygulama kapalıyken de ~15 dakikada bir kontrol edilir (Firebase gerekmez). Bildirim çubuğunda yeni logo simgesi.
- Uygulama içinde zil simgesi (Depolar ve Okut ekranı): okunmamış sayısı, bildirim listesi, ayarlar (tür seçimi, gecikme / garanti gün eşiği, izlenen depo-araçlar, özet saati, test bildirimi, pil kısıtlamasını kaldırma).
- Kendi yaptığınız işlemler için bildirim gelmez. Hatalı şifre ve yeni IP bildirimleri varsayılan kapalı (yönetici açar).
- 5 dakikalık kilit artık yalnızca ekranı kilitler (yine şifre ister); sunucu oturumu açık kalır ki arka planda kontrol sürebilsin. Tam çıkış için "Çıkış".

## 1.18.1
- Yeni logo (tarama çerçevesinde depo): Android simgesi (Android 8+ uyarlanabilir, Android 13+ temalı simge), web sekme simgesi, iPhone "Ana ekrana ekle" simgesi, açılış ve giriş ekranı.

## 1.18.0 – Giriş kayıtları
- Her girişte kullanıcı, tarih-saat, **IP adresi** (sunucunun gördüğü, telefondan değiştirilemez), platform (Android / iPhone / Web), uygulama sürümü ve tarayıcı bilgisi kaydedilir. Hatalı şifre denemeleri de ayrıca kaydedilir.
- Raporlar → **Giriş kayıtları**: kullanıcı bazında özet, hatalı denemeler ve tüm girişler (internet gerekir). Kayıtlar uygulamadan değiştirilemez / silinemez.
- Web'de menü de telefondaki gibi altta.
- Supabase: `supabase_guncelleme_1_18_0.sql` bir kez çalıştırılmalı.

## 1.17.2
- **Seri No ile Depoya Giriş:** üstteki kamera düğmesi kalktı; "Seri no okut" (+) düğmesi kamerayı açar, açık kaldıkça okutulan her seri listeye eklenir. Telefonda hatalı girişi önlemek için seri no elle yazılamaz (bilgisayar tarayıcısında USB barkod okuyucu için yazma alanı kalır). Değişimde yeni cihaz seri nosu da aynı şekilde yalnızca okutulur.
- **Okut ekranı:** başka sayfa açılınca arkadaki kamera durur. Böylece giriş sayfasında okutulan kodlar Okut ekranında "Kayıtlı cihaz yok / Depoya ekle" uyarısı çıkarmaz ve ikinci bir giriş sayfası açılmaz. Geri dönünce veya uygulamaya dönünce kamera yeniden açılır (donma giderildi).

## 1.17.1
- Onarım sonucu "Yeni cihazla değiştirildi" seçilince yeni seri no kamerayla okutulabilir. Seri no sistemde depoda veya başka modelde kayıtlıysa kaydetmeden önce uyarır.

## 1.17.0 – Arıza / servis / hurda
- **Sahadan geri almada arıza:** "Arıza" seçilince "Tamir gerekli" veya "Tamiri mümkün değil, değişim gerekli" sorulur. Cihaz depoya **arızalı** olarak girer; onarılana kadar transfer edilemez, kullanıma verilemez, sahada kullanılamaz, çıkışı yapılamaz ve stok/kritik stok sayılarına girmez.
- **Servis akışı (cihaz kartında):** garanti durumu gösterilir → "Garanti (firma)" veya "Kendi bünyemiz" seçilir; firma, gönderim tarihi ve saati kaydedilir → "Servisten döndü" ile dönüş tarihi/saati, **onarım süresi** ve sonuç girilir: Onarıldı (depoya eklenir), Yeni cihazla değiştirildi (yeni seri no girer, eski stoktan düşer), Onarılamadı (hurda veya değişim için bekletme).
- **Hurda:** "Ömrünü doldurdu (hurda)" ile sahadan geri alınan cihaz doğrudan hurdaya ayrılır. Depodaki cihaz da ⋮ menüsünden veya basılı tutarak hurdaya ayrılabilir (neden sorulur). Kayıt ve geçmiş silinmez.
- Depodaki sağlam cihaz "Arızalı olarak işaretle" ile servise alınabilir; araçtan iadede de arıza seçilebilir.
- Yeni raporlar: **Arıza / servis** (açık/kapanan dosyalar, firma bazında onarım süreleri ve sonuçlar) ve **Hurda**. Ürün raporlarında Arızalı ve Hurda sütunları.
- Supabase: `supabase_guncelleme_1_17_0.sql` güncellemeden önce bir kez çalıştırılmalı. En düşük sürüm 1.17.0.

## 1.16.5
- Güncelleme indirmesi Android'in kendi indirme yöneticisine geçti: uygulama arka plana düşse, hatta kapatılsa da indirme sürer; ilerleme bildirim çubuğunda görünür. Uygulama yeniden açılınca yarım kalan indirme kaldığı yerden izlenir, bitmişse "Şimdi kur" sorulur.
- Wi-Fi ile başlayan otomatik indirme mobil veriye geçilirse duraklar, Wi-Fi gelince devam eder (kota yemez).

## 1.16.4
- APK dosya adı **Depo-Otomasyon-Sistemi.apk** oldu. Eski uygulamaların güncellemesi bozulmasın diye aynı APK eski adla (depo-takip.apk) da yayınlanır; eski link de çalışır.

## 1.16.3
- Uygulama adı **DEPO OTOMASYON SİSTEMİ** oldu (telefon ana ekranı, giriş ekranı, web sekme başlığı, PDF alt bilgisi).

## 1.16.2
- Güncelleme indirilirken toplam boyut, inen miktar ve yüzde görünür ("12,4 MB / 38,7 MB · %32"); Wi-Fi'de arka plan indirmesi alttaki şeritte izlenir. Mobil veride indirmeden önce boyut gösterilir.

## 1.16.1
- Kritik stok hesabına araçlar (seyyar depo) da dahil: depolar + araçlardaki toplam, minimumla karşılaştırılır.

## 1.16.0 – Kritik stok
- Ürünün "Minimum adet uyarısı", **sabit depolardaki toplam** adede göre kontrol edilir
  (araçtakiler hesaba katılmaz, ayrıca gösterilir). Toplam minimuma eşit / altındaysa kritik.
- **Okut** ve **Depolar** ekranlarının üstünde uyarı şeridi (tükenen varsa kırmızı, yoksa
  turuncu); dokununca Kritik stok raporu açılır.
- **Ürünler** ekranında kritik ürünler kartı ve kırmızı adet.
- Depo > Stok sekmesindeki depo bazlı yanıltıcı kırmızı uyarı kaldırıldı; yalnızca toplamı
  kritik olan ürünler işaretlenir.
- Raporlar'da yeni **Kritik stok** raporu (ürün, minimum, depolarda, araçlarda, eksik, durum).

## 1.15.3
- Bilgisayar tarayıcısında açılış ekranı Depolar; telefonda (APK veya telefon tarayıcısı) Okut.

## 1.15.2
- "Tarama" sekmesinin adı **Okut** oldu ve uygulama açılınca doğrudan bu ekran gelir.

## 1.15.1
- Ürünler ekranında kısa dokunuşla düzenleme açılmıyor; Düzenle / Sil yalnızca basılı tutunca.

## 1.15.0 – Ürün ve cihaz silme (nedenli)
- **Basılı tutunca:** Ürünler listesinde ürüne, Depo > Cihazlar sekmesinde ve Ara
  sonuçlarında seri numarasına basılı tutulunca seçenekler çıkar (Düzenle / Aç / Sil).
  Cihaz kartının sağ üst menüsünde de "Cihazı sil" var.
- **Silme nedeni zorunlu:** cihaz için Yanlış kayıt / Mükerrer / Hurdaya ayrıldı /
  Kayıp-çalıntı / Diğer; ürün için Yanlış tanımlandı / Mükerrer / Artık kullanılmıyor /
  Diğer ("Diğer"de açıklama zorunlu).
- Silme, yapan kişi ve nedeniyle **hareket kayıtlarına** yazılır (cihaz geçmişi, depo
  Hareketler sekmesi, Hareket geçmişi raporu). **Hareket kayıtlarını silen hiçbir işlem
  yoktur** (yönetici dahil).
- Kayıtlar gizlenir, raporlardaki geçmiş korunur. Silinen seri no ileride yeniden
  girilebilir. Depoda / araçta / sahada cihazı olan ürün silinemez.
- **Zorunlu güncelleme:** `min_surum.txt` = 1.15.0 (yeni "silme" hareket türünü eski
  sürümler tanımadığı için).

## 1.14.1 – Otomatik güncelleme
- Giriş ekranında "Developed by Seyfettin AYDIN".
- **Telefon:** yeni sürüm Wi-Fi'deyken arka planda indirilir, sonra "Güncelleme hazır →
  Şimdi kur" çıkar (veriler korunur). Mobil veride indirmeden önce sorulur. İlk seferde
  Android "bu kaynaktan yüklemeye izin ver" ister. Kurulum Android PackageInstaller ile
  yapılır (MainActivity.kt); Android 12+ cihazlarda sonraki güncellemeler, üreticinin izin
  verdiği telefonlarda onay sormadan kurulabilir.
- **Web:** açılışta yeni sürüm varsa sayfa kendiliğinden yenilenir (aynı sürüm için bir
  kez; olmazsa "Yenile" sorulur).
- **Zorunlu güncelleme:** repodaki `min_surum.txt` değerinin altındaki sürümler
  "Güncelleme gerekli" ekranında kalır. Sunucuya yeni sütun eklenen sürümlerde bu
  değer yükseltilir.

## 1.14.0 – İl / ilçe / mahalle (köy)
> **Önce Supabase'de `supabase_guncelleme_1_14_0.sql` çalıştırılmalı.**

- "Sahada kullanıldı" penceresinde GPS konumu gelince il, ilçe ve mahalle/köy
  OpenStreetMap (Nominatim) üzerinden otomatik doldurulur; elle düzeltilebilir.
- Köyde internet yoksa konum kaydedilir, adres internet gelince arka planda (senkron
  sonrası) tamamlanır. Elle yazılan alanlara dokunulmaz.
- Ara sekmesinde mahalle / köy / ilçe adıyla arama.
- Yeni **Bölge raporu:** il / ilçe / mahalle bazında kurulum sayıları (en çok olan üstte)
  ve her mahallenin cihaz listesi, harita bağlantılarıyla. İsteğe bağlı filtre.
- Kullanım raporuna **Bölge** sütunu; cihaz kartında ve geçmişte bölge gösterimi.

## 1.13.0 – Kurulum konumu (GPS)
> **Önce Supabase'de `supabase_guncelleme_1_13_0.sql` çalıştırılmalı.**

- "Sahada kullanıldı" penceresi açılınca telefonun o anki GPS konumu bir kez okunur ve
  kayda eklenir (isteğe bağlı kutucuk). Konum yalnızca o an alınır; kişi takibi yapılmaz.
  İzin yoksa veya GPS kapalıysa kayıt konumsuz yapılır.
- Cihaz kartında "Kurulum konumu" düğmesi ve geçmişte 📍 ile Google Haritalar'da açılır.
- Kullanım raporuna **Konum (GPS)** sütunu; Ürünler / Stok durumu raporlarında sahadaki
  cihazların kullanım yerinin yanında koordinat. Excel'de tıklanınca harita açılır,
  uygulama içi önizlemede de dokunulabilir.

## 1.12.0 – Geri alma sebebi
> **Önce Supabase'de `supabase_guncelleme_1_12_0.sql` çalıştırılmalı**
> (`stok_hareketleri` tablosuna `sebep` sütunu).

- Sahada kullanılan / çıkışı yapılan cihaz kartında "Depoya geri al" denince **sebep
  zorunlu**: Arıza, Değişim, İşi bitti / ihtiyaç kalmadı, Yanlış kayıt, Diğer
  ("Diğer"de açıklama zorunlu).
- Araçtan iade ve toplu iadede sebep opsiyonel olarak seçilebilir.
- Sebep cihaz geçmişinde ("Sahadan geri alındı · Sebep: Arıza") ve Hareket geçmişi
  raporunda (Sebep sütunu + sebep bazlı sayılar) görünür.

## 1.11.0 – Alım ve garanti bilgileri
> **Önce Supabase'de `supabase_guncelleme_1_11_0.sql` çalıştırılmalı** (cihazlar tablosuna
> 4 sütun ekler). Çalıştırılmazsa yeni sürümde cihaz senkronizasyonu hata verir.

- Her cihaza **alım tarihi, alınan firma, ihale / sipariş no, garanti bitişi** eklenebilir.
  - Seri no ile girişte "Alım / garanti bilgileri" satırından bir kez girilir, listedeki
    tüm cihazlara uygulanır. Firma ve ihale yazarken daha önce girilenler önerilir.
  - Garanti: 12/24/36/60 ay düğmeleri (alım tarihinden hesaplanır) veya tarih seçimi.
  - Cihaz kartında "Alım / garanti" bölümünde görünür ve düzenlenir; garanti durumu
    renkli gösterilir (yeşil: devam, turuncu: 90 gün içinde bitiyor, kırmızı: bitti).
- Raporlar: Ürünler ve Ürün stok durumu raporlarına Firma, İhale, Alım tarihi, Garanti
  bitiş sütunları eklendi. Yeni raporlar:
  - **Garanti durumu:** bitmiş / 90 gün içinde bitecek / devam eden / bilgisi olmayan
  - **Alımlar (ihale / firma):** her ihale-firma için cihaz listesi ve özet

## 1.10.0 – Raporlar ve sayım
- **Tek rapor yapısı:** Raporlar sekmesinde sağ üstteki "Rapor oluştur" ile rapor seçilir,
  önce uygulamada önizlenir; PDF ve Excel aynı başlık/sütunlarla oradan alınır.
  - **Ürünler:** ürün çeşidine göre ayrılmış (önce ürün özeti, sonra her ürünün cihazları)
  - **Ürün stok durumu:** seçilen ürün için depoda / araçta / sahada kullanılan / çıkan
    dökümü ve konumlara göre dağılım
  - **Kullanım raporu** ve **Hareket geçmişi** (seçili tarih aralığıyla)
- **PDF düzeltmeleri:** tarih aralığı seçilince takılma giderildi; Türkçe karakterler için
  DejaVu Sans yazı tipi uygulamaya gömüldü (assets/fonts, internet gerekmez).
- **Sayım modu:** Raporlar > Sayım veya depo ekranı > "Seri no ile işlem" > Sayım yap.
  Depo/araç seçilir, seri nolar okutulur; Bulunan / Eksik / Fazla anlık görünür, sonunda
  sayım raporu alınır. Sayım sistemde hiçbir kaydı değiştirmez.

## 1.9.1 – Güncelleme uyarısı
- Uygulama açılınca (ve en fazla 6 saatte bir uygulamaya dönüldüğünde) yeni sürüm
  var mı bakar. Telefonda "İndir" APK linkini açar; web'de "Yenile" sayfayı yeniler.
- Sürüm numarası derlemede gömülür (`--dart-define=APP_SURUM`); giriş ekranının
  altında görünür. FlutLab derlemelerinde kontrol yapılmaz.

## 1.9.0 – Otomatik oturum kapatma ve Çıkış düğmesi
- **5 dakika** dokunma/tuş olmazsa oturum kapanır, giriş ekranı gelir (uygulama arka
  plandayken veya kapalıyken geçen süre de sayılır). Süre `lib/services/oturum_kilidi.dart`
  içindeki `sure` değeridir.
- Alt menünün sonunda **Çıkış** düğmesi var (onay sorar).
- İnternet yokken de kilitlenir; ancak **tekrar giriş için internet gerekir**.
  Telefondaki gönderilmemiş değişiklikler silinmez, girişten sonra gönderilir.

## 1.8.0 – Hedef çerçeveli okuma
- Tüm kamera ekranlarında ortada yeşil bir hedef çerçeve var; **yalnızca çerçevenin
  içindeki kod okunur**. Etikette seri no barkodunun yanında başka barkod/karekod
  olsa bile karışmaz.
- Sağ üstteki düğmeyle çerçeve **Barkod** (ince-uzun) ↔ **Karekod** (kare) yapılır;
  seçim telefonda hatırlanır.
- Çerçevenin içinde yine birden çok kod varsa uyarı verilir, hiçbiri okunmaz.

## 1.7.0 – Excel raporları
Raporlar sekmesindeki tablo simgesinden (PDF'in yanında) üç Excel çıktısı alınır:
- **Kullanım raporu** (ekrandaki liste, seçili tarih aralığıyla)
- **Tüm cihazlar** (seri no, ürün, kategori, durum, şu anki depo/araç)
- **Hareket geçmişi** (giriş, transfer, kullanım, iade, çıkış; kim, ne zaman, nereden nereye)

Web'de dosya doğrudan iner; telefonda paylaş menüsü açılır (WhatsApp, e-posta, Drive...).
Tarih aralığı seçildiğinde son gün de dahil edilir.

## 1.6.1
- Giriş ekranı son kullanılan e-postayı hatırlar; şifreyi telefonun/tarayıcının şifre
  kaydedicisi doldurabilir (girişten sonra "şifreyi kaydet" teklifi gelir).
- Oturum zaten saklanır: uygulama kapatılıp açıldığında giriş istenmez; yalnızca
  "Çıkış yap" denince veya uygulama silinip yeniden kurulunca sorulur.

## Android APK'yı GitHub'da derleme

`.github/workflows/android.yml` her yüklemede imzalı APK derler ve Releases'e koyar.
Sabit indirme adresi (saha ekibine bu link verilir):
https://github.com/Seyfettin7910/DEPO-APP/releases/latest/download/Depo-Otomasyon-Sistemi.apk

- İmza anahtarı repoda DEĞİL; GitHub secret'larında durur
  (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`). Yedeği güvenli yerde saklanmalı.
- Aynı anahtarla imzalandığı için güncellemeler eski uygulamanın üstüne kurulur
  (her sürümde `pubspec.yaml` içindeki `version` artırılır).
- Repodaki `android/` klasörü FlutLab için olduğu gibi kalır; derleme makinesi Gradle
  dosyalarını `tool/android_hazirla.py` ile güncel Flutter şablonuna uyarlar.

## Web'de çalıştırma (1.6.0)

Web sürümü tarayıcıda açılır; veriler tarayıcının içinde (IndexedDB) tutulur ve
girişten sonra Supabase ile eşitlenir. Kamera ile okutma için adresin **https**
olması gerekir (aşağıdaki iki yol da https verir). USB barkod okuyucu, klavye
gibi yazdığı için Ara sekmesindeki kutuda doğrudan çalışır.

Web derlemesinden önce bir hazırlık komutu gerekir
(`dart run sqflite_common_ffi_web:setup`: sqlite3.wasm + sqflite_sw.js üretir).
Aşağıdaki iki yol bunu otomatik yapar.

**Yol A – Windows bilgisayar**
1. Flutter SDK'yı kurun (docs.flutter.dev > Get started > Windows) ve
   `flutter doctor` ile kontrol edin. Chrome kurulu olsun.
2. Zip'i açın, klasördeki `web_derle.bat` dosyasına çift tıklayın.
3. Açılan `build\web` klasörünü https://app.netlify.com/drop sayfasına sürükleyin.
   Ücretsiz hesap açarsanız adres kalıcı olur (ör. depo-takip.netlify.app).
   Güncellemede aynı sitenin "Deploys" sekmesine yeni klasörü sürükleyin.

**Yol B – GitHub (bilgisayarsız, otomatik)**
1. GitHub'da bir repo açın, proje dosyalarını repo köküne yükleyin
   (`.github/workflows/web.yml` dahil).
2. Repo > Settings > Pages > Source: **GitHub Actions**.
3. Her yüklemede Actions sekmesinde derlenir ve
   `https://<kullanici-adi>.github.io/<repo-adi>/` adresinde yayınlanır.
   Not: ücretsiz hesapta Pages için repo herkese açık olmalı. Kodda yalnızca
   Supabase'in herkese açık (publishable) anahtarı var; veriler giriş + RLS ile
   korunur. Gizli (secret) anahtar ve veritabanı şifresi asla repoya konmaz.

Web'de bilinen sınırlar: sayfanın ilk açılışı için internet gerekir; her tarayıcı
kendi yerel kopyasını tutar (girişten sonra sunucudan dolar); fener düğmesi
çoğu tarayıcıda çalışmaz.

## Ne içeriyor?

- **Yerel veritabanı (sqflite):** `lib/database/` — offline çalışma bunun
  üzerinden yürür. Kod üretimi (build_runner) GEREKTİRMEZ, bu yüzden bulut
  IDE'lerde (FlutLab vb.) veya Flutter SDK kurulu olmayan ortamlarda da
  sorunsuz derlenir. Her tabloda `dirty` (henüz senkronize edilmedi) ve
  `deleted` (soft delete) alanları var.
- **Senkronizasyon (Supabase):** `lib/services/sync_service.dart` — bağlantı
  gelince yereldeki değişiklikleri sunucuya gönderir, sunucudaki değişiklikleri
  çeker. Şu an sadece `stok_hareketleri` ve `kullanim_kayitlari` / `depolar`
  / `urunler` için tam yazıldı; `araclar`/`kullanicilar`/`depo_stoklari` için
  aynı desenle genişletilmesi gerekiyor (kodda NOT olarak işaretlendi).
- **Supabase şeması:** `lib/services/supabase_service.dart` dosyasının altında
  yorum içinde tam SQL var (tablolar + örnek RLS politikası).
- **Barkod/QR tarama:** `lib/screens/hareket/barkod_tarama_screen.dart` —
  mobile_scanner paketiyle. iOS/Android'de doğrudan çalışır.
- **Stok hareketi mantığı:** `AppDatabase.hareketKaydet()` — giriş, çıkış,
  transfer ve "kullanım" (araca/yere düşülen) hareketlerini tek transaction
  içinde işler ve depo_stok tablosunu otomatik günceller.
- **Kullanım raporu + PDF export:** `AppDatabase.kullanimRaporu()` ve
  `lib/services/pdf_report_service.dart` — "hangi ürün, hangi depodan,
  hangi araca/yere kullanıldı" sorusuna cevap verir, PDF olarak dışa aktarılır.

## Telefonda hızlıca deneme (bilgisayar gerekmeden) — FlutLab.io

Flutter'ı yerelde kurmadan, tamamen telefon tarayıcısından gerçek bir APK
üretip kurabilirsiniz:

1. Telefonunuzda bu projeyi indirdiğiniz `depo_app.zip` dosyasını **açmayın**,
   olduğu gibi bırakın.
2. Tarayıcıdan **flutlab.io** adresine gidin, ücretsiz hesap oluşturun.
3. "New Project" → **"Upload as .zip"** seçeneğini seçin, `depo_app.zip`
   dosyasını yükleyin.
4. Proje açıldıktan sonra sağ üstteki **"Build Project"** butonuna basın,
   hedef olarak **Android (APK)** seçin.
5. Derleme bitince APK'yı indirin ve telefonunuza kurun (Android'de "bilinmeyen
   kaynaklardan yükleme" iznini açmanız gerekebilir).
6. Uygulama Supabase'e bağlanmadan da (offline modda) test edilebilir —
   depo/ürün ekleyip stok hareketi girerek yerel veritabanının çalıştığını
   görebilirsiniz. Gerçek senkronizasyon için adım 7'ye bakın.
7. Supabase bağlamak isterseniz: FlutLab proje ayarlarında "Environment
   Variables" veya build komutuna `--dart-define` ekleme seçeneğini kullanıp
   `SUPABASE_URL` ve `SUPABASE_ANON_KEY` değerlerini girin (aşağıdaki
   "Kurulum" bölümüne bakın).

**Not:** FlutLab'in ücretsiz planı 2 proje / 250 MB depolama ile sınırlı,
bu proje için yeterli.

## Bilgisayarda kurulum (tam geliştirme ortamı)

1. Flutter SDK'yı kurun: https://docs.flutter.dev/get-started/install
2. Bağımlılıkları çekin:
   ```
   flutter pub get
   ```
3. Bir Supabase projesi açın (ücretsiz plan yeterli): https://supabase.com
   - `lib/services/supabase_service.dart` altındaki SQL'i Supabase SQL
     Editor'de çalıştırarak tabloları oluşturun.
   - Proje URL ve anon key'i alın.
4. Uygulamayı çalıştırın:
   ```
   flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co --dart-define=SUPABASE_ANON_KEY=xxxx
   ```

## Windows için ek adım

```
flutter config --enable-windows-desktop
flutter create --platforms=windows .
flutter run -d windows
```

## Eksik / genişletilmesi gereken kısımlar (bilinçli olarak iskelet bırakıldı)

- Giriş/kimlik doğrulama ekranı (Supabase Auth ile e-posta+şifre veya magic
  link) henüz yok — `aktifKullaniciIdProvider` şu an elle set edilmeli.
- Kullanıcı-depo yetkilendirme ekranı (kim hangi depoyu görebilir) yok.
- `sync_service.dart` içindeki `_pushDirty`/`_pullRemoteChanges` tüm
  tabloları kapsayacak şekilde genişletilmeli.
- Excel export yok (şu an sadece PDF).
- Çakışma çözümü şu an "son yazan kazanır" seviyesinde basit tutuldu.

## Sürüm notları

### 1.5.0 (build 8) — 1.5.0 (ve 1.4.1) değişiklikleri dahil
- **İade:** araçtaki cihazın kartında "İade" düğmesi. Hedef olarak cihazın geldiği depo
  hazır seçili gelir; geçmişte "İade" olarak görünür.
- Depo ekranındaki "Seri no ile işlem" menüsüne **Toplu iade** eklendi.
- **Sahada kullanıldı:** cihaz kartındaki düğmeyle (örn. araçtaki kişi seri no'yu okutup) cihaz
  bulunduğu depo/araç stoğundan düşer, hiçbir stokta görünmez; kullanım yeri kaydedilir ve
  Kullanım Raporu/PDF'e girir. "Çıkış"tan farkı: nerede kullanıldığı tutulur.
- "Kullanıma ver" (depo/araca geçirme) artık kullanım raporuna yazılmaz; rapor yalnızca
  sahada kullanımları gösterir.
- Derleme hatası düzeltildi (Depolar ekranı import'u).

### 1.4.0 (build 6) — Seyyar depo (araçlar)
- **Araçlar seyyar depo olarak çalışır.** Depolar ekranında "+" ile yeni depo veya yeni
  araç (plaka) eklenir; araçlar kamyon simgesiyle ayrı bölümde listelenir. Araç da
  depo gibi içinde cihaz tutar: Stok, Cihazlar, Hareketler sekmeleri aynıdır.
- Depo/araç düzenleme ve silme (içinde cihaz varsa silinemez).
- **Kullanıma ver = transfer mantığı:** hedef depo veya araç listeden seçilir, cihaz
  oraya geçer. Cihaz kartında "Araçta: 34 ABC 123" olarak görünür.
- **Toplu transfer / toplu kullanıma ver:** seri numaraları okutulup tek seferde bir
  depoya veya araca taşınır (Tarama ekranındaki ↔ düğmesi veya depo ekranındaki
  "Seri no ile işlem" menüsü).
- Supabase'te `depolar` tablosuna `tur` sütunu eklendi: güncellemeden ÖNCE
  `supabase_kurulum.sql` yeniden çalıştırılmalıdır (zararsızdır).

### 1.3.0 (build 5) — Sunucu senkronizasyonu ve giriş
- **Giriş ekranı** (e-posta + şifre, Supabase Auth). Kullanıcılar Supabase panelinden
  eklenir. Oturum telefonda saklanır; çevrimdışı açılışta yeniden giriş istenmez.
- **Telefonlar arası senkronizasyon:** depolar, ürünler, cihazlar (seri no) ve tüm
  hareketler sunucuya gönderilir ve diğer telefonlara iner. Uygulama çevrimdışı da
  çalışır; bağlantı gelince otomatik senkronize olur (30 sn'de bir + her değişiklikte).
- Depolar ekranının sağ üstünde **senkron durumu** simgesi: bekleyen kayıt sayısı,
  son senkron saati, hata, "Şimdi senkronize et" ve "Çıkış yap".
- Hareket geçmişinde **işlemi kimin yaptığı** görünür.
- Çakışmada son yazan kazanır. Aynı seri no iki telefonda çevrimdışıyken ayrı ayrı
  eklenirse ikincisi sunucuda reddedilir ve durum menüsünde uyarı çıkar.
- Sunucu kurulumu için `supabase_kurulum.sql` dosyasını Supabase SQL Editor'de bir kez
  çalıştırın.
- Güncelleme mevcut verilerin üzerine kurulur; telefondaki mevcut kayıtlar ilk girişte
  sunucuya yüklenir.

### 1.2.1 (build 4)
- Yeni ürün formunda kamera simgeli alan artık **seri numarası** içindir (model
  barkodu kaldırıldı). Seri no yazılır/okutulur ve depo seçilirse ürün kaydedilirken
  cihaz o depoya girilir. Aynı model adı varsa seri no mevcut modele eklenir.
- Birim alanı formdan kaldırıldı.

### 1.2.0 (build 3) — Seri numarası ile takip
- **Her cihaz seri numarasıyla takip edilir.** Giriş, çıkış, transfer, kullanıma
  verme ve iade seri numarası okutularak yapılır.
- **Adetler otomatik:** model/ürün bazında ve depo bazında adetler, depoda duran
  seri numaralı cihazların sayısından hesaplanır (elle adet girilmez).
- **Ara sekmesi:** seri numarası yazın ya da okutun; cihazın hangi ürün olduğu
  ve şu an hangi depoda / hangi araçta (veya çıkış yapıldı) olduğu görünür.
  Arama kutusu model, depo ve araç plakasıyla da çalışır.
- **Tarama sekmesi:** seri no okutunca cihaz kartı açılır. Kayıtlı değilse uyarı
  sesi + titreşim verir, "Depoya ekle" önerir.
- **Seri no ile toplu giriş:** model ve depo seçilir, seri numaraları kamerayla
  tek tek okutulur veya elle yazılır, hepsi tek seferde kaydedilir. Aynı seri
  no iki kez eklenemez.
- Depo ekranı: Stok (model bazlı adet), Cihazlar (seri no listesi + arama),
  Hareketler (SN dahil).
- Kullanım raporu ve PDF'e **Seri No** sütunu eklendi.
- Etikette birden çok barkod varsa uygulama karışmaması için okumayı bekletir
  ve uyarı gösterir; yalnızca seri no barkodunu çerçeveye alın.
- Güncelleme mevcut verilerin üzerine kurulur. 1.1.0'da adet olarak girilmiş
  eski test stokları artık sayılmaz; cihazlar seri no ile yeniden eklenmelidir.

### 1.1.0 (build 2)
- Depo ekranı artık **Stok** ve **Hareketler** sekmelerinden oluşuyor: ürünlerin
  güncel adedi ve giren/çıkan/transfer edilen/kullanılan her işlem görünür.
- Depo ekranından **Giriş / Çıkış** düğmesiyle doğrudan o depoya stok eklenebilir;
  stok satırına dokunmak ürünü ve depoyu hazır seçili olarak hareket formunu açar.
- Depo listesinde çeşit sayısı ve toplam miktar, ürün listesinde tüm depolardaki
  toplam stok görünür.
- Depoda olandan fazla çıkış/transfer/kullanım girilemez (yetersiz stok uyarısı).
- Barkod okununca ürün bulunursa kısa bip, **bulunamazsa uyarı sesi + titreşim**.
  Aynı kod kamerada beklerken alarm tekrar tekrar çalmaz (3 saniye bekleme).
- Veritabanı şeması değişmedi: 1.0.0 üzerine kurulunca mevcut veriler korunur.

### 1.0.0
- İlk sürüm.
