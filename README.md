# Depo Takip Uygulaması

Çok kullanıcılı, çoklu depo, offline-senkronizasyonlu stok ve kullanım takip
uygulaması. iOS, Android ve Windows'ta tek kod tabanından çalışır.



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
