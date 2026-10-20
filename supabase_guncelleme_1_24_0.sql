-- DEPO OTOMASYON SİSTEMİ 1.24.0: montaj tutanağı
-- Supabase > SQL Editor'da bir kez çalıştırın (Ctrl+A ile hepsini seçip Run).
-- Tekrar çalıştırmak zararsızdır.
--
-- * kullanim_kayitlari.tutanak : alindi | alinacak | kurum_ici (eski kayıtlarda boş)
-- * Miktarlı malzemeler (kablo, adaptör…) mevcut tablolarla çalışır:
--   urunler.seri_takipli = 0 olan ürünlerin hareketleri stok_hareketleri'ne
--   cihaz_id boş, miktar dolu olarak yazılır. Yeni tablo gerekmez.

alter table kullanim_kayitlari add column if not exists tutanak text;
alter table kullanim_kayitlari add column if not exists tutanak_tarihi bigint;
alter table kullanim_kayitlari add column if not exists tutanak_kullanici_id text;

-- Sunucunun sütun listesini hemen yenile
notify pgrst, 'reload schema';
