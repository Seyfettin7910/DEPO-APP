# Veritabanı yedeği — açma ve geri yükleme

Yedekleri `.github/workflows/yedek.yml` alır: her gece 03:17'de (Türkiye saati) Supabase
veritabanının tam dökümü çıkarılır, **YEDEK_SIFRESI** ile AES-256 şifrelenir ve iki yere
konur:

| Yer | Nerede |
|---|---|
| Gizli GitHub deposu | `Seyfettin7910/DEPO-APP-yedek` → **Releases** → `yedek-YYYY-AA-GG` |
| Google Drive | `DEPO-APP-yedek/YYYY-AA/depo_YYYY-AA-GG_SSDD.tar.gpg` |

**Saklama:** son 30 gün her gece + 12 ay boyunca her ayın ilk yedeği. Daha eskiler iki
yerden de kendiliğinden silinir (kural: `tool/yedek_saklama.py`).

**Ayda bir geri yükleme denemesi:** ayın 1'inde yedek GitHub'dan indirilir, şifresi açılır,
boş bir veritabanına yüklenir, her tablonun satır sayısı döküm anındakiyle karşılaştırılır.
Drive'daki kopyanın GitHub'dakiyle birebir aynı olduğu da denetlenir. Elle denemek için:
GitHub → Actions → **Veritabanı yedeği** → **Run workflow**.

Yedek alınamazsa ya da deneme başarısız olursa GitHub e-posta gönderir.

## Dosyanın içinde ne var

`depo_….tar.gpg` şifresi açılınca bir `.tar` arşivi çıkar:

| Dosya | İçerik |
|---|---|
| `public.dump` | Uygulamanın bütün tabloları: ürünler, depolar, cihazlar, stok hareketleri, montaj/servis kayıtları, etiketler, giriş kayıtları, okuma istatistikleri… |
| `auth.dump` | Kullanıcı hesapları (e-posta, şifre özeti). Alınamadığı gecelerde yoktur, uyarı verilir. |
| `sayim.txt` | Döküm anında her tablonun satır sayısı (`şema.tablo\|adet`) |
| `bilgi.txt` | Tarih, PostgreSQL sürümü |
| `ozet.sha256` | Dosyaların SHA-256 özetleri (bozulma denetimi) |

`.dump` dosyaları PostgreSQL'in kendi biçimindedir (`pg_dump -Fc`), `pg_restore` ile açılır.

## Windows'ta şifreyi açma

1. **Gpg4win** kurun (gpg4win.org). Yalnız "GnuPG" bileşeni yeterlidir.
2. Yedek dosyasını GitHub Releases'tan ya da Drive'dan indirin.
3. Dosyanın olduğu klasörde komut satırı açın (adres çubuğuna `cmd`):

   ```
   gpg -o yedek.tar -d depo_2026-10-29_0317.tar.gpg
   ```

   Parola sorulur: **YEDEK_SIFRESI** (kâğıtta yazılı olan).
4. `yedek.tar` dosyasını 7-Zip ile ya da `tar -xf yedek.tar` ile açın.

Linux / macOS'ta aynı komut: `gpg -o yedek.tar -d depo_….tar.gpg && tar -xf yedek.tar`.

## Geri yükleme (yeni sunucu ya da yeni Supabase projesi)

Hedef boş bir PostgreSQL veritabanıdır (sürümü yedeğinkiyle aynı ya da daha yeni;
`bilgi.txt` → `sunucu_ana_surum`).

```
# 1) Supabase dışı bir sunucuysa, Supabase'in hazır rollerini ve eklenti şemasını açın
psql "$HEDEF" -c "create role anon nologin; create role authenticated nologin; create role service_role nologin;"
psql "$HEDEF" -c "create schema if not exists extensions;"

# 2) Önce kullanıcı hesapları, sonra uygulama tabloları
pg_restore --no-owner --no-privileges -d "$HEDEF" auth.dump
pg_restore --no-owner --no-privileges -d "$HEDEF" public.dump
```

- Hedef **yeni bir Supabase projesiyse** `auth` şeması zaten vardır. `auth.dump` yerine
  yalnız kullanıcı verisini yükleyin: `pg_restore --data-only -n auth -t users -d "$HEDEF" auth.dump`.
- `schema "public" already exists` uyarısı normaldir.
- Yükledikten sonra `tool/yedek_sayim.sql` çalıştırılır, sonuç `sayim.txt` ile karşılaştırılır.
- Bildirim zamanlayıcısı (pg_cron, `supabase_guncelleme_1_20_0.sql`) yedekte yoktur. Yeni
  projede o dosyanın ilgili kısmı yeniden çalıştırılır.

## Bakım notları

- **Drive bağlantısı** kendi Google Cloud projemizle kurulu (`depo-yedek`, OAuth uygulaması
  "Depo Yedek", yayın durumu *In production*, kapsam `drive.file`). Bu kapsamla uygulama
  Drive'da **yalnız kendi açtığı dosyaları** görür, Drive'ın geri kalanına erişemez.
- Drive bağlantısını yenilemek (anahtar sızdıysa ya da bağlantı koptuysa):
  1. myaccount.google.com/permissions → **Depo Yedek** → erişimi kaldır.
  2. Google Cloud Console → `depo-yedek` → Google Auth Platform → **Clients** → yeni
     Desktop client (ya da yeni secret).
  3. Bilgisayarda `rclone config` → `n` → `gdrive` → `drive` → client_id / client_secret →
     scope `drive.file` → tarayıcıda izin.
  4. `rclone config show gdrive` çıktısı → GitHub Secrets → **RCLONE_CONFIG** güncelle
     (bu çıktının fotoğrafı çekilmez, hiçbir yere yapıştırılmaz).
  5. `rclone config delete gdrive`.

  **Dikkat:** erişim kaldırılınca uygulama eski dosyaları artık göremez. Drive'da yeni bir
  `DEPO-APP-yedek` klasörü açılır. Eski klasördeki yedekler kendiliğinden silinmez; işi
  bitince elle silinir.
- Herkese açık depolarda GitHub, 60 gün hiç hareket olmazsa zamanlanmış görevleri kapatır.
  Yedek görevi her gece kendini yeniden etkinleştirir. Yine de Actions sekmesinde
  "This scheduled workflow is disabled" uyarısı görülürse **Enable workflow**'a basılır.
- Program belediyeye geçince yedek yeri belediyenin hesabına / sunucusuna taşınır.
