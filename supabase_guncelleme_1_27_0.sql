-- DEPO OTOMASYON SİSTEMİ 1.27.0: malzemede kutu / top içeriği
-- Supabase > SQL Editor'da bir kez çalıştırın (Ctrl+A ile hepsini seçip Run).
-- Tekrar çalıştırmak zararsızdır.
--
-- * urunler.kutu_icerigi : miktarlı malzemede bir kutu / topun içeriği
--   (ör. 305 metre). Barkodu her okutuşta bu kadar eklenir. Boşsa 1.
-- * Bu SQL çalıştırılana kadar uygulama çalışır; yalnız kutu içeriği
--   diğer telefonlara gitmez.

alter table urunler add column if not exists kutu_icerigi integer;

-- Sunucunun sütun listesini hemen yenile
notify pgrst, 'reload schema';
